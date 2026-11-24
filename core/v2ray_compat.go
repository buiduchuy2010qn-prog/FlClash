package core

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/url"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/common/convert"
	"go.yaml.in/yaml/v3"
)

func decodeCompatShareLine(rawLine string) []map[string]any {
	line := strings.TrimSpace(rawLine)
	if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
		return []map[string]any{}
	}
	scheme, _, hasScheme := strings.Cut(line, "://")
	if hasScheme {
		switch strings.ToLower(scheme) {
		case "v2rayn":
			return decodeV2RayNWrapper(line)
		case "wireguard", "wg":
			return parseWireGuardShareLink(line)
		case "socks4", "socks4a":
			return parseSocks4ShareLink(line)
		}
	}
	if strings.HasPrefix(line, "{") || strings.HasPrefix(line, "[") {
		if proxies, ok := parseXrayJSONOutbounds([]byte(line)); ok {
			return proxies
		}
	}
	return []map[string]any{}
}

func decodeShareLineAny(line string) []map[string]any {
	trimmed := strings.TrimSpace(line)
	if trimmed == "" {
		return []map[string]any{}
	}
	if proxies, ok := decodeSingleShareLine(trimmed); ok {
		return proxies
	}
	return decodeCompatShareLine(trimmed)
}

func decodeV2RayNWrapper(line string) []map[string]any {
	_, body, _ := strings.Cut(line, "://")
	payload, fragment, hasFragment := strings.Cut(body, "#")
	decoded, ok := decodeCompatBase64(payload)
	if !ok {
		return []map[string]any{}
	}
	text := strings.TrimSpace(string(decoded))
	if text == "" {
		return []map[string]any{}
	}
	if strings.HasPrefix(text, "{") || strings.HasPrefix(text, "[") {
		if proxies, ok := parseXrayJSONOutbounds([]byte(text)); ok {
			return applyFallbackFragmentName(proxies, fragment, hasFragment)
		}
	}
	if proxies, ok := parseWireGuardConf([]byte(text)); ok {
		return applyFallbackFragmentName(proxies, fragment, hasFragment)
	}
	var out []map[string]any
	for _, inner := range strings.Split(text, "\n") {
		trimmed := strings.TrimSpace(inner)
		if trimmed == "" {
			continue
		}
		out = append(out, decodeShareLineAny(trimmed)...)
	}
	return applyFallbackFragmentName(out, fragment, hasFragment)
}

func applyFallbackFragmentName(proxies []map[string]any, fragment string, hasFragment bool) []map[string]any {
	if !hasFragment || len(proxies) != 1 {
		return proxies
	}
	if unescaped, err := url.QueryUnescape(strings.TrimSpace(fragment)); err == nil && unescaped != "" {
		if existing, _ := proxies[0]["name"].(string); strings.TrimSpace(existing) == "" {
			proxies[0]["name"] = unescaped
		}
	}
	return proxies
}

func normalizeRawShareAuthority(rawLine string) string {
	schemeEnd := strings.Index(rawLine, "://")
	if schemeEnd < 0 {
		return rawLine
	}
	rest := rawLine[schemeEnd+3:]
	atIdx := strings.Index(rest, "@")
	if atIdx < 0 {
		return rawLine
	}
	qIdx := strings.IndexAny(rest, "?#")
	if qIdx >= 0 && atIdx >= qIdx {
		return rawLine
	}
	userInfo := strings.ReplaceAll(rest[:atIdx], "/", "%2F")
	return rawLine[:schemeEnd+3] + userInfo + rest[atIdx:]
}

func restoreBase64Plus(val string) string {
	if strings.Contains(val, " ") && !strings.Contains(val, "://") {
		return strings.ReplaceAll(val, " ", "+")
	}
	return val
}

func parseWireGuardShareLink(rawLine string) []map[string]any {
	u, err := url.Parse(normalizeRawShareAuthority(rawLine))
	if err != nil {
		return []map[string]any{}
	}
	server := strings.TrimSpace(u.Hostname())
	port := 51820
	if rawPort := u.Port(); rawPort != "" {
		parsedPort, portErr := strconv.Atoi(rawPort)
		if portErr != nil || parsedPort < 1 || parsedPort > 65535 {
			return []map[string]any{}
		}
		port = parsedPort
	}
	query := u.Query()
	privateKey := ""
	if u.User != nil {
		privateKey = strings.TrimSpace(u.User.Username())
	}
	if privateKey == "" {
		privateKey = firstQueryParam(query, "privatekey", "private-key", "secretkey")
	}
	privateKey = restoreBase64Plus(privateKey)
	publicKey := restoreBase64Plus(firstQueryParam(query, "publickey", "public-key", "pk"))
	if server == "" || privateKey == "" || publicKey == "" {
		return []map[string]any{}
	}
	name := strings.TrimSpace(u.Fragment)
	if name == "" {
		name = "wireguard-" + server
	}
	proxy := map[string]any{
		"name":               name,
		"type":               "wireguard",
		"server":             server,
		"port":               port,
		"private-key":        privateKey,
		"public-key":         publicKey,
		"udp":                true,
		"remote-dns-resolve": true,
	}
	if psk := restoreBase64Plus(firstQueryParam(query, "presharedkey", "pre-shared-key", "psk")); psk != "" {
		proxy["pre-shared-key"] = psk
	}
	ipv4, ipv6 := splitWireGuardAddresses(firstQueryParam(query, "address", "ip"))
	if ipv4 != "" {
		proxy["ip"] = ipv4
	}
	if ipv6 != "" {
		proxy["ipv6"] = ipv6
	}
	if rawMTU := firstQueryParam(query, "mtu"); rawMTU != "" {
		if mtu, mtuErr := strconv.Atoi(rawMTU); mtuErr == nil && mtu > 0 {
			proxy["mtu"] = mtu
		}
	}
	if reserved := parseWireGuardReserved(firstQueryParam(query, "reserved")); len(reserved) == 3 {
		proxy["reserved"] = reserved
	}
	return []map[string]any{proxy}
}

func parseSocks4ShareLink(rawLine string) []map[string]any {
	u, err := url.Parse(rawLine)
	if err != nil {
		return []map[string]any{}
	}
	server := strings.TrimSpace(u.Hostname())
	port := 1080
	if rawPort := u.Port(); rawPort != "" {
		parsedPort, portErr := strconv.Atoi(rawPort)
		if portErr != nil || parsedPort < 1 || parsedPort > 65535 {
			return []map[string]any{}
		}
		port = parsedPort
	}
	if server == "" {
		return []map[string]any{}
	}
	name := strings.TrimSpace(u.Fragment)
	if name == "" {
		name = fmt.Sprintf("socks-%s:%d", server, port)
	}
	proxy := map[string]any{
		"name":   name,
		"type":   "socks5",
		"server": server,
		"port":   port,
		"udp":    false,
	}
	if u.User != nil {
		if username := u.User.Username(); username != "" {
			proxy["username"] = username
		}
		if password, ok := u.User.Password(); ok && password != "" {
			proxy["password"] = password
		}
	}
	return []map[string]any{proxy}
}

func firstQueryParam(query url.Values, keys ...string) string {
	for _, key := range keys {
		for qKey, vals := range query {
			if strings.EqualFold(qKey, key) && len(vals) > 0 {
				if val := strings.TrimSpace(vals[0]); val != "" {
					return val
				}
			}
		}
	}
	return ""
}

func splitWireGuardAddresses(raw string) (string, string) {
	var ipv4, ipv6 string
	for _, part := range strings.Split(raw, ",") {
		addr := strings.TrimSpace(part)
		if addr == "" {
			continue
		}
		if strings.Contains(addr, ":") {
			if ipv6 == "" {
				ipv6 = addr
			}
		} else if ipv4 == "" {
			ipv4 = addr
		}
	}
	return ipv4, ipv6
}

func parseWireGuardReserved(raw string) []int {
	cleaned := strings.TrimSpace(raw)
	if cleaned == "" {
		return nil
	}
	stripped := strings.Trim(cleaned, "[]")
	if strings.Contains(stripped, ",") {
		parts := strings.Split(stripped, ",")
		if len(parts) != 3 {
			return nil
		}
		out := make([]int, 0, 3)
		for _, part := range parts {
			val, err := strconv.Atoi(strings.TrimSpace(part))
			if err != nil || val < 0 || val > 255 {
				return nil
			}
			out = append(out, val)
		}
		return out
	}
	if decoded, ok := decodeCompatBase64(cleaned); ok && len(decoded) == 3 {
		return []int{int(decoded[0]), int(decoded[1]), int(decoded[2])}
	}
	return nil
}

func decodeCompatBase64(raw string) ([]byte, bool) {
	cleaned := strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\t', '\r', '\n':
			return -1
		case '-':
			return '+'
		case '_':
			return '/'
		default:
			return r
		}
	}, raw)
	cleaned = strings.TrimRight(cleaned, "=")
	if cleaned == "" {
		return nil, false
	}
	switch len(cleaned) % 4 {
	case 2:
		cleaned += "=="
	case 3:
		cleaned += "="
	case 1:
		return nil, false
	}
	decoded, err := base64.StdEncoding.DecodeString(cleaned)
	if err != nil {
		return nil, false
	}
	return decoded, true
}

type wgConfPeer struct {
	publicKey    string
	presharedKey string
	endpoint     string
	keepalive    int
}

func parseWireGuardConf(buf []byte) ([]map[string]any, bool) {
	var section string
	var privateKey, ipv4, ipv6, rawReserved string
	var mtu int
	var peers []wgConfPeer
	currentPeer := -1

	for _, raw := range strings.Split(string(buf), "\n") {
		line := strings.TrimSpace(raw)
		if idx := strings.IndexAny(line, "#;"); idx >= 0 && !strings.HasPrefix(line, "[") {
			line = strings.TrimSpace(line[:idx])
		}
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			section = strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
			if section == "peer" {
				peers = append(peers, wgConfPeer{})
				currentPeer = len(peers) - 1
			}
			continue
		}
		key, val, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.ToLower(strings.TrimSpace(key))
		val = strings.TrimSpace(val)
		switch section {
		case "interface":
			switch key {
			case "privatekey":
				privateKey = val
			case "address":
				ipv4, ipv6 = splitWireGuardAddresses(val)
			case "mtu":
				if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 {
					mtu = parsed
				}
			case "reserved":
				rawReserved = val
			}
		case "peer":
			if currentPeer < 0 {
				continue
			}
			switch key {
			case "publickey":
				peers[currentPeer].publicKey = val
			case "presharedkey":
				peers[currentPeer].presharedKey = val
			case "endpoint":
				peers[currentPeer].endpoint = val
			case "persistentkeepalive":
				if parsed, err := strconv.Atoi(val); err == nil && parsed > 0 {
					peers[currentPeer].keepalive = parsed
				}
			}
		}
	}

	if privateKey == "" || len(peers) == 0 {
		return nil, false
	}
	proxies := make([]map[string]any, 0, len(peers))
	for index, peer := range peers {
		if peer.publicKey == "" || peer.endpoint == "" {
			continue
		}
		host, rawPort, err := net.SplitHostPort(peer.endpoint)
		if err != nil {
			continue
		}
		port, err := strconv.Atoi(rawPort)
		if err != nil || port < 1 || port > 65535 {
			continue
		}
		name := "WireGuard"
		if len(peers) > 1 {
			name = fmt.Sprintf("WireGuard-%d", index+1)
		}
		proxy := map[string]any{
			"name":               name,
			"type":               "wireguard",
			"server":             host,
			"port":               port,
			"private-key":        privateKey,
			"public-key":         peer.publicKey,
			"udp":                true,
			"remote-dns-resolve": true,
		}
		if peer.presharedKey != "" {
			proxy["pre-shared-key"] = peer.presharedKey
		}
		if ipv4 != "" {
			proxy["ip"] = ipv4
		}
		if ipv6 != "" {
			proxy["ipv6"] = ipv6
		}
		if mtu > 0 {
			proxy["mtu"] = mtu
		}
		if peer.keepalive > 0 {
			proxy["persistent-keepalive"] = peer.keepalive
		}
		if reserved := parseWireGuardReserved(rawReserved); len(reserved) == 3 {
			proxy["reserved"] = reserved
		}
		proxies = append(proxies, proxy)
	}
	return proxies, len(proxies) > 0
}

func parseXrayJSONOutbounds(buf []byte) ([]map[string]any, bool) {
	var raw any
	if err := json.Unmarshal(buf, &raw); err != nil {
		return nil, false
	}
	var outbounds []map[string]any
	switch v := raw.(type) {
	case map[string]any:
		if hasClashTopKeys(v) {
			return nil, false
		}
		if rawList, ok := v["outbounds"].([]any); ok {
			for _, item := range rawList {
				if m, ok := item.(map[string]any); ok {
					outbounds = append(outbounds, m)
				}
			}
		} else if _, ok := v["protocol"].(string); ok {
			outbounds = append(outbounds, v)
		}
	case []any:
		for _, item := range v {
			if m, ok := item.(map[string]any); ok {
				outbounds = append(outbounds, m)
			}
		}
	}
	if len(outbounds) == 0 {
		return nil, false
	}
	proxies := make([]map[string]any, 0, len(outbounds))
	for idx, outbound := range outbounds {
		if proxy, ok := convertXrayOutbound(outbound, idx); ok {
			proxies = append(proxies, proxy)
		}
	}
	return proxies, len(proxies) > 0
}

func hasClashTopKeys(m map[string]any) bool {
	for _, key := range []string{"proxies", "proxy-providers", "proxy-groups", "rules"} {
		if _, exists := m[key]; exists {
			return true
		}
	}
	return false
}

func convertXrayOutbound(outbound map[string]any, index int) (map[string]any, bool) {
	protocol := strings.ToLower(stringField(outbound, "protocol"))
	switch protocol {
	case "", "freedom", "blackhole", "dns", "loopback":
		return nil, false
	}
	settings := mapField(outbound, "settings")
	stream := mapField(outbound, "streamSettings")
	tag := stringField(outbound, "tag")
	if tag == "" || tag == "proxy" {
		tag = fmt.Sprintf("%s-%d", protocol, index+1)
	}

	var proxy map[string]any
	switch protocol {
	case "vless", "vmess":
		vnext := sliceMapFirst(settings, "vnext")
		server := stringField(vnext, "address")
		port := intField(vnext, "port")
		user := sliceMapFirst(vnext, "users")
		uuid := stringField(user, "id")
		if server == "" || port <= 0 || uuid == "" {
			return nil, false
		}
		proxy = map[string]any{
			"name":   tag,
			"type":   protocol,
			"server": server,
			"port":   port,
			"uuid":   uuid,
			"udp":    true,
		}
		if protocol == "vmess" {
			cipher := stringField(user, "security")
			if cipher == "" {
				cipher = "auto"
			}
			proxy["alterId"] = intField(user, "alterId")
			proxy["cipher"] = cipher
		} else if flow := stringField(user, "flow"); flow != "" {
			proxy["flow"] = flow
		}
		applyXrayStreamSettings(proxy, stream, protocol)
	case "trojan":
		srv := sliceMapFirst(settings, "servers")
		server := stringField(srv, "address")
		port := intField(srv, "port")
		password := stringField(srv, "password")
		if server == "" || port <= 0 || password == "" {
			return nil, false
		}
		proxy = map[string]any{
			"name":     tag,
			"type":     "trojan",
			"server":   server,
			"port":     port,
			"password": password,
			"udp":      true,
		}
		applyXrayStreamSettings(proxy, stream, protocol)
	case "shadowsocks":
		srv := sliceMapFirst(settings, "servers")
		server := stringField(srv, "address")
		port := intField(srv, "port")
		method := stringField(srv, "method")
		password := stringField(srv, "password")
		if server == "" || port <= 0 || method == "" {
			return nil, false
		}
		proxy = map[string]any{
			"name":     tag,
			"type":     "ss",
			"server":   server,
			"port":     port,
			"cipher":   method,
			"password": password,
			"udp":      true,
		}
	case "socks", "http":
		srv := sliceMapFirst(settings, "servers")
		server := stringField(srv, "address")
		port := intField(srv, "port")
		if server == "" || port <= 0 {
			return nil, false
		}
		kind := "socks5"
		if protocol == "http" {
			kind = "http"
		}
		proxy = map[string]any{
			"name":   tag,
			"type":   kind,
			"server": server,
			"port":   port,
		}
		if user := sliceMapFirst(srv, "users"); user != nil {
			if u := stringField(user, "user"); u != "" {
				proxy["username"] = u
			}
			if p := stringField(user, "pass"); p != "" {
				proxy["password"] = p
			}
		}
		applyXrayStreamSettings(proxy, stream, kind)
	case "wireguard":
		secretKey := stringField(settings, "secretKey")
		peer := sliceMapFirst(settings, "peers")
		publicKey := stringField(peer, "publicKey")
		endpoint := stringField(peer, "endpoint")
		if secretKey == "" || publicKey == "" || endpoint == "" {
			return nil, false
		}
		host, rawPort, err := net.SplitHostPort(endpoint)
		if err != nil {
			return nil, false
		}
		port, err := strconv.Atoi(rawPort)
		if err != nil || port <= 0 {
			return nil, false
		}
		proxy = map[string]any{
			"name":               tag,
			"type":               "wireguard",
			"server":             host,
			"port":               port,
			"private-key":        secretKey,
			"public-key":         publicKey,
			"udp":                true,
			"remote-dns-resolve": true,
		}
		if psk := stringField(peer, "preSharedKey"); psk != "" {
			proxy["pre-shared-key"] = psk
		}
		if mtu := intField(settings, "mtu"); mtu > 0 {
			proxy["mtu"] = mtu
		}
		if addrs := stringSliceField(settings, "address"); len(addrs) > 0 {
			ipv4, ipv6 := splitWireGuardAddresses(strings.Join(addrs, ","))
			if ipv4 != "" {
				proxy["ip"] = ipv4
			}
			if ipv6 != "" {
				proxy["ipv6"] = ipv6
			}
		}
	default:
		return nil, false
	}
	return proxy, true
}

func applyXrayStreamSettings(proxy, stream map[string]any, protocol string) {
	if len(stream) == 0 {
		return
	}
	security := strings.ToLower(stringField(stream, "security"))
	switch security {
	case "tls":
		proxy["tls"] = true
		tls := mapField(stream, "tlsSettings")
		setStreamSNI(proxy, stringField(tls, "serverName"), protocol)
		if boolField(tls, "allowInsecure") {
			proxy["skip-cert-verify"] = true
		}
		if alpn := stringSliceField(tls, "alpn"); len(alpn) > 0 {
			proxy["alpn"] = alpn
		}
		if fp := stringField(tls, "fingerprint"); fp != "" {
			proxy["client-fingerprint"] = fp
		} else {
			proxy["client-fingerprint"] = "chrome"
		}
	case "reality":
		proxy["tls"] = true
		reality := mapField(stream, "realitySettings")
		setStreamSNI(proxy, stringField(reality, "serverName"), protocol)
		if fp := stringField(reality, "fingerprint"); fp != "" {
			proxy["client-fingerprint"] = fp
		} else {
			proxy["client-fingerprint"] = "chrome"
		}
		opts := map[string]any{}
		if pk := stringField(reality, "publicKey"); pk != "" {
			opts["public-key"] = pk
		}
		if sid := stringField(reality, "shortId"); sid != "" {
			opts["short-id"] = sid
		}
		if len(opts) > 0 {
			proxy["reality-opts"] = opts
		}
	}

	network := strings.ToLower(stringField(stream, "network"))
	switch network {
	case "ws", "httpupgrade":
		proxy["network"] = "ws"
		key := "wsSettings"
		if network == "httpupgrade" {
			key = "httpupgradeSettings"
		}
		ws := mapField(stream, key)
		wsOpts := map[string]any{}
		if path := stringField(ws, "path"); path != "" {
			wsOpts["path"] = path
		}
		headers := stringMapField(ws, "headers")
		if host := stringField(ws, "host"); host != "" {
			if headers == nil {
				headers = map[string]string{}
			}
			headers["Host"] = host
		}
		if len(headers) > 0 {
			wsOpts["headers"] = headers
		}
		if network == "httpupgrade" {
			wsOpts["v2ray-http-upgrade"] = true
		}
		if len(wsOpts) > 0 {
			proxy["ws-opts"] = wsOpts
		}
	case "grpc":
		proxy["network"] = "grpc"
		grpc := mapField(stream, "grpcSettings")
		if svc := stringField(grpc, "serviceName"); svc != "" {
			proxy["grpc-opts"] = map[string]any{"grpc-service-name": svc}
		}
	case "h2", "http":
		proxy["network"] = "h2"
		httpSettings := mapField(stream, "httpSettings")
		h2Opts := map[string]any{}
		if path := stringField(httpSettings, "path"); path != "" {
			h2Opts["path"] = path
		}
		if hosts := stringSliceField(httpSettings, "host"); len(hosts) > 0 {
			h2Opts["host"] = hosts
		}
		if len(h2Opts) > 0 {
			proxy["h2-opts"] = h2Opts
		}
	}
}

func setStreamSNI(proxy map[string]any, serverName, protocol string) {
	if serverName == "" {
		return
	}
	if protocol == "trojan" {
		proxy["sni"] = serverName
	} else {
		proxy["servername"] = serverName
	}
}

func stringField(m map[string]any, key string) string {
	if m == nil {
		return ""
	}
	val, ok := m[key].(string)
	if !ok {
		return ""
	}
	return strings.TrimSpace(val)
}

func intField(m map[string]any, key string) int {
	if m == nil {
		return 0
	}
	switch v := m[key].(type) {
	case float64:
		return int(v)
	case int:
		return v
	case string:
		n, _ := strconv.Atoi(strings.TrimSpace(v))
		return n
	default:
		return 0
	}
}

func boolField(m map[string]any, key string) bool {
	if m == nil {
		return false
	}
	val, _ := m[key].(bool)
	return val
}

func mapField(m map[string]any, key string) map[string]any {
	if m == nil {
		return nil
	}
	val, _ := m[key].(map[string]any)
	return val
}

func sliceMapFirst(m map[string]any, key string) map[string]any {
	if m == nil {
		return nil
	}
	list, ok := m[key].([]any)
	if !ok || len(list) == 0 {
		return nil
	}
	first, _ := list[0].(map[string]any)
	return first
}

func stringSliceField(m map[string]any, key string) []string {
	if m == nil {
		return nil
	}
	list, ok := m[key].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(list))
	for _, item := range list {
		if s, ok := item.(string); ok && strings.TrimSpace(s) != "" {
			out = append(out, strings.TrimSpace(s))
		}
	}
	return out
}

func stringMapField(m map[string]any, key string) map[string]string {
	raw := mapField(m, key)
	if len(raw) == 0 {
		return nil
	}
	out := make(map[string]string, len(raw))
	for k, v := range raw {
		if s, ok := v.(string); ok {
			out[k] = s
		}
	}
	return out
}

func decodeSingleShareLine(trimmed string) ([]map[string]any, bool) {
	prepared := preprocessV2RayShareLine(trimmed)
	proxies, err := convert.ConvertsV2Ray([]byte(prepared))
	if err != nil || len(proxies) == 0 {
		return nil, false
	}
	for _, proxy := range proxies {
		patchV2RayShareLinkProxy(trimmed, proxy)
	}
	return proxies, true
}

func convertV2RayBytes(buf []byte) ([]map[string]any, error) {
	raw := strings.TrimSpace(string(buf))
	if raw == "" {
		return convert.ConvertsV2Ray(buf)
	}
	if !strings.Contains(raw, "://") {
		if decoded, ok := decodeCompatBase64(raw); ok && strings.Contains(string(decoded), "://") {
			raw = strings.TrimSpace(string(decoded))
		}
	}
	lines := strings.Split(strings.ReplaceAll(raw, "\r\n", "\n"), "\n")
	proxies := make([]map[string]any, 0, len(lines))
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || !strings.Contains(trimmed, "://") {
			continue
		}
		proxies = append(proxies, decodeShareLineAny(trimmed)...)
	}
	if len(proxies) > 0 {
		return proxies, nil
	}
	return convert.ConvertsV2Ray(buf)
}

func preprocessV2RayShareLine(rawLine string) string {
	u, err := url.Parse(normalizeRawShareAuthority(rawLine))
	if err != nil || u.RawQuery == "" {
		return rawLine
	}
	scheme := strings.ToLower(u.Scheme)
	if scheme != "vless" && scheme != "vmess" && scheme != "trojan" {
		return rawLine
	}
	query := u.Query()
	changed := false
	for k, vals := range query {
		if strings.EqualFold(k, "type") && len(vals) > 0 && strings.EqualFold(strings.TrimSpace(vals[0]), "splithttp") {
			query.Del(k)
			query.Set("type", "xhttp")
			changed = true
			break
		}
	}
	if !changed {
		return rawLine
	}
	u.RawQuery = query.Encode()
	return u.String()
}

func patchV2RayShareLinkProxy(rawLine string, proxy map[string]any) {
	if len(proxy) == 0 {
		return
	}
	if vmessObj, ok := decodeVMessJSONPayload(rawLine); ok {
		if anyTruthy(vmessObj["allowInsecure"]) || anyTruthy(vmessObj["insecure"]) || anyTruthy(vmessObj["skip-cert-verify"]) {
			proxy["skip-cert-verify"] = true
		}
		host := stringField(vmessObj, "host")
		if boolField(proxy, "tls") && stringField(proxy, "servername") == "" {
			if sni := stringField(vmessObj, "sni"); sni != "" {
				proxy["servername"] = sni
			} else if firstHost := firstCommaToken(host); firstHost != "" {
				proxy["servername"] = firstHost
			}
		}
		if strings.EqualFold(stringField(vmessObj, "net"), "tcp") && strings.EqualFold(stringField(vmessObj, "type"), "http") {
			applyHTTPOptsFromValues(proxy, host, stringField(vmessObj, "path"))
		}
		normalizeProxyHostLists(proxy)
		return
	}

	u, err := url.Parse(normalizeRawShareAuthority(rawLine))
	if err != nil {
		normalizeProxyHostLists(proxy)
		return
	}
	query := u.Query()
	if isTruthyFlag(firstQueryParam(query, "allowInsecure", "insecure", "skip-cert-verify")) {
		proxy["skip-cert-verify"] = true
	}
	rawHost := firstQueryParam(query, "host")
	firstHost := firstCommaToken(rawHost)
	security := strings.ToLower(firstQueryParam(query, "security"))
	scheme := strings.ToLower(u.Scheme)
	tlsActive := boolField(proxy, "tls") || (scheme == "trojan" && security != "none") || security == "tls" || security == "reality"
	if sniKey := proxySNIKey(proxy); sniKey != "" && stringField(proxy, sniKey) == "" {
		if sni := firstQueryParam(query, "sni", "peer"); sni != "" {
			proxy[sniKey] = sni
		} else if tlsActive && firstHost != "" {
			proxy[sniKey] = firstHost
		}
	}

	netType := strings.ToLower(firstQueryParam(query, "type", "net"))
	headerType := strings.ToLower(firstQueryParam(query, "headerType"))
	switch {
	case netType == "ws" || netType == "httpupgrade":
		proxy["network"] = "ws"
		wsOpts := ensureSubMap(proxy, "ws-opts")
		if path := firstQueryParam(query, "path"); path != "" && stringField(wsOpts, "path") == "" {
			wsOpts["path"] = path
		}
		if firstHost != "" {
			headers := ensureStringSubMap(wsOpts, "headers")
			if strings.TrimSpace(headers["Host"]) == "" {
				headers["Host"] = firstHost
			}
		}
		if netType == "httpupgrade" {
			wsOpts["v2ray-http-upgrade"] = true
		}
	case (netType == "tcp" || netType == "") && headerType == "http":
		applyHTTPOptsFromValues(proxy, rawHost, firstQueryParam(query, "path"))
	}
	normalizeProxyHostLists(proxy)
}

func decodeVMessJSONPayload(rawLine string) (map[string]any, bool) {
	if !strings.HasPrefix(strings.ToLower(rawLine), "vmess://") {
		return nil, false
	}
	body := rawLine[len("vmess://"):]
	if idx := strings.IndexByte(body, '#'); idx >= 0 {
		body = body[:idx]
	}
	if strings.ContainsAny(body, "@?") {
		return nil, false
	}
	decoded, ok := decodeCompatBase64(body)
	if !ok {
		return nil, false
	}
	var obj map[string]any
	if err := json.Unmarshal(decoded, &obj); err != nil {
		return nil, false
	}
	return obj, true
}

func proxySNIKey(proxy map[string]any) string {
	switch strings.ToLower(stringField(proxy, "type")) {
	case "trojan", "hysteria", "hysteria2", "tuic", "anytls":
		return "sni"
	case "vless", "vmess":
		return "servername"
	default:
		return ""
	}
}

func applyHTTPOptsFromValues(proxy map[string]any, rawHost, rawPath string) {
	proxy["network"] = "http"
	httpOpts := ensureSubMap(proxy, "http-opts")
	if stringField(httpOpts, "method") == "" {
		httpOpts["method"] = "GET"
	}
	if _, exists := httpOpts["path"]; !exists {
		if paths := splitCommaTrimmed(rawPath); len(paths) > 0 {
			httpOpts["path"] = paths
		} else {
			httpOpts["path"] = []string{"/"}
		}
	}
	if hosts := splitCommaTrimmed(rawHost); len(hosts) > 0 {
		headers := ensureSubMap(httpOpts, "headers")
		headers["Host"] = hosts
	}
}

func normalizeProxyHostLists(proxy map[string]any) {
	if httpOpts, ok := proxy["http-opts"].(map[string]any); ok {
		if headers, ok := httpOpts["headers"].(map[string]any); ok {
			if rawHost, exists := headers["Host"]; exists {
				if normalized := normalizeCommaStringSlice(rawHost); len(normalized) > 0 {
					headers["Host"] = normalized
				}
			}
		}
		if _, exists := httpOpts["method"]; !exists {
			httpOpts["method"] = "GET"
		}
		if _, exists := httpOpts["path"]; !exists {
			httpOpts["path"] = []string{"/"}
		}
	}
	if h2Opts, ok := proxy["h2-opts"].(map[string]any); ok {
		if rawHost, exists := h2Opts["host"]; exists {
			if normalized := normalizeCommaStringSlice(rawHost); len(normalized) > 0 {
				h2Opts["host"] = normalized
			}
		}
	}
}

func ensureSubMap(parent map[string]any, key string) map[string]any {
	if existing, ok := parent[key].(map[string]any); ok && existing != nil {
		return existing
	}
	sub := map[string]any{}
	if existingStr, ok := parent[key].(map[string]string); ok {
		for k, v := range existingStr {
			sub[k] = v
		}
	}
	parent[key] = sub
	return sub
}

func ensureStringSubMap(parent map[string]any, key string) map[string]string {
	if existing, ok := parent[key].(map[string]string); ok && existing != nil {
		return existing
	}
	sub := map[string]string{}
	if existingAny, ok := parent[key].(map[string]any); ok {
		for k, v := range existingAny {
			if s, ok := v.(string); ok {
				sub[k] = s
			}
		}
	}
	parent[key] = sub
	return sub
}

func normalizeCommaStringSlice(val any) []string {
	var out []string
	switch v := val.(type) {
	case string:
		out = append(out, splitCommaTrimmed(v)...)
	case []string:
		for _, item := range v {
			out = append(out, splitCommaTrimmed(item)...)
		}
	case []any:
		for _, item := range v {
			if s, ok := item.(string); ok {
				out = append(out, splitCommaTrimmed(s)...)
			}
		}
	}
	return out
}

func splitCommaTrimmed(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			out = append(out, trimmed)
		}
	}
	return out
}

func firstCommaToken(raw string) string {
	tokens := splitCommaTrimmed(raw)
	if len(tokens) == 0 {
		return ""
	}
	return tokens[0]
}

func isTruthyFlag(val string) bool {
	switch strings.ToLower(strings.TrimSpace(val)) {
	case "1", "true", "yes":
		return true
	default:
		return false
	}
}

func anyTruthy(val any) bool {
	switch v := val.(type) {
	case bool:
		return v
	case float64:
		return v != 0
	case int:
		return v != 0
	case string:
		return isTruthyFlag(v)
	default:
		return false
	}
}

func buildClashConfigFromProxies(proxies []map[string]any) ([]byte, bool) {
	if len(proxies) == 0 {
		return nil, false
	}
	used := make(map[string]int, len(proxies))
	names := make([]string, 0, len(proxies))
	for idx, proxy := range proxies {
		base, _ := proxy["name"].(string)
		base = strings.TrimSpace(base)
		if base == "" {
			base = fmt.Sprintf("Node-%d", idx+1)
		}
		name := base
		if count, exists := used[base]; exists {
			used[base] = count + 1
			name = fmt.Sprintf("%s (%d)", base, count+1)
			for used[name] > 0 {
				count++
				name = fmt.Sprintf("%s (%d)", base, count+1)
			}
		} else {
			used[base] = 1
		}
		used[name] = 1
		proxy["name"] = name
		names = append(names, name)
	}
	selectList := make([]string, 0, len(names)+2)
	selectList = append(selectList, "Auto", "Fallback")
	selectList = append(selectList, names...)
	doc := map[string]any{
		"proxies": proxies,
		"proxy-groups": []map[string]any{
			{
				"name":    "Proxy",
				"type":    "select",
				"proxies": selectList,
			},
			{
				"name":            "Auto",
				"type":            "url-test",
				"url":             "https://www.gstatic.com/generate_204",
				"interval":        180,
				"tolerance":       50,
				"expected-status": "200-299",
				"proxies":         names,
			},
			{
				"name":            "Fallback",
				"type":            "fallback",
				"url":             "https://www.gstatic.com/generate_204",
				"interval":        180,
				"expected-status": "200-299",
				"proxies":         names,
			},
		},
		"rules": []string{"MATCH,Proxy"},
	}
	out, err := yaml.Marshal(doc)
	if err != nil {
		return nil, false
	}
	return out, true
}

func normalizeProfileBytes(buf []byte) []byte {
	return normalizeProfileBytesDepth(buf, 0)
}

func normalizeProfileBytesDepth(buf []byte, depth int) []byte {
	if depth > 2 {
		return buf
	}
	trimmed := bytes.TrimSpace(bytes.TrimPrefix(buf, []byte{0xEF, 0xBB, 0xBF}))
	if len(trimmed) == 0 {
		return buf
	}
	if trimmed[0] == '{' || trimmed[0] == '[' {
		if proxies, ok := parseXrayJSONOutbounds(trimmed); ok {
			if out, ok := buildClashConfigFromProxies(proxies); ok {
				return out
			}
		}
		return buf
	}
	if bytes.Contains(trimmed, []byte("[Interface]")) && bytes.Contains(trimmed, []byte("[Peer]")) {
		if proxies, ok := parseWireGuardConf(trimmed); ok {
			if out, ok := buildClashConfigFromProxies(proxies); ok {
				return out
			}
		}
	}
	if looksLikeShareLinkList(trimmed) {
		if proxies := decodeShareLinkDocument(trimmed); len(proxies) > 0 {
			if out, ok := buildClashConfigFromProxies(proxies); ok {
				return out
			}
		}
	}
	if !bytes.ContainsAny(trimmed, ":") && len(trimmed) >= 8 {
		if decoded, ok := decodeCompatBase64(string(trimmed)); ok && len(bytes.TrimSpace(decoded)) > 0 {
			return normalizeProfileBytesDepth(decoded, depth+1)
		}
	}
	return buf
}

func looksLikeShareLinkList(buf []byte) bool {
	for _, raw := range bytes.Split(buf, []byte("\n")) {
		line := strings.TrimSpace(string(raw))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		scheme, _, ok := strings.Cut(line, "://")
		return ok && !strings.ContainsAny(scheme, " \t:")
	}
	return false
}

func decodeShareLinkDocument(buf []byte) []map[string]any {
	var proxies []map[string]any
	for _, raw := range bytes.Split(buf, []byte("\n")) {
		line := strings.TrimSpace(string(raw))
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") {
			continue
		}
		proxies = append(proxies, decodeShareLineAny(line)...)
	}
	return proxies
}
