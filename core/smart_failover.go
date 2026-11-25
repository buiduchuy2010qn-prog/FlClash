package core

import (
	"context"
	"slices"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

const (
	smartFailoverTickInterval          = 15 * time.Second
	smartFailoverPeriodicProbeInterval = 180 * time.Second
	smartFailoverSuspectProbeInterval  = 60 * time.Second
	smartFailoverFastCandidateMs       = 1000
	smartFailoverSlowDelayMs           = 1800
	smartFailoverHysteresisMs          = 100
	smartFailoverSwitchCooldown        = 20 * time.Second
	smartFailoverQuarantineTTL         = 3 * time.Minute
	smartFailoverQuarantinePenaltyMs   = 1500
	smartFailoverConfirmWait           = 500 * time.Millisecond
	smartFailoverProbeTimeout          = 4 * time.Second

	stalledZeroDownAge        = 8 * time.Second
	stalledZeroDownMinUpload  = 256
	stalledThrottledAge       = 12 * time.Second
	stalledThrottledMinUpload = 1024
	stalledMaxTotalDownload   = 2048
)

var (
	autoFailoverEnabled atomic.Bool

	smartFailoverMu     sync.Mutex
	smartFailoverCancel context.CancelFunc
	lastPeriodicProbeAt time.Time
	lastAutoSwitchAt    time.Time
	quarantinedNodes    = map[string]time.Time{}
)

func init() {
	autoFailoverEnabled.Store(false)
}

func SetAutoFailover(enabled bool) {
	autoFailoverEnabled.Store(enabled)
}

func IsAutoFailoverEnabled() bool {
	return autoFailoverEnabled.Load()
}

func startSmartFailoverMonitor() {
	smartFailoverMu.Lock()
	defer smartFailoverMu.Unlock()
	if smartFailoverCancel != nil {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	smartFailoverCancel = cancel
	go runSmartFailoverLoop(ctx)
}

func stopSmartFailoverMonitor() {
	smartFailoverMu.Lock()
	cancel := smartFailoverCancel
	smartFailoverCancel = nil
	smartFailoverMu.Unlock()
	if cancel != nil {
		cancel()
	}
}

func runSmartFailoverLoop(ctx context.Context) {
	ticker := time.NewTicker(smartFailoverTickInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			evaluateSmartFailover(ctx)
		}
	}
}

func isSmartFailoverBuiltinName(name string) bool {
	switch name {
	case "DIRECT", "REJECT", "REJECT-DROP", "PASS":
		return true
	default:
		return false
	}
}

func isPushNotificationPort(port uint16) bool {
	return port == 5228 || port == 5229 || port == 5230
}

type leafStreamStats struct {
	zeroDownConns  int
	throttledConns int
	totalDown      int64
}

func detectStalledProxyInStats(activeLeaf string, now time.Time) (string, bool) {
	statsByLeaf := map[string]*leafStreamStats{}
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		info := c.Info()
		if info == nil || len(info.Chain) == 0 || info.Metadata == nil {
			return true
		}
		if isPushNotificationPort(info.Metadata.DstPort) {
			return true
		}
		leaf := info.Chain[0]
		if leaf == "" || isSmartFailoverBuiltinName(leaf) {
			return true
		}
		if activeLeaf != "" && leaf != activeLeaf {
			return true
		}
		entry := statsByLeaf[leaf]
		if entry == nil {
			entry = &leafStreamStats{}
			statsByLeaf[leaf] = entry
		}
		age := now.Sub(info.Start)
		up := info.UploadTotal.Load()
		down := info.DownloadTotal.Load()
		if age >= stalledZeroDownAge && up >= stalledZeroDownMinUpload && down == 0 {
			entry.zeroDownConns++
		}
		if age >= stalledThrottledAge && up >= stalledThrottledMinUpload {
			entry.throttledConns++
			entry.totalDown += down
		}
		return true
	})

	isStalled := func(entry *leafStreamStats) bool {
		if entry == nil {
			return false
		}
		return entry.zeroDownConns >= 2 || (entry.throttledConns >= 3 && entry.totalDown < stalledMaxTotalDownload)
	}

	if activeLeaf != "" {
		if isStalled(statsByLeaf[activeLeaf]) {
			return activeLeaf, true
		}
		return "", false
	}

	leaves := make([]string, 0, len(statsByLeaf))
	for leaf := range statsByLeaf {
		leaves = append(leaves, leaf)
	}
	slices.Sort(leaves)
	for _, leaf := range leaves {
		if isStalled(statsByLeaf[leaf]) {
			return leaf, true
		}
	}
	return "", false
}

func detectStalledActiveProxy(now time.Time) (proxyName string, stalled bool) {
	if _, _, activeLeaf, ok := findPrimarySelectorGroup(); ok {
		return detectStalledProxyInStats(activeLeaf, now)
	}
	return detectStalledProxyInStats("", now)
}

func quarantineNode(name string, now time.Time) {
	if name == "" {
		return
	}
	smartFailoverMu.Lock()
	defer smartFailoverMu.Unlock()
	for k, until := range quarantinedNodes {
		if !now.Before(until) {
			delete(quarantinedNodes, k)
		}
	}
	quarantinedNodes[name] = now.Add(smartFailoverQuarantineTTL)
}

func clearQuarantinesLocked(now time.Time) {
	for k, until := range quarantinedNodes {
		if !now.Before(until) {
			delete(quarantinedNodes, k)
		}
	}
}

func isNodeQuarantined(name string, now time.Time) bool {
	smartFailoverMu.Lock()
	defer smartFailoverMu.Unlock()
	clearQuarantinesLocked(now)
	until, ok := quarantinedNodes[name]
	return ok && now.Before(until)
}

func effectiveCandidateScore(name string, rawDelayMs int, now time.Time) int {
	if isNodeQuarantined(name, now) {
		return rawDelayMs + smartFailoverQuarantinePenaltyMs
	}
	return rawDelayMs
}

func selectBestCandidateFromDelays(delays map[string]int, orderedCandidates []string, now time.Time) (bestName string, bestRawDelay int) {
	bestScore := int(^uint(0) >> 1)
	for _, name := range orderedCandidates {
		rawDelay := delays[name]
		if rawDelay <= 0 {
			continue
		}
		score := effectiveCandidateScore(name, rawDelay, now)
		if score < bestScore || (score == bestScore && rawDelay < bestRawDelay) {
			bestScore = score
			bestRawDelay = rawDelay
			bestName = name
		}
	}
	return bestName, bestRawDelay
}

func findPrimarySelectorGroup() (groupName string, group outboundgroup.ProxyGroup, currentPick string, ok bool) {
	proxies := tunnel.AllProxies()
	if len(proxies) == 0 {
		return "", nil, "", false
	}

	inspect := func(name string, requireVisible bool) (string, outboundgroup.ProxyGroup, string, bool) {
		p := proxies[name]
		if p == nil || p.Type() != constant.Selector {
			return "", nil, "", false
		}
		pg, ok := adapterAs[outboundgroup.ProxyGroup](p)
		if !ok {
			return "", nil, "", false
		}
		if _, ok := adapterAs[outboundgroup.SelectAble](p); !ok {
			return "", nil, "", false
		}
		if requireVisible && pg.Hidden() {
			return "", nil, "", false
		}
		return name, pg, pg.Now(), true
	}

	if tunnel.Mode() == tunnel.Global {
		if name, pg, now, matched := inspect(globalProxyName, false); matched {
			return name, pg, now, true
		}
	}

	for _, name := range config.GetProxyNameList() {
		if gName, pg, now, matched := inspect(name, true); matched {
			return gName, pg, now, true
		}
	}
	return "", nil, "", false
}

func isLeafSwitchTarget(name string) bool {
	if name == "" || isSmartFailoverBuiltinName(name) {
		return false
	}
	p := lookupProxy(name)
	if p == nil {
		return false
	}
	return !isProxyGroupType(p.Type())
}

func probeLeafDelayMs(ctx context.Context, proxyName, probeURL string, timeout time.Duration) int {
	proxy := lookupProxy(proxyName)
	if proxy == nil {
		return int(delayFailed)
	}
	probeCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	delay, err := proxy.URLTest(probeCtx, probeURL, defaultExpectedDelayStatus)
	if err != nil || !proxy.AliveForTestUrl(probeURL) {
		return int(delayFailed)
	}
	if delay == 0 {
		return int(delayTimedOut)
	}
	return int(delay)
}

func selectFailoverCandidateSequential(
	ctx context.Context,
	candidates []string,
	currentPick string,
	now time.Time,
	probe func(ctx context.Context, name string) int,
) (string, int) {
	if len(candidates) == 0 || probe == nil {
		return "", 0
	}
	var cleanCandidates []string
	var quarantinedCandidates []string
	for _, name := range candidates {
		if name == "" || name == currentPick {
			continue
		}
		if isNodeQuarantined(name, now) {
			quarantinedCandidates = append(quarantinedCandidates, name)
		} else {
			cleanCandidates = append(cleanCandidates, name)
		}
	}

	probePass := func(pool []string) (string, int) {
		bestName := ""
		bestDelay := 0
		for _, name := range pool {
			if ctx.Err() != nil {
				break
			}
			delay := probe(ctx, name)
			if delay <= 0 {
				continue
			}
			if delay < smartFailoverFastCandidateMs {
				return name, delay
			}
			if bestName == "" || delay < bestDelay {
				bestName = name
				bestDelay = delay
			}
		}
		return bestName, bestDelay
	}

	if name, delay := probePass(cleanCandidates); name != "" {
		return name, delay
	}
	return probePass(quarantinedCandidates)
}

func closeConnectionsForLeaf(leafName string) {
	if leafName == "" {
		return
	}
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		info := c.Info()
		if info == nil || len(info.Chain) == 0 {
			return true
		}
		if slices.Contains(info.Chain, leafName) {
			_ = c.Close()
		}
		return true
	})
}

func evaluateSmartFailover(ctx context.Context) {
	if ctx.Err() != nil || !isRunning.Load() || !IsAutoFailoverEnabled() {
		return
	}

	now := time.Now()
	smartFailoverMu.Lock()
	withinCooldown := !lastAutoSwitchAt.IsZero() && now.Sub(lastAutoSwitchAt) < smartFailoverSwitchCooldown
	periodicDue := lastPeriodicProbeAt.IsZero() || now.Sub(lastPeriodicProbeAt) >= smartFailoverPeriodicProbeInterval
	suspectDue := lastPeriodicProbeAt.IsZero() || now.Sub(lastPeriodicProbeAt) >= smartFailoverSuspectProbeInterval
	smartFailoverMu.Unlock()
	if withinCooldown {
		return
	}

	groupName, group, currentPick, ok := findPrimarySelectorGroup()
	if !ok || !isLeafSwitchTarget(currentPick) {
		return
	}

	stalledLeaf, stalled := detectStalledProxyInStats(currentPick, now)
	stalledSuspected := stalled && stalledLeaf == currentPick && suspectDue
	if handleGetConnectionCount() == 0 || (!periodicDue && !stalledSuspected) {
		return
	}

	smartFailoverMu.Lock()
	lastPeriodicProbeAt = now
	smartFailoverMu.Unlock()

	probeURL := normalizeProbeURL(currentTestURL())
	firstDelay := probeLeafDelayMs(ctx, currentPick, probeURL, smartFailoverProbeTimeout)
	if firstDelay > 0 {
		return
	}

	timer := time.NewTimer(smartFailoverConfirmWait)
	select {
	case <-ctx.Done():
		timer.Stop()
		return
	case <-timer.C:
	}

	if ctx.Err() != nil || !isRunning.Load() || !IsAutoFailoverEnabled() {
		return
	}
	confirmedDelay := probeLeafDelayMs(ctx, currentPick, probeURL, smartFailoverProbeTimeout)
	if confirmedDelay > 0 {
		return
	}
	quarantineNode(currentPick, time.Now())

	rawProxies := group.Proxies()
	candidates := make([]string, 0, len(rawProxies))
	for _, p := range rawProxies {
		if p == nil {
			continue
		}
		name := p.Name()
		if !isLeafSwitchTarget(name) {
			continue
		}
		candidates = append(candidates, name)
	}
	if len(candidates) <= 1 {
		return
	}

	checkNow := time.Now()
	bestName, bestRawDelay := selectFailoverCandidateSequential(
		ctx,
		candidates,
		currentPick,
		checkNow,
		func(probeCtx context.Context, name string) int {
			return probeLeafDelayMs(probeCtx, name, probeURL, smartFailoverProbeTimeout)
		},
	)
	if bestName == "" || bestName == currentPick {
		return
	}

	closeConnectionsForLeaf(currentPick)
	res := handleChangeProxy(&ChangeProxyParams{GroupName: groupName, ProxyName: bestName})
	if res == nil || !res.Changed {
		return
	}
	smartFailoverMu.Lock()
	lastAutoSwitchAt = time.Now()
	smartFailoverMu.Unlock()

	closeConnectionsForLeaf(currentPick)
	log.Infoln("[SmartFailover] switched %s: %s -> %s (%dms)", groupName, currentPick, bestName, bestRawDelay)
}
