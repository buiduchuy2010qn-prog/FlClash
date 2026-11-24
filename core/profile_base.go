package core

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"

	"github.com/metacubex/mihomo/component/age"
	"github.com/metacubex/mihomo/config"
	"go.yaml.in/yaml/v3"
)

// What makes a profile large stays in the Core; the overlay the host sends
// back replaces every other section.
var profileBaseSections = []string{"proxies", "proxy-groups", "sub-rules"}

func handleGetProfileBase(params PathParams) (*ProfileBase, error) {
	defer scheduleLoadMemoryRelease()
	buf, err := os.ReadFile(params.Path)
	if err != nil {
		return nil, err
	}
	digest := sha256.Sum256(buf)
	raw, err := unmarshalRawConfig(buf)
	if err != nil {
		return nil, err
	}
	base := &ProfileBase{
		Digest:      hex.EncodeToString(digest[:]),
		MatchRules:  []string{},
		Proxies:     len(raw.Proxy),
		ProxyGroups: len(raw.ProxyGroup),
		Rules:       len(raw.Rule),
	}
	for _, rule := range raw.Rule {
		if isMatchRule(rule) {
			base.MatchRules = append(base.MatchRules, rule)
		}
	}
	raw.Proxy, raw.ProxyGroup, raw.Rule, raw.SubRules = nil, nil, nil, nil
	base.Config = raw
	return base, nil
}

func handleGetProfileOutbounds(params PathParams) (*ProfileOutbounds, error) {
	defer scheduleLoadMemoryRelease()
	buf, err := os.ReadFile(params.Path)
	if err != nil {
		return nil, err
	}
	raw, err := unmarshalRawConfig(buf)
	if err != nil {
		return nil, err
	}
	return &ProfileOutbounds{Proxies: outboundsOf(raw.Proxy), ProxyGroups: outboundsOf(raw.ProxyGroup)}, nil
}

func outboundsOf(mappings []map[string]any) []ProfileOutbound {
	outbounds := make([]ProfileOutbound, 0, len(mappings))
	for _, mapping := range mappings {
		name, _ := mapping["name"].(string)
		kind, _ := mapping["type"].(string)
		outbounds = append(outbounds, ProfileOutbound{Name: name, Type: kind})
	}
	return outbounds
}

// The merged config goes to the spill directory, so the host reads it as text
// and never decodes it.
func handleBuildProfile(base *SetupBase) (string, error) {
	defer scheduleLoadMemoryRelease()
	document, err := mergeProfileBase(base)
	if err != nil {
		return "", err
	}
	dir, err := makeSpilledResponseDir()
	if err != nil {
		return "", err
	}
	path, err := writeDocumentFile(dir, "*.yaml", document)
	if err != nil {
		return "", err
	}
	scheduleReclaimOwnership()
	return path, nil
}

// Mirrors Rule.parse in Dart, which reads the type from the first field.
func isMatchRule(rule string) bool {
	kind, _, _ := strings.Cut(rule, ",")
	return strings.EqualFold(strings.TrimSpace(kind), "MATCH")
}

var isAndroidRuntime = runtime.GOOS == "android"

func boolNode(value bool) *yaml.Node {
	v := "false"
	if value {
		v = "true"
	}
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!bool", Value: v}
}

func strNode(value string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value}
}

func isExplicitBool(node *yaml.Node, want bool) bool {
	resolved := resolveAlias(node)
	if resolved == nil || resolved.Kind != yaml.ScalarNode {
		return false
	}
	target := "false"
	if want {
		target = "true"
	}
	return strings.EqualFold(strings.TrimSpace(resolved.Value), target)
}

func optimizeProxyNodes(root *yaml.Node) {
	proxiesNode := resolveAlias(mappingValue(root, "proxies"))
	if proxiesNode == nil || proxiesNode.Kind != yaml.SequenceNode {
		return
	}
	for _, node := range proxiesNode.Content {
		item := resolveAlias(node)
		if item == nil || item.Kind != yaml.MappingNode {
			continue
		}
		typeNode := resolveAlias(mappingValue(item, "type"))
		if typeNode == nil || typeNode.Kind != yaml.ScalarNode {
			continue
		}
		switch strings.ToLower(strings.TrimSpace(typeNode.Value)) {
		case "vless", "vmess", "trojan":
			if mappingValue(item, "udp") == nil {
				setMappingValue(item, "udp", boolNode(true))
			}
			if isExplicitBool(mappingValue(item, "tls"), true) {
				fpNode := resolveAlias(mappingValue(item, "client-fingerprint"))
				if fpNode == nil || fpNode.Kind != yaml.ScalarNode || strings.TrimSpace(fpNode.Value) == "" {
					setMappingValue(item, "client-fingerprint", strNode("chrome"))
				}
			}
		}
	}
}

func ensureSystemDNSNode(dnsNode *yaml.Node, key string) {
	existing := resolveAlias(mappingValue(dnsNode, key))
	if existing == nil || isNull(existing) || existing.Kind != yaml.SequenceNode {
		setMappingValue(dnsNode, key, &yaml.Node{
			Kind:    yaml.SequenceNode,
			Tag:     "!!seq",
			Content: []*yaml.Node{strNode("system")},
		})
		return
	}
	for _, item := range existing.Content {
		resolved := resolveAlias(item)
		if resolved == nil || resolved.Kind != yaml.ScalarNode {
			continue
		}
		val := strings.TrimSpace(resolved.Value)
		if val == "system" || val == "system://" {
			return
		}
	}
	content := make([]*yaml.Node, 0, len(existing.Content)+1)
	content = append(content, strNode("system"))
	content = append(content, existing.Content...)
	setMappingValue(dnsNode, key, &yaml.Node{
		Kind:    yaml.SequenceNode,
		Tag:     "!!seq",
		Content: content,
	})
}

func walkParenthesizedRules(expr string, visit func(string) bool) bool {
	depth := 0
	start := -1
	for i := 0; i < len(expr); i++ {
		switch expr[i] {
		case '(':
			if depth == 0 {
				start = i + 1
			}
			depth++
		case ')':
			if depth == 0 {
				continue
			}
			depth--
			if depth == 0 && start >= 0 {
				inner := strings.TrimSpace(expr[start:i])
				start = -1
				if strings.HasPrefix(inner, "(") {
					if walkParenthesizedRules(inner, visit) {
						return true
					}
				} else if inner != "" && visit(inner) {
					return true
				}
			}
		}
	}
	return false
}

func visitRuleParts(rule string, fn func(kind, payload string) bool) bool {
	kind, rest, found := strings.Cut(strings.TrimSpace(rule), ",")
	if !found && kind == "" {
		return false
	}
	kind = strings.ToUpper(strings.TrimSpace(kind))
	switch kind {
	case "AND", "OR", "NOT", "SUB-RULE":
		return walkParenthesizedRules(rest, func(sub string) bool {
			return visitRuleParts(sub, fn)
		})
	default:
		payload, _, _ := strings.Cut(rest, ",")
		return fn(kind, strings.TrimSpace(payload))
	}
}

func ruleUsesProcess(rule string) bool {
	return visitRuleParts(rule, func(kind, _ string) bool {
		return kind == "UID" || strings.HasPrefix(kind, "PROCESS-")
	})
}

func seqHasProcessRule(seq *yaml.Node) bool {
	if seq == nil || seq.Kind != yaml.SequenceNode {
		return false
	}
	for _, item := range seq.Content {
		resolved := resolveAlias(item)
		if resolved != nil && resolved.Kind == yaml.ScalarNode && ruleUsesProcess(resolved.Value) {
			return true
		}
	}
	return false
}

func documentHasProcessRule(root *yaml.Node) bool {
	if seqHasProcessRule(resolveAlias(mappingValue(root, "rules"))) {
		return true
	}
	subRules := resolveAlias(mappingValue(root, "sub-rules"))
	if subRules != nil && subRules.Kind == yaml.MappingNode {
		for i := 0; i+1 < len(subRules.Content); i += 2 {
			if seqHasProcessRule(resolveAlias(subRules.Content[i+1])) {
				return true
			}
		}
	}
	return false
}

var androidDoTHosts = []struct {
	host string
	ips  []string
}{
	{"1dot1dot1dot1.cloudflare-dns.com", []string{"1.1.1.1", "1.0.0.1"}},
	{"one.one.one.one", []string{"1.1.1.1", "1.0.0.1"}},
	{"dns.cloudflare.com", []string{"1.1.1.1", "1.0.0.1"}},
	{"dns.google", []string{"8.8.8.8", "8.8.4.4"}},
	{"dns.google.com", []string{"8.8.8.8", "8.8.4.4"}},
	{"dns.quad9.net", []string{"9.9.9.9", "149.112.112.112"}},
	{"dns.adguard-dns.com", []string{"94.140.14.14", "94.140.15.15"}},
	{"dns.adguard.com", []string{"94.140.14.14", "94.140.15.15"}},
	{"dns.alidns.com", []string{"223.5.5.5", "223.6.6.6"}},
	{"common.dot.dns.yandex.net", []string{"77.88.8.8", "77.88.8.1"}},
}

var androidFakeIPBypass = []string{
	"+.lan",
	"+.local",
	"1dot1dot1dot1.cloudflare-dns.com",
	"one.one.one.one",
	"dns.cloudflare.com",
	"dns.google",
	"dns.google.com",
	"dns.quad9.net",
	"dns.adguard-dns.com",
	"dns.adguard.com",
	"dns.alidns.com",
	"common.dot.dns.yandex.net",
	"dns.nextdns.io",
	"*.dns.nextdns.io",
	"connectivitycheck.gstatic.com",
	"www.gstatic.com",
	"captive.apple.com",
	"connectivitycheck.platform.hicloud.com",
	"*.ntp.org",
	"time.*.com",
}

func optimizeConfigDocument(document, profile *yaml.Node) {
	root, err := documentMapping(document)
	if err != nil {
		return
	}
	defaultsSource := profile
	if defaultsSource == nil {
		defaultsSource = root
	}
	if mappingValue(defaultsSource, "unified-delay") == nil {
		setMappingValue(root, "unified-delay", boolNode(true))
	}
	if mappingValue(defaultsSource, "tcp-concurrent") == nil {
		setMappingValue(root, "tcp-concurrent", boolNode(true))
	}
	optimizeProxyNodes(root)
	optimizeProxyGroups(root)
	if !isAndroidRuntime {
		return
	}
	ensureAndroidHosts(root)
	ensureAndroidProfilePersistence(root)
	ensureAndroidSniffer(root)
	if dnsNode := resolveAlias(mappingValue(root, "dns")); dnsNode != nil && dnsNode.Kind == yaml.MappingNode {
		ensureAndroidDNSDefaults(dnsNode)
	}
	if !documentHasProcessRule(root) {
		setMappingValue(root, "find-process-mode", strNode("off"))
	}
}

func ensureChildMapping(parent *yaml.Node, key string) *yaml.Node {
	existing := resolveAlias(mappingValue(parent, key))
	if existing != nil && !isNull(existing) {
		if existing.Kind == yaml.MappingNode {
			return existing
		}
		return nil
	}
	node := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}
	setMappingValue(parent, key, node)
	return node
}

func ensureSequenceStrings(parent *yaml.Node, key string, additions ...string) {
	existing := resolveAlias(mappingValue(parent, key))
	if existing == nil || isNull(existing) {
		existing = &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
		setMappingValue(parent, key, existing)
	}
	if existing.Kind != yaml.SequenceNode {
		return
	}
	seen := make(map[string]struct{}, len(existing.Content))
	for _, item := range existing.Content {
		if resolved := resolveAlias(item); resolved != nil && resolved.Kind == yaml.ScalarNode {
			seen[resolved.Value] = struct{}{}
		}
	}
	for _, entry := range additions {
		if _, exists := seen[entry]; exists {
			continue
		}
		existing.Content = append(existing.Content, strNode(entry))
		seen[entry] = struct{}{}
	}
}

func ensureAndroidHosts(root *yaml.Node) {
	hostsNode := ensureChildMapping(root, "hosts")
	if hostsNode == nil {
		return
	}
	for _, entry := range androidDoTHosts {
		if existing := resolveAlias(mappingValue(hostsNode, entry.host)); existing == nil || isNull(existing) {
			ensureSequenceStrings(hostsNode, entry.host, entry.ips...)
		}
	}
}

func ensureAndroidProfilePersistence(root *yaml.Node) {
	profileNode := ensureChildMapping(root, "profile")
	if profileNode == nil {
		return
	}
	if node := resolveAlias(mappingValue(profileNode, "store-fake-ip")); node == nil || isNull(node) {
		setMappingValue(profileNode, "store-fake-ip", boolNode(true))
	}
}

func mappingKeyIgnoreCase(mapping *yaml.Node, want string) string {
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		if strings.EqualFold(mapping.Content[i].Value, want) {
			return mapping.Content[i].Value
		}
	}
	return want
}

func ensureAndroidSniffer(root *yaml.Node) {
	snifferNode := ensureChildMapping(root, "sniffer")
	if snifferNode == nil {
		return
	}
	if isExplicitBool(mappingValue(snifferNode, "enable"), false) {
		return
	}
	setMappingValue(snifferNode, "enable", boolNode(true))
	if node := resolveAlias(mappingValue(snifferNode, "force-dns-mapping")); node == nil || isNull(node) {
		setMappingValue(snifferNode, "force-dns-mapping", boolNode(true))
	}
	if node := resolveAlias(mappingValue(snifferNode, "parse-pure-ip")); node == nil || isNull(node) {
		setMappingValue(snifferNode, "parse-pure-ip", boolNode(true))
	}
	sniffMap := ensureChildMapping(snifferNode, "sniff")
	if sniffMap == nil {
		return
	}
	if httpNode := ensureChildMapping(sniffMap, mappingKeyIgnoreCase(sniffMap, "HTTP")); httpNode != nil {
		if existing := resolveAlias(mappingValue(httpNode, "ports")); existing == nil || isNull(existing) {
			ensureSequenceStrings(httpNode, "ports", "80", "8080-8880")
		}
		if od := resolveAlias(mappingValue(httpNode, "override-destination")); od == nil || isNull(od) {
			setMappingValue(httpNode, "override-destination", boolNode(true))
		}
	}
	if tlsNode := ensureChildMapping(sniffMap, mappingKeyIgnoreCase(sniffMap, "TLS")); tlsNode != nil {
		if existing := resolveAlias(mappingValue(tlsNode, "ports")); existing == nil || isNull(existing) {
			ensureSequenceStrings(tlsNode, "ports", "443", "853", "8443")
		} else {
			ensureSequenceStrings(tlsNode, "ports", "853")
		}
	}
	if quicNode := ensureChildMapping(sniffMap, mappingKeyIgnoreCase(sniffMap, "QUIC")); quicNode != nil {
		if existing := resolveAlias(mappingValue(quicNode, "ports")); existing == nil || isNull(existing) {
			ensureSequenceStrings(quicNode, "ports", "443", "8443")
		}
	}
}

func ensureAndroidDNSDefaults(dnsNode *yaml.Node) {
	if isExplicitBool(mappingValue(dnsNode, "enable"), false) {
		return
	}
	ensureSystemDNSNode(dnsNode, "default-nameserver")
	ensureSystemDNSNode(dnsNode, "proxy-server-nameserver")
	ensureSystemDNSNode(dnsNode, "direct-nameserver")
	ensureSequenceStrings(dnsNode, "nameserver", "1.1.1.1", "8.8.8.8")
	if nsSeq := resolveAlias(mappingValue(dnsNode, "nameserver")); nsSeq != nil && nsSeq.Kind == yaml.SequenceNode {
		var nonSystem []*yaml.Node
		for _, item := range nsSeq.Content {
			if resolved := resolveAlias(item); resolved != nil && resolved.Kind == yaml.ScalarNode {
				val := strings.TrimSpace(resolved.Value)
				if val == "system" || val == "system://" {
					continue
				}
			}
			nonSystem = append(nonSystem, item)
		}
		if len(nonSystem) > 0 {
			nsSeq.Content = nonSystem
		}
	}
	if node := resolveAlias(mappingValue(dnsNode, "respect-rules")); node == nil || isNull(node) {
		setMappingValue(dnsNode, "respect-rules", boolNode(true))
	}
	if node := resolveAlias(mappingValue(dnsNode, "use-hosts")); node == nil || isNull(node) {
		setMappingValue(dnsNode, "use-hosts", boolNode(true))
	}
	modeNode := resolveAlias(mappingValue(dnsNode, "fake-ip-filter-mode"))
	if modeNode == nil || !strings.EqualFold(modeNode.Value, "whitelist") {
		ensureSequenceStrings(dnsNode, "fake-ip-filter", androidFakeIPBypass...)
	}
}

func intNode(v int) *yaml.Node {
	return &yaml.Node{
		Kind:  yaml.ScalarNode,
		Tag:   "!!int",
		Value: strconv.Itoa(v),
	}
}

func scalarString(mapping *yaml.Node, key string) string {
	node := resolveAlias(mappingValue(mapping, key))
	if node == nil || node.Kind != yaml.ScalarNode {
		return ""
	}
	return strings.TrimSpace(node.Value)
}

func scalarInt(mapping *yaml.Node, key string) (int, bool) {
	raw := scalarString(mapping, key)
	if raw == "" {
		return 0, false
	}
	val, err := strconv.Atoi(raw)
	if err != nil {
		return 0, false
	}
	return val, true
}

func optimizeProxyGroups(root *yaml.Node) {
	groupsNode := resolveAlias(mappingValue(root, "proxy-groups"))
	if groupsNode == nil || groupsNode.Kind != yaml.SequenceNode {
		return
	}

	var leafProxyNames []string
	if proxiesNode := resolveAlias(mappingValue(root, "proxies")); proxiesNode != nil && proxiesNode.Kind == yaml.SequenceNode {
		for _, item := range proxiesNode.Content {
			if m := resolveAlias(item); m != nil && m.Kind == yaml.MappingNode {
				if name := scalarString(m, "name"); name != "" {
					leafProxyNames = append(leafProxyNames, name)
				}
			}
		}
	}

	groupNames := make(map[string]bool, len(groupsNode.Content))
	fallbackGroups := make(map[string]bool)
	hasURLTest := false

	for _, item := range groupsNode.Content {
		group := resolveAlias(item)
		if group == nil || group.Kind != yaml.MappingNode {
			continue
		}
		name := scalarString(group, "name")
		if name != "" {
			groupNames[name] = true
		}
		groupType := strings.ToLower(scalarString(group, "type"))
		switch groupType {
		case "url-test":
			hasURLTest = true
		case "fallback":
			if name != "" {
				fallbackGroups[name] = true
			}
		}
		if groupType == "fallback" || groupType == "url-test" || groupType == "load-balance" {
			if interval, ok := scalarInt(group, "interval"); !ok || interval <= 0 || interval > 300 {
				setMappingValue(group, "interval", intNode(180))
			}
			if lazyNode := resolveAlias(mappingValue(group, "lazy")); lazyNode == nil || isNull(lazyNode) {
				setMappingValue(group, "lazy", boolNode(true))
			}
			if timeoutVal, ok := scalarInt(group, "timeout"); !ok || timeoutVal <= 0 || timeoutVal > 10000 {
				setMappingValue(group, "timeout", intNode(5000))
			}
			if scalarString(group, "expected-status") == "" {
				setMappingValue(group, "expected-status", strNode("200-299"))
			}
			if maxFailed, ok := scalarInt(group, "max-failed-times"); !ok || maxFailed <= 0 {
				setMappingValue(group, "max-failed-times", intNode(2))
			}
			rawURL := strings.ToLower(scalarString(group, "url"))
			if rawURL == "" || strings.HasPrefix(rawURL, "http://cp.cloudflare.com") {
				setMappingValue(group, "url", strNode("https://www.gstatic.com/generate_204"))
			}
			if groupType == "url-test" {
				if tol := resolveAlias(mappingValue(group, "tolerance")); tol == nil || isNull(tol) {
					setMappingValue(group, "tolerance", intNode(100))
				}
			}
		}
	}

	if len(leafProxyNames) >= 2 && !hasURLTest && len(fallbackGroups) > 0 && !groupNames["Auto"] {
		proxiesSeq := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
		for _, proxyName := range leafProxyNames {
			proxiesSeq.Content = append(proxiesSeq.Content, strNode(proxyName))
		}
		autoGroup := &yaml.Node{
			Kind: yaml.MappingNode,
			Tag:  "!!map",
			Content: []*yaml.Node{
				strNode("name"), strNode("Auto"),
				strNode("type"), strNode("url-test"),
				strNode("url"), strNode("https://www.gstatic.com/generate_204"),
				strNode("interval"), intNode(180),
				strNode("timeout"), intNode(5000),
				strNode("lazy"), boolNode(true),
				strNode("tolerance"), intNode(100),
				strNode("expected-status"), strNode("200-299"),
				strNode("max-failed-times"), intNode(2),
				strNode("proxies"), proxiesSeq,
			},
		}
		groupsNode.Content = append(groupsNode.Content, autoGroup)

		for _, item := range groupsNode.Content {
			group := resolveAlias(item)
			if group == nil || group.Kind != yaml.MappingNode {
				continue
			}
			if strings.ToLower(scalarString(group, "type")) != "select" {
				continue
			}
			seq := resolveAlias(mappingValue(group, "proxies"))
			if seq == nil || seq.Kind != yaml.SequenceNode || len(seq.Content) == 0 {
				continue
			}
			first := resolveAlias(seq.Content[0])
			if first == nil || first.Kind != yaml.ScalarNode || !fallbackGroups[strings.TrimSpace(first.Value)] {
				continue
			}
			hasAutoAlready := false
			for _, entry := range seq.Content {
				if r := resolveAlias(entry); r != nil && r.Kind == yaml.ScalarNode && strings.TrimSpace(r.Value) == "Auto" {
					hasAutoAlready = true
					break
				}
			}
			if !hasAutoAlready {
				seq.Content = append([]*yaml.Node{strNode("Auto")}, seq.Content...)
			}
		}
	}
}

func loadConfigWithBase(base *SetupBase, configPath string) (*config.Config, error) {
	document, profile, err := mergeProfileDocuments(base)
	if err != nil {
		return nil, err
	}
	optimizeConfigDocument(document, profile)
	raw := config.DefaultRawConfig()
	if err := document.Decode(raw); err != nil {
		return nil, err
	}
	if err := writeConfigDocument(configPath, document); err != nil {
		return nil, err
	}
	prepareRawConfigForParse(raw)
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return nil, err
	}
	return withPlatformLimits(cfg), nil
}

func mergeProfileBase(base *SetupBase) (*yaml.Node, error) {
	document, _, err := mergeProfileDocuments(base)
	return document, err
}

func mergeProfileDocuments(base *SetupBase) (*yaml.Node, *yaml.Node, error) {
	buf, err := os.ReadFile(base.Path)
	if err != nil {
		return nil, nil, err
	}
	if buf, err = age.DecryptBytes(buf); err != nil {
		return nil, nil, fmt.Errorf("decrypt config error: %w", err)
	}
	buf = normalizeProfileBytes(buf)
	retag := bytes.Contains(buf, []byte("short-id"))
	var profileDocument, overlayDocument yaml.Node
	if err := yaml.Unmarshal(buf, &profileDocument); err != nil {
		return nil, nil, err
	}
	if err := yaml.Unmarshal([]byte(base.Overlay), &overlayDocument); err != nil {
		return nil, nil, err
	}
	profile, err := documentMapping(&profileDocument)
	if err != nil {
		return nil, nil, err
	}
	root, err := documentMapping(&overlayDocument)
	if err != nil {
		return nil, nil, err
	}
	allowQuic := isExplicitBool(mappingValue(root, "allow-quic"), true)
	deleteMappingKey(root, "allow-quic")
	for _, key := range profileBaseSections {
		if value := mappingValue(profile, key); value != nil {
			setMappingValue(root, key, value)
		}
	}
	rules, err := appendRules(mappingValue(root, "rules"), mappingValue(profile, "rules"))
	if err != nil {
		return nil, nil, err
	}
	if rules != nil {
		if allowQuic {
			stripQuicRejectRules(rules)
		}
		setMappingValue(root, "rules", rules)
	}
	if retag {
		retagShortIDs(root)
	}
	return &yaml.Node{Kind: yaml.DocumentNode, Content: []*yaml.Node{root}}, profile, nil
}

func documentMapping(document *yaml.Node) (*yaml.Node, error) {
	node := document
	if node.Kind == yaml.DocumentNode && len(node.Content) > 0 {
		node = resolveAlias(node.Content[0])
	}
	switch {
	case node.Kind == yaml.MappingNode:
		return node, nil
	case node.Kind == 0, node.Kind == yaml.DocumentNode, isNull(node):
		return &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map"}, nil
	}
	return nil, fmt.Errorf("line %d: a config must be a mapping", node.Line)
}

// A key the mapping lacks is looked up in its merge keys, as the decoder does.
func mappingValue(mapping *yaml.Node, key string) *yaml.Node {
	var sources []*yaml.Node
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		name, value := mapping.Content[i], mapping.Content[i+1]
		if name.Kind != yaml.ScalarNode {
			continue
		}
		if name.ShortTag() == "!!merge" {
			sources = append(sources, value)
		} else if name.Value == key {
			return value
		}
	}
	for _, source := range sources {
		source = resolveAlias(source)
		candidates := []*yaml.Node{source}
		if source.Kind == yaml.SequenceNode {
			candidates = source.Content
		}
		for _, candidate := range candidates {
			if candidate = resolveAlias(candidate); candidate.Kind == yaml.MappingNode {
				if value := mappingValue(candidate, key); value != nil {
					return value
				}
			}
		}
	}
	return nil
}

func setMappingValue(mapping *yaml.Node, key string, value *yaml.Node) {
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		if name := mapping.Content[i]; name.Kind == yaml.ScalarNode && name.Value == key {
			mapping.Content[i+1] = value
			return
		}
	}
	mapping.Content = append(
		mapping.Content,
		&yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key},
		value,
	)
}

func deleteMappingKey(mapping *yaml.Node, key string) {
	if mapping == nil || mapping.Kind != yaml.MappingNode {
		return
	}
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		if name := mapping.Content[i]; name.Kind == yaml.ScalarNode && name.Value == key {
			mapping.Content = append(mapping.Content[:i], mapping.Content[i+2:]...)
			return
		}
	}
}

func isQuicRejectRule(rule string) bool {
	trimmed := strings.TrimSpace(rule)
	if trimmed == "" {
		return false
	}
	depth := 0
	var parts []string
	start := 0
	for i := 0; i < len(trimmed); i++ {
		switch trimmed[i] {
		case '(':
			depth++
		case ')':
			if depth > 0 {
				depth--
			}
		case ',':
			if depth == 0 {
				parts = append(parts, strings.TrimSpace(trimmed[start:i]))
				start = i + 1
			}
		}
	}
	parts = append(parts, strings.TrimSpace(trimmed[start:]))
	hasReject := false
	for i := len(parts) - 1; i >= 0; i-- {
		upper := strings.ToUpper(parts[i])
		if upper == "NO-RESOLVE" {
			continue
		}
		if upper == "REJECT" || upper == "REJECT-DROP" {
			hasReject = true
		}
		break
	}
	if !hasReject {
		return false
	}
	hasUDP := false
	hasPort443 := false
	visitRuleParts(trimmed, func(kind, payload string) bool {
		if kind == "NETWORK" && strings.EqualFold(payload, "UDP") {
			hasUDP = true
		} else if kind == "DST-PORT" && payload == "443" {
			hasPort443 = true
		}
		return hasUDP && hasPort443
	})
	return hasUDP && hasPort443
}

func stripQuicRejectRules(seq *yaml.Node) {
	if seq == nil || seq.Kind != yaml.SequenceNode {
		return
	}
	kept := make([]*yaml.Node, 0, len(seq.Content))
	for _, item := range seq.Content {
		resolved := resolveAlias(item)
		if resolved != nil && resolved.Kind == yaml.ScalarNode && isQuicRejectRule(resolved.Value) {
			continue
		}
		kept = append(kept, item)
	}
	seq.Content = kept
}

// The overlay's rules are the ones the host adds in front of the profile's.
func appendRules(added, profile *yaml.Node) (*yaml.Node, error) {
	if profile == nil {
		return nil, nil
	}
	added, profile = resolveAlias(added), resolveAlias(profile)
	if added == nil || isNull(added) || (added.Kind == yaml.SequenceNode && len(added.Content) == 0) {
		return profile, nil
	}
	if isNull(profile) {
		return added, nil
	}
	if added.Kind != yaml.SequenceNode || profile.Kind != yaml.SequenceNode {
		return nil, fmt.Errorf("line %d: rules must be a list", profile.Line)
	}
	content := make([]*yaml.Node, 0, len(added.Content)+len(profile.Content))
	content = append(append(content, added.Content...), profile.Content...)
	return &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: content}, nil
}

func resolveAlias(node *yaml.Node) *yaml.Node {
	for node != nil && node.Kind == yaml.AliasNode && node.Alias != nil {
		node = node.Alias
	}
	return node
}

func isNull(node *yaml.Node) bool {
	return node.Kind == yaml.ScalarNode && node.ShortTag() == "!!null"
}

// config.yaml is read again without this process: by the Android service
// starting on its own and by mihomo's own reload through the controller.
func writeConfigDocument(path string, document *yaml.Node) error {
	temporary, err := writeDocumentFile(filepath.Dir(path), ".config-*.yaml", document)
	if err != nil {
		return err
	}
	if err := os.Rename(temporary, path); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	scheduleReclaimOwnership()
	return nil
}

func writeDocumentFile(dir, pattern string, document *yaml.Node) (string, error) {
	inlineAliases(document)
	file, err := os.CreateTemp(dir, pattern)
	if err != nil {
		return "", err
	}
	writer := bufio.NewWriterSize(file, 1<<20)
	err = errors.Join(
		encodeConfigMapping(writer, document.Content[0]),
		writer.Flush(),
		file.Close(),
		os.Chmod(file.Name(), 0o644),
	)
	if err != nil {
		_ = os.Remove(file.Name())
		return "", err
	}
	return file.Name(), nil
}

// One Encode call keeps every event it emitted until it returns, several times
// the size of a large profile, so a long top-level list goes out in slices.
const encodeSliceLength = 4096

// The mapping is drained as it is written, so the parse that follows does not
// share the heap with the whole tree.
func encodeConfigMapping(w io.Writer, mapping *yaml.Node) error {
	for i := 0; i+1 < len(mapping.Content); i += 2 {
		key, value := mapping.Content[i], mapping.Content[i+1]
		mapping.Content[i+1] = nil
		if value.Kind != yaml.SequenceNode || len(value.Content) <= encodeSliceLength {
			pair := &yaml.Node{Kind: yaml.MappingNode, Tag: "!!map", Content: []*yaml.Node{key, value}}
			if err := encodeYamlPiece(w, pair, nil); err != nil {
				return err
			}
			continue
		}
		if err := encodeYamlPiece(w, key, []byte(":\n")); err != nil {
			return err
		}
		for start := 0; start < len(value.Content); start += encodeSliceLength {
			items := value.Content[start:min(start+encodeSliceLength, len(value.Content))]
			slice := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq", Content: items}
			if err := encodeYamlPiece(w, slice, nil); err != nil {
				return err
			}
			clear(items)
		}
	}
	return nil
}

// Each piece is a document of its own; an end marker left between two of them
// would end config.yaml there.
func encodeYamlPiece(w io.Writer, node *yaml.Node, suffix []byte) error {
	var buffer bytes.Buffer
	encoder := yaml.NewEncoder(&buffer)
	encoder.SetIndent(2)
	if err := errors.Join(encoder.Encode(node), encoder.Close()); err != nil {
		return err
	}
	piece := bytes.TrimSuffix(buffer.Bytes(), []byte("...\n"))
	if suffix != nil {
		piece = append(bytes.TrimSuffix(piece, []byte("\n")), suffix...)
	}
	_, err := w.Write(piece)
	return err
}

// An anchor may sit in a section the overlay replaced, so every alias is
// written out in full, as the host's own encoder always did.
func inlineAliases(root *yaml.Node) {
	visited := map[*yaml.Node]struct{}{}
	var walk func(node *yaml.Node)
	walk = func(node *yaml.Node) {
		if _, seen := visited[node]; seen {
			return
		}
		if node.Anchor != "" {
			visited[node] = struct{}{}
			node.Anchor = ""
		}
		for i, child := range node.Content {
			child = resolveAlias(child)
			node.Content[i] = child
			walk(child)
		}
	}
	walk(root)
}
