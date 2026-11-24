package core

import (
	"context"
	"errors"
	"net/netip"
	"path/filepath"
	"slices"
	"testing"

	"github.com/metacubex/mihomo/component/resolver"
	D "github.com/miekg/dns"
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

func TestOptimizeProxyGroupsFallbackAndAuto(t *testing.T) {
	previousAndroid := isAndroidRuntime
	isAndroidRuntime = false
	t.Cleanup(func() { isAndroidRuntime = previousAndroid })

	const input = `proxies:
  - {name: node1, type: vless, server: node1.example.com, port: 80, uuid: 11111111-1111-1111-1111-111111111111}
  - {name: node2, type: vless, server: node2.example.net, port: 443, uuid: 11111111-1111-1111-1111-111111111111, tls: true}
proxy-groups:
  - {name: ProxyMain, type: select, proxies: [AutoFallback, node1, node2]}
  - {name: AutoFallback, type: fallback, proxies: [node1, node2], url: 'http://cp.cloudflare.com/', interval: 7200}
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
		ProxyGroups []struct {
			Name           string   `yaml:"name"`
			Type           string   `yaml:"type"`
			URL            string   `yaml:"url"`
			Interval       int      `yaml:"interval"`
			Timeout        int      `yaml:"timeout"`
			Lazy           bool     `yaml:"lazy"`
			Tolerance      int      `yaml:"tolerance"`
			ExpectedStatus string   `yaml:"expected-status"`
			MaxFailedTimes int      `yaml:"max-failed-times"`
			Proxies        []string `yaml:"proxies"`
		} `yaml:"proxy-groups"`
	}
	if err := yaml.Unmarshal(out, &parsed); err != nil {
		t.Fatalf("decode: %v\n%s", err, string(out))
	}
	if len(parsed.ProxyGroups) != 3 {
		t.Fatalf("proxy-groups len = %d, want 3 (select + fallback + Auto): %+v", len(parsed.ProxyGroups), parsed.ProxyGroups)
	}
	sel := parsed.ProxyGroups[0]
	if len(sel.Proxies) < 2 || sel.Proxies[0] != "Auto" || sel.Proxies[1] != "AutoFallback" {
		t.Errorf("ProxyMain proxies = %v, want [Auto AutoFallback ...]", sel.Proxies)
	}
	fb := parsed.ProxyGroups[1]
	if fb.Interval != 180 || fb.Timeout != 5000 || !fb.Lazy || fb.ExpectedStatus != "200-299" || fb.MaxFailedTimes != 2 || fb.URL != "https://www.gstatic.com/generate_204" {
		t.Errorf("AutoFallback not optimized: %+v", fb)
	}
	auto := parsed.ProxyGroups[2]
	if auto.Name != "Auto" || auto.Type != "url-test" || auto.Interval != 180 || auto.Timeout != 5000 || !auto.Lazy || auto.Tolerance != 100 || auto.ExpectedStatus != "200-299" || auto.MaxFailedTimes != 2 {
		t.Errorf("Auto group not built properly: %+v", auto)
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
    - https://1.1.1.1/dns-query
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
	if slices.Contains(parsed.DNS.Nameserver, "system") || slices.Contains(parsed.DNS.Nameserver, "system://") {
		t.Errorf("dns.nameserver still contains system entry: %v", parsed.DNS.Nameserver)
	}
	if !slices.Contains(parsed.DNS.Nameserver, "1.1.1.1") || !slices.Contains(parsed.DNS.Nameserver, "8.8.8.8") {
		t.Errorf("dns.nameserver missing plain resolvers: %v", parsed.DNS.Nameserver)
	}
	if !slices.Contains(parsed.DNS.DefaultNameserver, "system") ||
		!slices.Contains(parsed.DNS.ProxyServerNameserver, "system") ||
		!slices.Contains(parsed.DNS.DirectNameserver, "system") {
		t.Errorf("bootstrap resolvers missing system: %+v", parsed.DNS)
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
		return nil, errors.New("carrier blocked doh")
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
