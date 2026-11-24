package core

import (
	"encoding/base64"
	"net/url"
	"strings"
	"testing"
)

func TestHandleDecodeShareLinksCompatFormats(t *testing.T) {
	priv := "yAnz5TF+lXXJte14tji3zlMNq+hd2rYUIgJBgB3fBmk="
	pub := "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg="
	psk := "oY5N2mN8Z2T4lQ9u2H3u5z1W8aX0dF7v9kP6nM1bR8E="
	wgLink := "wireguard://" + url.QueryEscape(priv) + "@162.159.192.1:2408?publickey=" +
		url.QueryEscape(pub) + "&presharedkey=" + url.QueryEscape(psk) +
		"&address=172.16.0.2/32,2606:4700:d0::a29f:c001/128&mtu=1280&reserved=12,34,56#WarpWG"
	wgShort := "wg://10.0.0.1:51820?privatekey=" + priv + "&publickey=" + pub +
		"&reserved=" + base64.StdEncoding.EncodeToString([]byte{7, 8, 9}) + "#RawWG"
	v2raynPayload := base64.StdEncoding.EncodeToString([]byte("socks4://alice:pass@127.0.0.1:1080#S4"))
	v2raynLink := "v2rayn://" + v2raynPayload

	results := handleDecodeShareLinks(LinesParams{
		Lines: []string{wgLink, wgShort, "socks4a://10.2.3.4:1081#S4A", v2raynLink},
	})
	if len(results) != 4 {
		t.Fatalf("len(results) = %d, want 4", len(results))
	}
	wg := results[0][0]
	if wg["type"] != "wireguard" || wg["server"] != "162.159.192.1" || wg["port"] != 2408 {
		t.Fatalf("unexpected wg decoded: %#v", wg)
	}
	if wg["private-key"] != priv || wg["public-key"] != pub || wg["pre-shared-key"] != psk {
		t.Fatalf("unexpected wg keys: %#v", wg)
	}
	if wg["ip"] != "172.16.0.2/32" || wg["ipv6"] != "2606:4700:d0::a29f:c001/128" || wg["mtu"] != 1280 {
		t.Fatalf("unexpected wg address/mtu: %#v", wg)
	}
	wg2 := results[1][0]
	if wg2["private-key"] != priv || wg2["public-key"] != pub || wg2["name"] != "RawWG" {
		t.Fatalf("unexpected wgShort decoded: %#v", wg2)
	}
	s4a := results[2][0]
	if s4a["type"] != "socks5" || s4a["server"] != "10.2.3.4" || s4a["port"] != 1081 {
		t.Fatalf("unexpected socks4a decoded: %#v", s4a)
	}
	wrapped := results[3][0]
	if wrapped["type"] != "socks5" || wrapped["username"] != "alice" || wrapped["name"] != "S4" {
		t.Fatalf("unexpected v2rayn wrapped decoded: %#v", wrapped)
	}
}

func TestParseWireGuardConf(t *testing.T) {
	conf := []byte(`
[Interface]
PrivateKey = privkey123=
Address = 10.7.0.2/32, fd00::2/128
MTU = 1380

[Peer]
PublicKey = pubkey456=
PresharedKey = psk789=
Endpoint = 198.51.100.10:51820
PersistentKeepalive = 25
`)
	proxies, ok := parseWireGuardConf(conf)
	if !ok || len(proxies) != 1 {
		t.Fatalf("parseWireGuardConf = (%v, %v), want 1 proxy", proxies, ok)
	}
	p := proxies[0]
	if p["type"] != "wireguard" || p["server"] != "198.51.100.10" || p["port"] != 51820 {
		t.Fatalf("unexpected peer endpoint: %#v", p)
	}
	if p["ip"] != "10.7.0.2/32" || p["ipv6"] != "fd00::2/128" || p["mtu"] != 1380 {
		t.Fatalf("unexpected interface fields: %#v", p)
	}
}

func TestParseXrayJSONOutbounds(t *testing.T) {
	xray := []byte(`{
		"outbounds": [
			{"protocol": "freedom", "tag": "direct"},
			{
				"tag": "vless-reality",
				"protocol": "vless",
				"settings": {"vnext": [{"address": "1.2.3.4", "port": 443, "users": [{"id": "11111111-1111-1111-1111-111111111111", "flow": "xtls-rprx-vision"}]}]},
				"streamSettings": {
					"network": "tcp",
					"security": "reality",
					"realitySettings": {"serverName": "example.com", "publicKey": "pubk", "shortId": "abcd"}
				}
			},
			{
				"tag": "vmess-ws",
				"protocol": "vmess",
				"settings": {"vnext": [{"address": "2.3.4.5", "port": 80, "users": [{"id": "22222222-2222-2222-2222-222222222222", "alterId": 0}]}]},
				"streamSettings": {"network": "ws", "wsSettings": {"path": "/ws", "headers": {"Host": "ws.example.com"}}}
			},
			{
				"tag": "trojan-grpc",
				"protocol": "trojan",
				"settings": {"servers": [{"address": "3.4.5.6", "port": 443, "password": "secret"}]},
				"streamSettings": {"network": "grpc", "security": "tls", "tlsSettings": {"serverName": "tj.example.com"}, "grpcSettings": {"serviceName": "grpc-svc"}}
			},
			{
				"tag": "ss-node",
				"protocol": "shadowsocks",
				"settings": {"servers": [{"address": "4.5.6.7", "port": 8388, "method": "aes-256-gcm", "password": "pw"}]}
			}
		]
	}`)
	proxies, ok := parseXrayJSONOutbounds(xray)
	if !ok || len(proxies) != 4 {
		t.Fatalf("parseXrayJSONOutbounds len = %d (%v), want 4", len(proxies), ok)
	}
	if proxies[0]["type"] != "vless" || proxies[1]["network"] != "ws" || proxies[2]["sni"] != "tj.example.com" || proxies[3]["type"] != "ss" {
		t.Fatalf("unexpected converted outbounds: %#v", proxies)
	}
	clashJSON := []byte(`{"proxies":[{"name":"p","type":"direct"}]}`)
	if _, ok := parseXrayJSONOutbounds(clashJSON); ok {
		t.Fatal("parseXrayJSONOutbounds should skip JSON Clash configs")
	}
}

func TestNormalizeProfileBytes(t *testing.T) {
	rawLinks := "vless://11111111-1111-1111-1111-111111111111@example.com:443?security=tls#V1\n" +
		"wg://yAnz5TF%2BlXXJte14tji3zlMNq%2Bhd2rYUIgJBgB3fBmk%3D@1.1.1.1:51820?publickey=xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg%3D#W1"
	b64Sub := []byte(base64.StdEncoding.EncodeToString([]byte(rawLinks)))
	normalized := normalizeProfileBytes(b64Sub)
	raw, err := unmarshalRawConfig(normalized)
	if err != nil {
		t.Fatalf("unmarshalRawConfig failed on normalized base64 sub: %v\n%s", err, string(normalized))
	}
	if len(raw.Proxy) != 2 {
		t.Fatalf("len(raw.Proxy) = %d, want 2", len(raw.Proxy))
	}

	clashYAML := "proxies:\n  - name: n1\n    type: vless\n    server: example.com\n    port: 443\n    uuid: 11111111-1111-1111-1111-111111111111\n    reality-opts:\n      short-id: 01234567\n"
	if got := string(normalizeProfileBytes([]byte(clashYAML))); got != clashYAML {
		t.Fatalf("standard Clash YAML modified: %s", got)
	}
	if !strings.Contains(string(normalized), "proxy-groups") {
		t.Fatalf("expected generated Clash config with proxy-groups: %s", string(normalized))
	}
}

func TestIsQuicRejectRuleAndStrip(t *testing.T) {
	if !isQuicRejectRule("AND,((NETWORK,UDP),(DST-PORT,443)),REJECT") {
		t.Fatal("expected UDP/443 REJECT rule to match")
	}
	if !isQuicRejectRule("AND,((NETWORK,udp),(DST-PORT,443)),REJECT-DROP,no-resolve") {
		t.Fatal("expected lowercase udp/443 REJECT-DROP rule to match")
	}
	if isQuicRejectRule("GEOSITE,category-ads,REJECT") {
		t.Fatal("adblock rule must not match QUIC filter")
	}
	if isQuicRejectRule("AND,((NETWORK,TCP),(DST-PORT,443)),REJECT") {
		t.Fatal("TCP/443 rule must not match QUIC filter")
	}
}

func TestDecodeShareLinksMobileCompat(t *testing.T) {
	vmessJSON := `{"v":"2","ps":"vmess-ws","add":"104.16.1.1","port":"443","id":"11111111-1111-1111-1111-111111111111","aid":"0","net":"ws","type":"none","host":"cdn.example.net","path":"/vm","tls":"tls","allowInsecure":1}`
	vmessLink := "vmess://" + base64.StdEncoding.EncodeToString([]byte(vmessJSON))

	lines := []string{
		"vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?security=tls&type=ws&host=ws.example.com&allowInsecure=1#Mobile-WS",
		"vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?security=tls&sni=sni.example.com&type=ws&host=worker.example.dev#ExplicitSNI",
		"trojan://secretpass@5.6.7.8:443?type=ws&host=ws-host.example.com&path=/ws&allowInsecure=true#TrojanWS",
		"vless://11111111-1111-1111-1111-111111111111@1.2.3.4:80?security=none&type=tcp&headerType=http&host=a.example.org,b.example.org&path=/v1#HttpObfs",
		"vless://11111111-1111-1111-1111-111111111111@1.2.3.4:443?type=splithttp&security=tls&sni=split.example&path=/xh#Split",
		vmessLink,
	}
	results := handleDecodeShareLinks(LinesParams{Lines: lines})
	if len(results) != len(lines) {
		t.Fatalf("len(results) = %d, want %d", len(results), len(lines))
	}

	p0 := results[0][0]
	if p0["skip-cert-verify"] != true || p0["servername"] != "ws.example.com" {
		t.Fatalf("vless ws host fallback failed: %#v", p0)
	}
	p1 := results[1][0]
	if p1["servername"] != "sni.example.com" {
		t.Fatalf("explicit sni overwritten: %#v", p1)
	}
	p2 := results[2][0]
	if p2["sni"] != "ws-host.example.com" || p2["skip-cert-verify"] != true || p2["network"] != "ws" {
		t.Fatalf("trojan ws compat failed: %#v", p2)
	}
	wsHeaders, _ := p2["ws-opts"].(map[string]any)["headers"].(map[string]string)
	if wsHeaders["Host"] != "ws-host.example.com" {
		t.Fatalf("trojan ws host missing: %#v", p2["ws-opts"])
	}
	p3 := results[3][0]
	if p3["network"] != "http" {
		t.Fatalf("tcp http headerType failed: %#v", p3)
	}
	httpHosts, _ := p3["http-opts"].(map[string]any)["headers"].(map[string]any)["Host"].([]string)
	if len(httpHosts) != 2 || httpHosts[0] != "a.example.org" || httpHosts[1] != "b.example.org" {
		t.Fatalf("comma-separated HTTP Host not split: %#v", p3["http-opts"])
	}
	p4 := results[4][0]
	if p4["network"] != "xhttp" || p4["servername"] != "split.example" {
		t.Fatalf("splithttp -> xhttp mapping failed: %#v", p4)
	}
	p5 := results[5][0]
	if p5["skip-cert-verify"] != true || p5["servername"] != "cdn.example.net" {
		t.Fatalf("vmess JSON compat failed: %#v", p5)
	}

	subBlob := base64.StdEncoding.EncodeToString([]byte(strings.Join(lines, "\n")))
	converted, err := convertV2RayBytes([]byte(subBlob))
	if err != nil || len(converted) != len(lines) {
		t.Fatalf("convertV2RayBytes = (%d, %v), want %d", len(converted), err, len(lines))
	}

	builtYAML, ok := buildClashConfigFromProxies(converted)
	if !ok || !strings.Contains(string(builtYAML), "Fallback") || !strings.Contains(string(builtYAML), "200-299") {
		t.Fatalf("buildClashConfigFromProxies missing Fallback/expected-status: %s", string(builtYAML))
	}
}
