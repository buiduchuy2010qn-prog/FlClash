package core

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/netip"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/http"
	"github.com/metacubex/mihomo/component/ca"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	D "github.com/miekg/dns"
)

const (
	proxyHostCacheFilename      = "proxy_host_cache.json"
	proxyHostLookupTimeout      = 2500 * time.Millisecond
	proxyHostRefreshMinSpacing  = 60 * time.Second
	proxyHostPersistDelay       = 500 * time.Millisecond
	proxyHostPrewarmConcurrency = 4
)

var (
	cgnatPrefix  = netip.MustParsePrefix("100.64.0.0/10")
	fakeIPPrefix = netip.MustParsePrefix("198.18.0.0/15")

	proxyHostResolverMu     sync.Mutex
	activeProxyHostResolver *resilientProxyHostResolver

	prewarmTimerMu sync.Mutex
	prewarmTimer   *time.Timer
)

type proxyResolverCtxKey struct{}

func withSkipDoHFallback(ctx context.Context) context.Context {
	return context.WithValue(ctx, proxyResolverCtxKey{}, true)
}

func shouldSkipDoHFallback(ctx context.Context) bool {
	skip, _ := ctx.Value(proxyResolverCtxKey{}).(bool)
	return skip
}

func normalizeHostKey(host string) string {
	return strings.TrimSuffix(strings.ToLower(strings.TrimSpace(host)), ".")
}

func isPublicDomainHost(host string) bool {
	key := normalizeHostKey(host)
	if key == "" {
		return false
	}
	if _, err := netip.ParseAddr(key); err == nil {
		return false
	}
	if !strings.Contains(key, ".") {
		return false
	}
	for _, suffix := range []string{".local", ".lan", ".localhost", ".test", ".invalid", ".internal", ".home", ".arpa"} {
		if strings.HasSuffix(key, suffix) {
			return false
		}
	}
	return true
}

func isUsablePublicIPv4(ip netip.Addr) bool {
	ip = ip.Unmap()
	if !ip.Is4() || !ip.IsGlobalUnicast() {
		return false
	}
	if ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsMulticast() || ip.IsUnspecified() {
		return false
	}
	if cgnatPrefix.Contains(ip) || fakeIPPrefix.Contains(ip) {
		return false
	}
	return true
}

func usableProxyIPv4s(host string, ips []netip.Addr) []netip.Addr {
	publicDomain := isPublicDomainHost(host)
	seen := make(map[netip.Addr]struct{}, len(ips))
	out := make([]netip.Addr, 0, len(ips))
	for _, raw := range ips {
		ip := raw.Unmap()
		if !ip.Is4() {
			continue
		}
		if publicDomain && !isUsablePublicIPv4(ip) {
			continue
		}
		if _, exists := seen[ip]; exists {
			continue
		}
		seen[ip] = struct{}{}
		out = append(out, ip)
	}
	return out
}

func filterPublicLookupIPs(host string, ips []netip.Addr) []netip.Addr {
	if !isPublicDomainHost(host) {
		out := make([]netip.Addr, len(ips))
		for i, ip := range ips {
			out[i] = ip.Unmap()
		}
		return out
	}
	v4 := usableProxyIPv4s(host, ips)
	var v6 []netip.Addr
	seen := make(map[netip.Addr]struct{}, len(ips))
	for _, raw := range ips {
		ip := raw.Unmap()
		if ip.Is4() || !ip.Is6() || !ip.IsGlobalUnicast() || ip.IsPrivate() || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
			continue
		}
		if _, exists := seen[ip]; exists {
			continue
		}
		seen[ip] = struct{}{}
		v6 = append(v6, ip)
	}
	return append(v4, v6...)
}

type resilientProxyHostResolver struct {
	base        resolver.Resolver
	cachePath   string
	mu          sync.RWMutex
	cache       map[string][]netip.Addr
	lastRefresh map[string]time.Time
	persistWait *time.Timer
	dohQuery    func(ctx context.Context, host string) ([]netip.Addr, error)
}

func newResilientProxyHostResolver(base resolver.Resolver, cachePath string) *resilientProxyHostResolver {
	r := &resilientProxyHostResolver{
		base:        unwrapProxyHostResolver(base),
		cachePath:   cachePath,
		cache:       map[string][]netip.Addr{},
		lastRefresh: map[string]time.Time{},
		dohQuery:    defaultDoHQueryIPv4,
	}
	r.loadCacheFromDisk()
	return r
}

func unwrapProxyHostResolver(r resolver.Resolver) resolver.Resolver {
	for r != nil {
		wrapped, ok := r.(*resilientProxyHostResolver)
		if !ok {
			return r
		}
		r = wrapped.base
	}
	return nil
}

func (r *resilientProxyHostResolver) upstream() resolver.Resolver {
	r.mu.RLock()
	base := r.base
	r.mu.RUnlock()
	if base != nil && base.Invalid() {
		return base
	}
	return resolver.SystemResolver
}

func (r *resilientProxyHostResolver) Invalid() bool {
	return true
}

func (r *resilientProxyHostResolver) ClearCache() {
	if upstream := r.upstream(); upstream != nil {
		upstream.ClearCache()
	}
}

func (r *resilientProxyHostResolver) ResetConnection() {
	if upstream := r.upstream(); upstream != nil {
		upstream.ResetConnection()
	}
}

func (r *resilientProxyHostResolver) ExchangeContext(ctx context.Context, m *D.Msg) (*D.Msg, error) {
	if upstream := r.upstream(); upstream != nil {
		return upstream.ExchangeContext(ctx, m)
	}
	return nil, resolver.ErrIPNotFound
}

func (r *resilientProxyHostResolver) ResolveECH(ctx context.Context, host string) ([]byte, error) {
	if upstream := r.upstream(); upstream != nil {
		return upstream.ResolveECH(ctx, host)
	}
	return nil, resolver.ErrIPNotFound
}

func (r *resilientProxyHostResolver) LookupIPv6(ctx context.Context, host string) ([]netip.Addr, error) {
	if upstream := r.upstream(); upstream != nil {
		return upstream.LookupIPv6(ctx, host)
	}
	return nil, resolver.ErrIPNotFound
}

func (r *resilientProxyHostResolver) LookupIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	if ip, err := netip.ParseAddr(strings.TrimSpace(host)); err == nil {
		ip = ip.Unmap()
		if ip.Is4() {
			return []netip.Addr{ip}, nil
		}
		return []netip.Addr{}, resolver.ErrIPVersion
	}

	key := normalizeHostKey(host)
	upstream := r.upstream()
	var upstreamErr error
	if upstream != nil {
		lookupCtx, cancel := context.WithTimeout(ctx, proxyHostLookupTimeout)
		ips, err := upstream.LookupIPv4(lookupCtx, host)
		cancel()
		if err == nil {
			if usable := usableProxyIPv4s(host, ips); len(usable) > 0 {
				r.storeCached(key, usable)
				return usable, nil
			}
			upstreamErr = fmt.Errorf("%w: filtered non-public IPv4 for %s", resolver.ErrIPNotFound, host)
		} else {
			upstreamErr = err
		}
	}

	if cached := r.getCached(key); len(cached) > 0 {
		if !shouldSkipDoHFallback(ctx) && isPublicDomainHost(key) {
			r.triggerAsyncRefresh(key)
		}
		return cached, nil
	}

	if !shouldSkipDoHFallback(ctx) && isPublicDomainHost(key) && r.dohQuery != nil {
		dohCtx, cancel := context.WithTimeout(withSkipDoHFallback(ctx), proxyHostLookupTimeout)
		ips, err := r.dohQuery(dohCtx, key)
		cancel()
		if err == nil {
			if usable := usableProxyIPv4s(key, ips); len(usable) > 0 {
				r.storeCached(key, usable)
				return usable, nil
			}
		} else if upstreamErr == nil {
			upstreamErr = err
		}
	}

	if upstreamErr != nil {
		return nil, upstreamErr
	}
	return nil, fmt.Errorf("%w: %s", resolver.ErrIPNotFound, host)
}

func (r *resilientProxyHostResolver) LookupIP(ctx context.Context, host string) ([]netip.Addr, error) {
	if ip, err := netip.ParseAddr(strings.TrimSpace(host)); err == nil {
		return []netip.Addr{ip.Unmap()}, nil
	}
	if resolver.DisableIPv6 {
		return r.LookupIPv4(ctx, host)
	}
	key := normalizeHostKey(host)
	if upstream := r.upstream(); upstream != nil {
		lookupCtx, cancel := context.WithTimeout(ctx, proxyHostLookupTimeout)
		ips, err := upstream.LookupIP(lookupCtx, host)
		cancel()
		if err == nil {
			if v4 := usableProxyIPv4s(host, ips); len(v4) > 0 {
				r.storeCached(key, v4)
			}
			if filtered := filterPublicLookupIPs(host, ips); len(filtered) > 0 {
				return filtered, nil
			}
		}
	}
	return r.LookupIPv4(ctx, host)
}

func (r *resilientProxyHostResolver) getCached(key string) []netip.Addr {
	if key == "" {
		return nil
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	stored := r.cache[key]
	if len(stored) == 0 {
		return nil
	}
	out := make([]netip.Addr, len(stored))
	copy(out, stored)
	return out
}

func (r *resilientProxyHostResolver) storeCached(key string, ips []netip.Addr) {
	if !isPublicDomainHost(key) || len(ips) == 0 {
		return
	}
	copied := make([]netip.Addr, len(ips))
	copy(copied, ips)

	r.mu.Lock()
	r.cache[key] = copied
	if r.cachePath != "" {
		if r.persistWait != nil {
			r.persistWait.Stop()
		}
		r.persistWait = time.AfterFunc(proxyHostPersistDelay, r.flushCacheToDisk)
	}
	r.mu.Unlock()
}

func (r *resilientProxyHostResolver) triggerAsyncRefresh(key string) {
	if r.dohQuery == nil || !isPublicDomainHost(key) {
		return
	}
	now := time.Now()
	r.mu.Lock()
	if prev, ok := r.lastRefresh[key]; ok && now.Sub(prev) < proxyHostRefreshMinSpacing {
		r.mu.Unlock()
		return
	}
	r.lastRefresh[key] = now
	r.mu.Unlock()

	safeGo("refreshProxyHostCache", func() {
		ctx, cancel := context.WithTimeout(withSkipDoHFallback(context.Background()), proxyHostLookupTimeout)
		defer cancel()
		ips, err := r.dohQuery(ctx, key)
		if err != nil {
			return
		}
		if usable := usableProxyIPv4s(key, ips); len(usable) > 0 {
			r.storeCached(key, usable)
		}
	})
}

func (r *resilientProxyHostResolver) loadCacheFromDisk() {
	if r.cachePath == "" {
		return
	}
	buf, err := os.ReadFile(r.cachePath)
	if err != nil {
		return
	}
	var raw map[string][]string
	if err := json.Unmarshal(buf, &raw); err != nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	for host, values := range raw {
		key := normalizeHostKey(host)
		if !isPublicDomainHost(key) {
			continue
		}
		var parsed []netip.Addr
		for _, text := range values {
			if addr, parseErr := netip.ParseAddr(strings.TrimSpace(text)); parseErr == nil {
				parsed = append(parsed, addr)
			}
		}
		if usable := usableProxyIPv4s(key, parsed); len(usable) > 0 {
			r.cache[key] = usable
		}
	}
}

func (r *resilientProxyHostResolver) flushCacheToDisk() {
	if r.cachePath == "" {
		return
	}
	r.mu.RLock()
	snapshot := make(map[string][]string, len(r.cache))
	for host, addrs := range r.cache {
		list := make([]string, 0, len(addrs))
		for _, addr := range addrs {
			list = append(list, addr.String())
		}
		if len(list) > 0 {
			snapshot[host] = list
		}
	}
	r.mu.RUnlock()

	data, err := json.MarshalIndent(snapshot, "", "  ")
	if err != nil {
		return
	}
	_ = os.MkdirAll(filepath.Dir(r.cachePath), 0o700)
	tmp := r.cachePath + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return
	}
	if err := os.Rename(tmp, r.cachePath); err != nil {
		_ = os.WriteFile(r.cachePath, data, 0o600)
		_ = os.Remove(tmp)
	}
}

type dohJSONResponse struct {
	Answer []struct {
		Type int    `json:"type"`
		Data string `json:"data"`
	} `json:"Answer"`
}

func queryDoHOverDialer(ctx context.Context, host string, dialFn func(context.Context, string, string) (net.Conn, error)) ([]netip.Addr, error) {
	tlsConfig, err := ca.GetTLSConfig(ca.Option{})
	if err != nil {
		return nil, err
	}
	tlsConfig.ServerName = "cloudflare-dns.com"
	transport := &http.Transport{
		DialContext:         dialFn,
		TLSClientConfig:     tlsConfig,
		TLSHandshakeTimeout: proxyHostLookupTimeout,
		DisableKeepAlives:   true,
	}
	defer transport.CloseIdleConnections()

	target := "https://1.1.1.1/dns-query?name=" + url.QueryEscape(host) + "&type=A"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/dns-json")

	client := &http.Client{Transport: transport}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = resp.Body.Close()
	}()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("doh http status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 64*1024))
	if err != nil {
		return nil, err
	}
	var payload dohJSONResponse
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, err
	}
	addrs := make([]netip.Addr, 0, len(payload.Answer))
	for _, ans := range payload.Answer {
		if ans.Type != 1 {
			continue
		}
		if ip, parseErr := netip.ParseAddr(strings.TrimSpace(ans.Data)); parseErr == nil {
			addrs = append(addrs, ip)
		}
	}
	return usableProxyIPv4s(host, addrs), nil
}

func aliveLeafProxyForDoH() constant.Proxy {
	for _, p := range tunnel.AllProxies() {
		t := p.Type()
		if isProxyGroupType(t) || t == constant.Direct || t == constant.Reject || t == constant.RejectDrop || t == constant.Pass || t == constant.Compatible {
			continue
		}
		if p.AliveForTestUrl("") {
			return p
		}
	}
	return nil
}

func defaultDoHQueryIPv4(ctx context.Context, host string) ([]netip.Addr, error) {
	raceCtx, cancel := context.WithTimeout(withSkipDoHFallback(ctx), proxyHostLookupTimeout)
	defer cancel()

	type dohResult struct {
		ips []netip.Addr
		err error
	}
	ch := make(chan dohResult, 2)
	attempts := 1
	go func() {
		ips, err := queryDoHOverDialer(raceCtx, host, func(dctx context.Context, network, address string) (net.Conn, error) {
			return dialer.DialContext(dctx, network, address)
		})
		ch <- dohResult{ips: ips, err: err}
	}()

	if leaf := aliveLeafProxyForDoH(); leaf != nil {
		attempts++
		go func() {
			ips, err := queryDoHOverDialer(raceCtx, host, func(dctx context.Context, network, address string) (net.Conn, error) {
				md, err := probeMetadata(address)
				if err != nil {
					return nil, err
				}
				return leaf.DialContext(dctx, md)
			})
			ch <- dohResult{ips: ips, err: err}
		}()
	}

	var lastErr error
	for i := 0; i < attempts; i++ {
		select {
		case res := <-ch:
			if res.err == nil && len(res.ips) > 0 {
				return res.ips, nil
			}
			if res.err != nil {
				lastErr = res.err
			}
		case <-raceCtx.Done():
			return nil, raceCtx.Err()
		}
	}
	if lastErr != nil {
		return nil, lastErr
	}
	return nil, fmt.Errorf("%w: doh empty answer for %s", resolver.ErrIPNotFound, host)
}

func installResilientProxyHostResolver() {
	home := constant.Path.HomeDir()
	cachePath := ""
	if home != "" {
		cachePath = filepath.Join(home, proxyHostCacheFilename)
	}
	base := unwrapProxyHostResolver(resolver.ProxyServerHostResolver)

	proxyHostResolverMu.Lock()
	defer proxyHostResolverMu.Unlock()
	if activeProxyHostResolver == nil || activeProxyHostResolver.cachePath != cachePath {
		activeProxyHostResolver = newResilientProxyHostResolver(base, cachePath)
	} else {
		activeProxyHostResolver.mu.Lock()
		activeProxyHostResolver.base = base
		activeProxyHostResolver.mu.Unlock()
	}
	resolver.ProxyServerHostResolver = activeProxyHostResolver
}

func extractProxyServerHosts() []string {
	seen := map[string]struct{}{}
	addHost := func(raw string) {
		trimmed := strings.TrimSpace(raw)
		if trimmed == "" {
			return
		}
		if host, port, err := net.SplitHostPort(trimmed); err == nil && port != "" {
			if _, portErr := strconv.Atoi(port); portErr == nil {
				trimmed = host
			}
		}
		key := normalizeHostKey(trimmed)
		if !isPublicDomainHost(key) {
			return
		}
		seen[key] = struct{}{}
	}

	for _, p := range tunnel.AllProxies() {
		addHost(p.Addr())
	}
	if raw, err := readRawConfig(runningConfigPath()); err == nil && raw != nil {
		for _, proxyMap := range raw.Proxy {
			if server, ok := proxyMap["server"].(string); ok {
				addHost(server)
			}
		}
	}

	hosts := make([]string, 0, len(seen))
	for host := range seen {
		hosts = append(hosts, host)
	}
	return hosts
}

func schedulePrewarmProxyServerHosts(delay time.Duration) {
	prewarmTimerMu.Lock()
	if prewarmTimer != nil {
		prewarmTimer.Stop()
	}
	prewarmTimer = time.AfterFunc(delay, prewarmProxyServerHosts)
	prewarmTimerMu.Unlock()
}

func prewarmProxyServerHosts() {
	installResilientProxyHostResolver()
	hosts := extractProxyServerHosts()
	if len(hosts) == 0 {
		return
	}
	proxyHostResolverMu.Lock()
	r := activeProxyHostResolver
	proxyHostResolverMu.Unlock()
	if r == nil {
		return
	}

	sem := make(chan struct{}, proxyHostPrewarmConcurrency)
	var wg sync.WaitGroup
	for _, host := range hosts {
		h := host
		wg.Add(1)
		safeGo("prewarmProxyHost", func() {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()
			ctx, cancel := context.WithTimeout(context.Background(), 4*time.Second)
			defer cancel()
			if _, err := r.LookupIPv4(ctx, h); err != nil {
				log.Debugln("[DNS] proxy host prewarm %s: %v", h, err)
			}
		})
	}
	wg.Wait()
}
