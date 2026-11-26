package core

import (
	"context"
	"errors"
	"net/netip"
	"path/filepath"
	"slices"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	D "github.com/miekg/dns"
	"go.yaml.in/yaml/v3"
)

func TestOptimizeConfigDocumentAndroidMobileDefaults(t *testing.T) {
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
		IPv6    *bool               `yaml:"ipv6"`
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
			IPv6                  *bool    `yaml:"ipv6"`
			PreferH3              bool     `yaml:"prefer-h3"`
			UseHosts              bool     `yaml:"use-hosts"`
			RespectRules          bool     `yaml:"respect-rules"`
			Nameserver            []string `yaml:"nameserver"`
			DefaultNameserver     []string `yaml:"default-nameserver"`
			ProxyServerNameserver []string `yaml:"proxy-server-nameserver"`
			DirectNameserver      []string `yaml:"direct-nameserver"`
			FakeIPFilter          []string `yaml:"fake-ip-filter"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("unmarshal optimized YAML: %v\n%s", err, string(out))
	}
	if parsed.IPv6 == nil || *parsed.IPv6 {
		t.Errorf("root ipv6 = %v, want false", parsed.IPv6)
	}
	if parsed.DNS.IPv6 == nil || *parsed.DNS.IPv6 {
		t.Errorf("dns.ipv6 = %v, want false", parsed.DNS.IPv6)
	}
	if !parsed.Profile.StoreFakeIP {
		t.Errorf("profile.store-fake-ip = false, want true")
	}
	if !slices.Contains(parsed.Hosts["1dot1dot1dot1.cloudflare-dns.com"], "1.1.1.1") {
		t.Errorf("hosts missing DoT static entry: %#v", parsed.Hosts)
	}
	if !parsed.Sniffer.Enable ||
		!slices.Contains(parsed.Sniffer.Sniff["TLS"].Ports, "853") ||
		!slices.Contains(parsed.Sniffer.Sniff["TLS"].Ports, "5228") ||
		!slices.Contains(parsed.Sniffer.Sniff["TLS"].Ports, "5229") ||
		!slices.Contains(parsed.Sniffer.Sniff["TLS"].Ports, "5230") {
		t.Errorf("sniffer missing TLS DoT/FCM ports: %#v", parsed.Sniffer)
	}
	if parsed.DNS.PreferH3 {
		t.Errorf("dns prefer-h3 = true, want false")
	}
	if !parsed.DNS.RespectRules || !parsed.DNS.UseHosts {
		t.Errorf("dns respect-rules/use-hosts not enabled: %+v", parsed.DNS)
	}
	for _, legacy := range []string{"1.1.1.1", "8.8.8.8"} {
		if slices.Contains(parsed.DNS.Nameserver, legacy) {
			t.Errorf("dns.nameserver still contains bare UDP resolver %q: %v", legacy, parsed.DNS.Nameserver)
		}
	}
	for _, wantNS := range androidTCPDNSResolvers {
		if !slices.Contains(parsed.DNS.Nameserver, wantNS) {
			t.Errorf("dns.nameserver missing TCP/DoH resolver %q: %v", wantNS, parsed.DNS.Nameserver)
		}
	}
	if !slices.Contains(parsed.DNS.DefaultNameserver, "system") ||
		!slices.Contains(parsed.DNS.ProxyServerNameserver, "system") ||
		!slices.Contains(parsed.DNS.DirectNameserver, "system") {
		t.Errorf("dns missing system bootstrap nameserver: %+v", parsed.DNS)
	}
	if !slices.Contains(parsed.DNS.FakeIPFilter, "1dot1dot1dot1.cloudflare-dns.com") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "connectivitycheck.gstatic.com") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "connectivitycheck.android.com") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "mtalk.google.com") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "alt1-mtalk.google.com") {
		t.Errorf("fake-ip-filter missing DoT/connectivity/FCM domains: %v", parsed.DNS.FakeIPFilter)
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
  prefer-h3: true
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
			PreferH3     bool     `yaml:"prefer-h3"`
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
	if !parsed.DNS.PreferH3 {
		t.Error("explicit dns.prefer-h3=true was overridden")
	}
	if len(parsed.DNS.FakeIPFilter) != 1 || parsed.DNS.FakeIPFilter[0] != "only.me" {
		t.Errorf("whitelist fake-ip-filter was polluted: %v", parsed.DNS.FakeIPFilter)
	}

	const ruleInput = `dns:
  enable: true
  fake-ip-filter-mode: rule
  fake-ip-filter:
    - DOMAIN,example.com,real-ip
`
	var ruleDoc yaml.Node
	if err := yaml.Unmarshal([]byte(ruleInput), &ruleDoc); err != nil {
		t.Fatalf("unmarshal ruleInput: %v", err)
	}
	optimizeConfigDocument(&ruleDoc, nil)
	ruleOut, err := yaml.Marshal(&ruleDoc)
	if err != nil {
		t.Fatalf("marshal ruleOut: %v", err)
	}
	var parsedRule struct {
		DNS struct {
			FakeIPFilter []string `yaml:"fake-ip-filter"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(ruleOut, &parsedRule); err != nil {
		t.Fatalf("decode ruleOut: %v", err)
	}
	if len(parsedRule.DNS.FakeIPFilter) != 1 || parsedRule.DNS.FakeIPFilter[0] != "DOMAIN,example.com,real-ip" {
		t.Errorf("rule-mode fake-ip-filter was polluted with plain domains: %v", parsedRule.DNS.FakeIPFilter)
	}
}

func TestOptimizeProxyGroupsFallbackAndAuto(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = false
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `proxies:
  - {name: node1, type: vless, server: node1.example.com, port: 80, uuid: 11111111-1111-1111-1111-111111111111}
  - {name: node2, type: vless, server: node2.example.net, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true}
proxy-providers:
  sub:
    type: file
    path: ./sub.yaml
    health-check:
      enable: true
      url: https://www.gstatic.com/generate_204
      interval: 300
proxy-groups:
  - {name: ProxyMain, type: select, proxies: [AutoFallback, AutoShort, node1, node2]}
  - {name: AutoFallback, type: fallback, proxies: [node1, node2], url: 'http://cp.cloudflare.com/', interval: 7200}
  - {name: AutoShort, type: url-test, proxies: [node1, node2], interval: 120}
  - {name: Streaming, type: select, proxies: [AutoShort, node1, node2]}
  - {name: AdBlock, type: select, proxies: [REJECT, DIRECT]}
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
		ProxyProviders map[string]struct {
			HealthCheck struct {
				Enable   bool `yaml:"enable"`
				Interval int  `yaml:"interval"`
			} `yaml:"health-check"`
		} `yaml:"proxy-providers"`
		ProxyGroups []struct {
			Name     string   `yaml:"name"`
			Type     string   `yaml:"type"`
			Interval int      `yaml:"interval"`
			Hidden   bool     `yaml:"hidden"`
			Proxies  []string `yaml:"proxies"`
		} `yaml:"proxy-groups"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v\n%s", err, string(out))
	}
	if subHC := parsed.ProxyProviders["sub"].HealthCheck; subHC.Enable || subHC.Interval != 0 {
		t.Errorf("proxy-providers.sub.health-check = %+v, want disabled with interval 0", subHC)
	}
	if len(parsed.ProxyGroups) != 5 {
		t.Fatalf("proxy-groups len = %d, want 5: %+v", len(parsed.ProxyGroups), parsed.ProxyGroups)
	}
	sel := parsed.ProxyGroups[0]
	if sel.Type != "select" || len(sel.Proxies) != 2 || sel.Proxies[0] != "node1" || sel.Proxies[1] != "node2" {
		t.Errorf("ProxyMain proxies = %v, want [node1 node2]", sel.Proxies)
	}
	fb := parsed.ProxyGroups[1]
	if fb.Type != "select" || fb.Interval != 0 || !fb.Hidden || len(fb.Proxies) == 0 || fb.Proxies[0] != "ProxyMain" {
		t.Errorf("AutoFallback not unified cleanly: %+v", fb)
	}
	shortGroup := parsed.ProxyGroups[2]
	if shortGroup.Type != "select" || shortGroup.Interval != 0 || !shortGroup.Hidden || len(shortGroup.Proxies) == 0 || shortGroup.Proxies[0] != "ProxyMain" {
		t.Errorf("AutoShort not unified cleanly: %+v", shortGroup)
	}
	streaming := parsed.ProxyGroups[3]
	if len(streaming.Proxies) == 0 || streaming.Proxies[0] != "ProxyMain" {
		t.Errorf("Streaming proxies = %v, want ProxyMain at index 0", streaming.Proxies)
	}
	adBlock := parsed.ProxyGroups[4]
	if len(adBlock.Proxies) == 0 || adBlock.Proxies[0] != "REJECT" {
		t.Errorf("AdBlock reject-first order changed: %v", adBlock.Proxies)
	}
}

func TestEnsureAndroidDNSStripsSystemNameserver(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - system://
    - 1.1.1.1
    - udp://8.8.8.8:53
    - https://9.9.9.9/dns-query
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
		DNS struct {
			Nameserver            []string `yaml:"nameserver"`
			DefaultNameserver     []string `yaml:"default-nameserver"`
			ProxyServerNameserver []string `yaml:"proxy-server-nameserver"`
			DirectNameserver      []string `yaml:"direct-nameserver"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v", err)
	}
	for _, removed := range []string{"system", "system://", "1.1.1.1", "udp://8.8.8.8:53"} {
		if slices.Contains(parsed.DNS.Nameserver, removed) {
			t.Errorf("dns.nameserver still contains legacy entry %q: %v", removed, parsed.DNS.Nameserver)
		}
	}
	if !slices.Contains(parsed.DNS.Nameserver, "https://9.9.9.9/dns-query") {
		t.Errorf("dns.nameserver lost custom entry: %v", parsed.DNS.Nameserver)
	}
	for _, wantNS := range androidTCPDNSResolvers {
		if !slices.Contains(parsed.DNS.Nameserver, wantNS) {
			t.Errorf("dns.nameserver missing TCP/DoH resolver %q: %v", wantNS, parsed.DNS.Nameserver)
		}
	}
	if !slices.Contains(parsed.DNS.DefaultNameserver, "system") ||
		!slices.Contains(parsed.DNS.ProxyServerNameserver, "system") ||
		!slices.Contains(parsed.DNS.DirectNameserver, "system") {
		t.Errorf("bootstrap resolvers missing system: %+v", parsed.DNS)
	}
}

func TestOptimizeConfigDocumentAndroidParsesInMihomo(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	previousHome := constant.Path.HomeDir()
	home := t.TempDir()
	constant.SetHomeDir(home)
	t.Cleanup(func() {
		isAndroidRuntime = previousAndroid
		constant.SetHomeDir(previousHome)
		setDeferredGeoResources(nil)
	})

	const input = `mode: global
proxies:
  - name: n1
    type: vless
    server: node.example.net
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    tls: true
    network: ws
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 1.1.1.1
    - 8.8.8.8
rules:
  - MATCH,n1
`
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(input), &doc); err != nil {
		t.Fatalf("unmarshal input: %v", err)
	}
	optimizeConfigDocument(&doc, nil)

	out, err := yaml.Marshal(&doc)
	if err != nil {
		t.Fatalf("marshal optimized YAML: %v", err)
	}
	raw := config.DefaultRawConfig()
	if err := yaml.Unmarshal(out, raw); err != nil {
		t.Fatalf("decode raw config: %v\n%s", err, string(out))
	}
	if !raw.Profile.StoreFakeIP {
		t.Fatal("expected optimized raw config to enable profile.store-fake-ip")
	}
	// Keep fake-ip pool in memory during this host parse test so bbolt's
	// process-wide cache.db handle does not lock t.TempDir() on Windows.
	raw.Profile.StoreFakeIP = false
	prepareRawConfigForParse(raw)
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		t.Fatalf("config.ParseRawConfig failed on optimized Android config: %v\n%s", err, string(out))
	}
	if cfg == nil || cfg.DNS == nil || !cfg.DNS.Enable {
		t.Fatalf("expected parsed config with active DNS, got: %#v", cfg)
	}
}

type stubResolver struct {
	ips []netip.Addr
	err error
}

func (s *stubResolver) LookupIP(_ context.Context, _ string) ([]netip.Addr, error) {
	return s.ips, s.err
}

func (s *stubResolver) LookupIPv4(_ context.Context, _ string) ([]netip.Addr, error) {
	return s.ips, s.err
}

func (s *stubResolver) LookupIPv6(_ context.Context, _ string) ([]netip.Addr, error) {
	return nil, s.err
}

func (s *stubResolver) ResolveECH(_ context.Context, _ string) ([]byte, error) {
	return nil, s.err
}

func (s *stubResolver) ExchangeContext(_ context.Context, _ *D.Msg) (*D.Msg, error) {
	return nil, s.err
}

func (s *stubResolver) Invalid() bool {
	return true
}

func (s *stubResolver) ClearCache() {}

func (s *stubResolver) ResetConnection() {}

var _ resolver.Resolver = (*stubResolver)(nil)

func TestResilientProxyHostResolverCacheAndCaptiveFilter(t *testing.T) {
	bogons := []netip.Addr{
		netip.MustParseAddr("10.0.0.1"),
		netip.MustParseAddr("100.64.0.5"),
		netip.MustParseAddr("198.18.0.10"),
		netip.MustParseAddr("127.0.0.1"),
		netip.MustParseAddr("172.67.168.158"),
	}
	usable := usableProxyIPv4s("node2.example.net", bogons)
	if len(usable) != 1 || usable[0] != netip.MustParseAddr("172.67.168.158") {
		t.Fatalf("usableProxyIPv4s = %v, want only 172.67.168.158", usable)
	}

	cachePath := filepath.Join(t.TempDir(), proxyHostCacheFilename)
	upstream := &stubResolver{ips: []netip.Addr{netip.MustParseAddr("172.67.168.158")}}
	r := newResilientProxyHostResolver(upstream, cachePath)
	r.dohQuery = func(_ context.Context, _ string) ([]netip.Addr, error) {
		return nil, errors.New("offline")
	}

	got, err := r.LookupIPv4(context.Background(), "node2.example.net")
	if err != nil || len(got) != 1 || got[0] != netip.MustParseAddr("172.67.168.158") {
		t.Fatalf("initial LookupIPv4 = (%v, %v), want 172.67.168.158", got, err)
	}
	r.flushCacheToDisk()

	r.mu.Lock()
	if r.persistWait != nil {
		r.persistWait.Stop()
	}
	r.mu.Unlock()

	failingUpstream := &stubResolver{ips: []netip.Addr{netip.MustParseAddr("10.149.204.129")}}
	r2 := newResilientProxyHostResolver(failingUpstream, cachePath)
	r2.dohQuery = func(_ context.Context, _ string) ([]netip.Addr, error) {
		return nil, errors.New("doh unreachable")
	}
	fallback, err := r2.LookupIPv4(context.Background(), "node2.example.net")
	if err != nil || len(fallback) != 1 || fallback[0] != netip.MustParseAddr("172.67.168.158") {
		t.Fatalf("disk-cached fallback = (%v, %v), want 172.67.168.158", fallback, err)
	}

	r2.ClearCache()
	stillCached, err := r2.LookupIPv4(context.Background(), "node2.example.net")
	if err != nil || len(stillCached) != 1 {
		t.Fatalf("ClearCache wiped proxy host cache: (%v, %v)", stillCached, err)
	}
}

func TestSetTelemetryPausedClearsTrafficAndGatesTelemetry(t *testing.T) {
	t.Cleanup(func() {
		SetTelemetryPaused(false)
		currentRequestTraffic.clear()
	})

	currentRequestTraffic.clear()
	SetTelemetryPaused(false)
	if isTelemetryPaused() {
		t.Fatal("expected telemetry to start unpaused")
	}
	tracker := newPipeTracker(t)
	watchRequestTraffic(tracker)
	currentRequestTraffic.mu.Lock()
	countBeforePause := len(currentRequestTraffic.requests)
	_, hasBeforePause := currentRequestTraffic.requests[tracker.ID()]
	currentRequestTraffic.mu.Unlock()
	if countBeforePause != 1 || !hasBeforePause {
		t.Fatalf("tracked requests = %d (has tracker=%t), want 1 (true)", countBeforePause, hasBeforePause)
	}

	SetTelemetryPaused(true)
	if !isTelemetryPaused() {
		t.Fatal("expected isTelemetryPaused() == true after SetTelemetryPaused(true)")
	}
	currentRequestTraffic.mu.Lock()
	countAfterPause := len(currentRequestTraffic.requests)
	runningAfterPause := currentRequestTraffic.running
	currentRequestTraffic.mu.Unlock()
	if countAfterPause != 0 || runningAfterPause {
		t.Fatalf("expected cleared traffic watch after pause, got count=%d running=%t", countAfterPause, runningAfterPause)
	}

	watchRequestTraffic(tracker)
	currentRequestTraffic.mu.Lock()
	countWhilePaused := len(currentRequestTraffic.requests)
	currentRequestTraffic.mu.Unlock()
	if countWhilePaused != 0 {
		t.Fatalf("watchRequestTraffic added request while paused: %d", countWhilePaused)
	}

	SetTelemetryPaused(false)
	if isTelemetryPaused() {
		t.Fatal("expected isTelemetryPaused() == false after SetTelemetryPaused(false)")
	}
}

func TestOptimizeConfigSanitizesHijackedHostsAndPrioritizesRealNodes(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `hosts:
  ibanking.vietcombank.com.vn: 203.0.113.99
  localhost: 127.0.0.1
proxies:
  - name: "Dung lượng: 95 GB"
    type: vless
    server: 127.0.0.1
    port: 1
    uuid: 11111111-1111-1111-1111-111111111111
  - name: "Singapore-01"
    type: vless
    server: sg1.example.net
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    tls: true
proxy-groups:
  - name: MainProxy
    type: select
    proxies:
      - "Dung lượng: 95 GB"
      - "Singapore-01"
dns:
  enable: true
  enhanced-mode: fake-ip
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
		Hosts       map[string]any `yaml:"hosts"`
		ProxyGroups []struct {
			Name    string   `yaml:"name"`
			Proxies []string `yaml:"proxies"`
		} `yaml:"proxy-groups"`
		DNS struct {
			FakeIPFilter []string `yaml:"fake-ip-filter"`
		} `yaml:"dns"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if _, leaked := parsed.Hosts["ibanking.vietcombank.com.vn"]; leaked {
		t.Fatalf("expected hijacked sensitive host entry to be removed, got %#v", parsed.Hosts)
	}
	if _, ok := parsed.Hosts["localhost"]; !ok {
		t.Fatalf("expected localhost host entry to remain, got %#v", parsed.Hosts)
	}
	if len(parsed.ProxyGroups) != 1 || parsed.ProxyGroups[0].Proxies[0] != "Singapore-01" {
		t.Fatalf("expected real node before info banner node, got %+v", parsed.ProxyGroups)
	}
	if !slices.Contains(parsed.DNS.FakeIPFilter, "stun.*.*") ||
		!slices.Contains(parsed.DNS.FakeIPFilter, "msftconnecttest.com") {
		t.Fatalf("expected STUN and captive domains in fake-ip-filter: %v", parsed.DNS.FakeIPFilter)
	}
}

func TestGlobalSelectorAutoBindsToPrimaryGroupInsteadOfDirect(t *testing.T) {
	prevMode := tunnel.Mode()
	prevNames := config.GetProxyNameList()
	t.Cleanup(func() {
		tunnel.SetMode(prevMode)
		config.SetProxyNameList(prevNames)
		tunnel.UpdateProxies(nil, nil)
	})

	direct := adapter.NewProxy(outbound.NewDirect())
	compatible := adapter.NewProxy(outbound.NewCompatible())
	nodeA := adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: "NodeA"}))
	hcMain := provider.NewHealthCheck([]constant.Proxy{nodeA}, "", 5000, 0, true, nil)
	pdMain, err := provider.NewCompatibleProvider("main-pd", []constant.Proxy{nodeA}, hcMain)
	if err != nil {
		t.Fatalf("NewCompatibleProvider(main-pd): %v", err)
	}
	mainSelect, err := outboundgroup.NewSelector(
		outboundgroup.GroupCommonOption{Name: "MainSelect"},
		outboundgroup.SelectorOption{},
		compatible,
		[]cp.ProxyProvider{pdMain},
	)
	if err != nil {
		t.Fatalf("NewSelector(MainSelect): %v", err)
	}
	mainSelectProxy := adapter.NewProxy(mainSelect)
	hcGlobal := provider.NewHealthCheck([]constant.Proxy{direct, nodeA, mainSelectProxy}, "", 5000, 0, true, nil)
	pdGlobal, err := provider.NewCompatibleProvider(
		provider.ReservedName,
		[]constant.Proxy{direct, nodeA, mainSelectProxy},
		hcGlobal,
	)
	if err != nil {
		t.Fatalf("NewCompatibleProvider(ReservedName): %v", err)
	}
	globalGroup, err := outboundgroup.NewSelector(
		outboundgroup.GroupCommonOption{Name: globalProxyName},
		outboundgroup.SelectorOption{},
		compatible,
		[]cp.ProxyProvider{pdGlobal},
	)
	if err != nil {
		t.Fatalf("NewSelector(GLOBAL): %v", err)
	}

	tunnel.UpdateProxies(
		map[string]constant.Proxy{
			"DIRECT":        direct,
			"COMPATIBLE":    compatible,
			"NodeA":         nodeA,
			"MainSelect":    mainSelectProxy,
			globalProxyName: adapter.NewProxy(globalGroup),
		},
		map[string]cp.ProxyProvider{
			"main-pd":             pdMain,
			provider.ReservedName: pdGlobal,
		},
	)
	config.SetProxyNameList([]string{"DIRECT", "NodeA", "MainSelect"})
	tunnel.SetMode(tunnel.Global)

	patchSelectGroup(nil)
	if got := globalGroup.Now(); got != "MainSelect" {
		t.Fatalf("GLOBAL.Now() after auto-bind = %q, want %q", got, "MainSelect")
	}

	gName, _, currentPick, ok := findPrimarySelectorGroup()
	if !ok || gName != "MainSelect" || currentPick != "NodeA" {
		t.Fatalf("findPrimarySelectorGroup = (%q, %q, %t), want (%q, %q, true)", gName, currentPick, ok, "MainSelect", "NodeA")
	}

	patchSelectGroup(map[string]string{globalProxyName: "DIRECT"})
	if got := globalGroup.Now(); got != "MainSelect" {
		t.Fatalf("stale GLOBAL=DIRECT was not healed to MainSelect, got %q", got)
	}

	patchSelectGroup(map[string]string{globalProxyName: "NodeA"})
	if got := globalGroup.Now(); got != "NodeA" {
		t.Fatalf("explicit GLOBAL=NodeA was overridden, got %q", got)
	}
}

func TestOptimizeProxyNodesUnlocksHysteria2CapAndHighBDPWindows(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = true
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `proxies:
  - name: Hy2-TemplateCap
    type: hysteria2
    server: hy2.example.net
    port: 443
    password: secret
    up: 50 Mbps
    down: 100 Mbps
  - name: Hy2-HighExplicit
    type: hysteria2
    server: hy2fast.example.net
    port: 443
    password: secret
    up: 500 Mbps
    down: 1000 Mbps
  - name: Vless-Main
    type: vless
    server: vless.example.net
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    tls: true
  - name: Tuic-Main
    type: tuic
    server: tuic.example.net
    port: 443
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
		Proxies []map[string]any `yaml:"proxies"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v\n%s", err, string(out))
	}
	if len(parsed.Proxies) != 4 {
		t.Fatalf("proxies len = %d, want 4", len(parsed.Proxies))
	}

	hyCap := parsed.Proxies[0]
	if _, hasUp := hyCap["up"]; hasUp {
		t.Errorf("expected template up cap to be stripped, got %#v", hyCap)
	}
	if _, hasDown := hyCap["down"]; hasDown {
		t.Errorf("expected template down cap to be stripped, got %#v", hyCap)
	}
	if hyCap["initial-stream-receive-window"] != quicInitStreamRecvWin ||
		hyCap["max-stream-receive-window"] != quicMaxStreamRecvWin ||
		hyCap["initial-connection-receive-window"] != quicInitConnRecvWin ||
		hyCap["max-connection-receive-window"] != quicMaxConnRecvWin {
		t.Errorf("unexpected hysteria2 QUIC windows: %#v", hyCap)
	}

	hyHigh := parsed.Proxies[1]
	if hyHigh["up"] != "500 Mbps" || hyHigh["down"] != "1000 Mbps" {
		t.Errorf("expected high explicit caps >300Mbps to stay, got up=%v down=%v", hyHigh["up"], hyHigh["down"])
	}

	vless := parsed.Proxies[2]
	if vless["udp"] != true || vless["packet-encoding"] != "xudp" {
		t.Errorf("expected udp=true and packet-encoding=xudp on vless, got %#v", vless)
	}

	tuic := parsed.Proxies[3]
	if tuic["recv-window-conn"] != quicMaxStreamRecvWin || tuic["recv-window"] != quicMaxConnRecvWin {
		t.Errorf("expected QUIC windows on tuic, got %#v", tuic)
	}
}
