package core

import (
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func addSyntheticStreamTracker(
	t *testing.T,
	leafName string,
	dstPort uint16,
	start time.Time,
	upload int64,
	download int64,
) statistic.Tracker {
	t.Helper()
	local, remote := net.Pipe()
	t.Cleanup(func() {
		_ = local.Close()
		_ = remote.Close()
	})
	direct := outbound.NewDirectWithOption(outbound.DirectOption{Name: leafName})
	meta := &constant.Metadata{
		NetWork: constant.TCP,
		DstPort: dstPort,
	}
	tracker := statistic.NewTCPTracker(
		outbound.NewConn(local, direct),
		statistic.DefaultManager,
		meta,
		nil,
		upload,
		download,
		false,
	)
	info := tracker.Info()
	info.Start = start
	info.Chain = constant.Chain{leafName, "Proxy"}
	t.Cleanup(func() {
		_ = tracker.Close()
	})
	return tracker
}

func TestDetectStalledActiveProxyBlackholedStreams(t *testing.T) {
	now := time.Now()
	addSyntheticStreamTracker(t, "node-a", 443, now.Add(-10*time.Second), 512, 0)
	addSyntheticStreamTracker(t, "node-a", 443, now.Add(-9*time.Second), 1024, 0)

	leaf, stalled := detectStalledActiveProxy(now)
	if !stalled || leaf != "node-a" {
		t.Fatalf("detectStalledActiveProxy = (%q, %t), want (%q, true)", leaf, stalled, "node-a")
	}
}

func TestDetectStalledActiveProxyThrottledStreams(t *testing.T) {
	now := time.Now()
	addSyntheticStreamTracker(t, "node-b", 443, now.Add(-14*time.Second), 2048, 500)
	addSyntheticStreamTracker(t, "node-b", 443, now.Add(-13*time.Second), 4096, 500)
	addSyntheticStreamTracker(t, "node-b", 443, now.Add(-12*time.Second), 2048, 500)

	leaf, stalled := detectStalledActiveProxy(now)
	if !stalled || leaf != "node-b" {
		t.Fatalf("detectStalledActiveProxy throttled = (%q, %t), want (%q, true)", leaf, stalled, "node-b")
	}
}

func TestDetectStalledActiveProxyIgnoresPushPorts(t *testing.T) {
	now := time.Now()
	addSyntheticStreamTracker(t, "node-push", 5228, now.Add(-30*time.Second), 2048, 0)
	addSyntheticStreamTracker(t, "node-push", 5229, now.Add(-25*time.Second), 2048, 0)

	if leaf, stalled := detectStalledActiveProxy(now); stalled {
		t.Fatalf("detectStalledActiveProxy flagged push notification streams (%q, true)", leaf)
	}
}

func TestQuarantineScoringPrefersCleanOverQuarantinedAndFallsBackToSoleSurvivor(t *testing.T) {
	now := time.Now()
	t.Cleanup(func() {
		smartFailoverMu.Lock()
		quarantinedNodes = map[string]time.Time{}
		smartFailoverMu.Unlock()
	})

	quarantineNode("node-flaky", now)
	if !isNodeQuarantined("node-flaky", now.Add(30*time.Second)) {
		t.Fatal("expected node-flaky to stay quarantined within TTL")
	}
	if score := effectiveCandidateScore("node-flaky", 80, now); score != 80+smartFailoverQuarantinePenaltyMs {
		t.Fatalf("effectiveCandidateScore(node-flaky) = %d, want %d", score, 80+smartFailoverQuarantinePenaltyMs)
	}

	delays := map[string]int{
		"node-flaky": 80,
		"node-clean": 220,
	}
	best, raw := selectBestCandidateFromDelays(delays, []string{"node-flaky", "node-clean"}, now)
	if best != "node-clean" || raw != 220 {
		t.Fatalf("selectBestCandidateFromDelays = (%q, %d), want (%q, 220)", best, raw, "node-clean")
	}

	soleBest, soleRaw := selectBestCandidateFromDelays(
		map[string]int{"node-flaky": 80},
		[]string{"node-flaky"},
		now,
	)
	if soleBest != "node-flaky" || soleRaw != 80 {
		t.Fatalf("sole survivor fallback = (%q, %d), want (%q, 80)", soleBest, soleRaw, "node-flaky")
	}
}

func TestSetAutoFailoverToggle(t *testing.T) {
	previous := IsAutoFailoverEnabled()
	t.Cleanup(func() { SetAutoFailover(previous) })

	if !previous {
		t.Fatal("expected autoFailoverEnabled to default to true")
	}
	SetAutoFailover(false)
	if IsAutoFailoverEnabled() {
		t.Fatal("expected IsAutoFailoverEnabled() == false after SetAutoFailover(false)")
	}
	SetAutoFailover(true)
	if !IsAutoFailoverEnabled() {
		t.Fatal("expected IsAutoFailoverEnabled() == true after SetAutoFailover(true)")
	}
}
