package core

import (
	"slices"
	"testing"

	"go.yaml.in/yaml/v3"
)

func TestOptimizeConfigDocumentAndroidZeroRatingDefaults(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `proxies:
  - name: n1
    type: vless
    server: 1.2.3.4
    port: 443
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 1.1.1.1
`
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(input), &doc); err != nil {
		t.Fatalf("unmarshal input: %v", err)
	}

	optimizeConfigDocument(&doc, nil)

	out, err := yaml.Marshal(&doc)
	if err != nil {
		t.Fatalf("marshal output: %v", err)
	}
	var parsed struct {
		Hosts   map[string][]string `yaml:"hosts"`
		Profile struct {
			StoreFakeIP bool `yaml:"store-fake-ip"`
		} `yaml:"profile"`
		Sniffer struct {
			Enable bool `yaml:"enable"`
			Sniff  map[string]struct {
				Ports []string `yaml:"ports"`
			} `yaml:"sniff"`
		} `yaml:"sniffer"`
		DNS struct {
			UseHosts              bool     `yaml:"use-hosts"`
			RespectRules          bool     `yaml:"respect-rules"`
			DefaultNameserver     []string `yaml:"default-nameserver"`
			ProxyServerNameserver []string `yaml:"proxy-server-nameserver"`
			DirectNameserver      []string `yaml:"direct-nameserver"`
			FakeIPFilter          []string `yaml:"fake-ip-filter"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("unmarshal optimized YAML: %v\n%s", err, string(out))
	}
	if !parsed.Profile.StoreFakeIP {
		t.Errorf("profile.store-fake-ip = false, want true")
	}
	if !slices.Contains(parsed.Hosts["1dot1dot1dot1.cloudflare-dns.com"], "1.1.1.1") {
		t.Errorf("hosts missing DoT static entry: %#v", parsed.Hosts)
	}
	if !parsed.Sniffer.Enable || !slices.Contains(parsed.Sniffer.Sniff["TLS"].Ports, "853") {
		t.Errorf("sniffer missing TLS DoT port 853: %#v", parsed.Sniffer)
	}
	if !parsed.DNS.RespectRules || !parsed.DNS.UseHosts {
		t.Errorf("dns respect-rules/use-hosts not enabled: %+v", parsed.DNS)
	}
	if !slices.Contains(parsed.DNS.DefaultNameserver, "system") ||
		!slices.Contains(parsed.DNS.ProxyServerNameserver, "system") ||
		!slices.Contains(parsed.DNS.DirectNameserver, "system") {
		t.Errorf("dns missing system bootstrap nameserver: %+v", parsed.DNS)
	}
	if !slices.Contains(parsed.DNS.FakeIPFilter, "1dot1dot1dot1.cloudflare-dns.com") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "connectivitycheck.gstatic.com") {
		t.Errorf("fake-ip-filter missing DoT/connectivity domains: %v", parsed.DNS.FakeIPFilter)
	}
}

func TestOptimizeConfigDocumentPreservesExplicitDisables(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `sniffer:
  enable: false
dns:
  enable: true
  respect-rules: false
  fake-ip-filter-mode: whitelist
  fake-ip-filter:
    - only.me
`
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(input), &doc); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	optimizeConfigDocument(&doc, nil)

	out, err := yaml.Marshal(&doc)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	var parsed struct {
		Sniffer struct {
			Enable bool `yaml:"enable"`
		} `yaml:"sniffer"`
		DNS struct {
			RespectRules bool     `yaml:"respect-rules"`
			FakeIPFilter []string `yaml:"fake-ip-filter"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if parsed.Sniffer.Enable {
		t.Error("explicit sniffer.enable=false was overridden")
	}
	if parsed.DNS.RespectRules {
		t.Error("explicit dns.respect-rules=false was overridden")
	}
	if len(parsed.DNS.FakeIPFilter) != 1 || parsed.DNS.FakeIPFilter[0] != "only.me" {
		t.Errorf("whitelist fake-ip-filter was polluted: %v", parsed.DNS.FakeIPFilter)
	}
}
