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
	if !isAndroidRuntime {
		return
	}
	if dnsNode := resolveAlias(mappingValue(root, "dns")); dnsNode != nil && dnsNode.Kind == yaml.MappingNode {
		if !isExplicitBool(mappingValue(dnsNode, "enable"), false) {
			ensureSystemDNSNode(dnsNode, "default-nameserver")
			ensureSystemDNSNode(dnsNode, "proxy-server-nameserver")
		}
	}
	if !documentHasProcessRule(root) {
		setMappingValue(root, "find-process-mode", strNode("off"))
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
