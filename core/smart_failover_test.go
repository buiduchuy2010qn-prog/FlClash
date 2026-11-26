package core

import (
	"context"
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

	if previous {
		t.Fatal("expected autoFailoverEnabled to default to false")
	}
	SetAutoFailover(true)
	if !IsAutoFailoverEnabled() {
		t.Fatal("expected IsAutoFailoverEnabled() == true after SetAutoFailover(true)")
	}
	SetAutoFailover(false)
	if IsAutoFailoverEnabled() {
		t.Fatal("expected IsAutoFailoverEnabled() == false after SetAutoFailover(false)")
	}
}

func TestSelectFailoverCandidateSequentialEarlyExitsOnFirstFastNode(t *testing.T) {
	now := time.Now()
	t.Cleanup(func() {
		smartFailoverMu.Lock()
		quarantinedNodes = map[string]time.Time{}
		smartFailoverMu.Unlock()
	})

	quarantineNode("node-quarantined", now)
	candidates := []string{
		"node-current",
		"node-dead",
		"node-fast-1",
		"node-fast-2",
		"node-fast-3",
		"node-quarantined",
	}
	probed := []string{}
	best, delay := selectFailoverCandidateSequential(
		t.Context(),
		candidates,
		"node-current",
		now,
		func(_ context.Context, name string) int {
			probed = append(probed, name)
			switch name {
			case "node-dead":
				return -1
			case "node-fast-1":
				return 120
			default:
				return 80
			}
		},
	)
	if best != "node-fast-1" || delay != 120 {
		t.Fatalf("selectFailoverCandidateSequential = (%q, %d), want (%q, 120)", best, delay, "node-fast-1")
	}
	wantProbed := []string{"node-dead", "node-fast-1"}
	if len(probed) != len(wantProbed) || probed[0] != wantProbed[0] || probed[1] != wantProbed[1] {
		t.Fatalf("probed = %v, want %v (must stop on first healthy fast node)", probed, wantProbed)
	}

	slowProbed := []string{}
	slowBest, slowDelay := selectFailoverCandidateSequential(
		t.Context(),
		[]string{"node-current", "node-quarantined", "node-slow-a", "node-slow-b"},
		"node-current",
		now,
		func(_ context.Context, name string) int {
			slowProbed = append(slowProbed, name)
			if name == "node-slow-a" {
				return 1400
			}
			if name == "node-slow-b" {
				return 1100
			}
			return 90
		},
	)
	if slowBest != "node-slow-b" || slowDelay != 1100 {
		t.Fatalf("slow clean fallback = (%q, %d), want (%q, 1100)", slowBest, slowDelay, "node-slow-b")
	}
	if len(slowProbed) != 2 {
		t.Fatalf("expected quarantined node to be skipped when clean node responds, probed=%v", slowProbed)
	}
}

func TestShouldSwitchForDegradedPing(t *testing.T) {
	if shouldSwitchForDegradedPing(350, 90, false) {
		t.Fatal("should not switch when current delay is healthy (<1200ms)")
	}
	if shouldSwitchForDegradedPing(1450, 900, false) {
		t.Fatal("should not switch when best candidate is also slow (>=650ms)")
	}
	if shouldSwitchForDegradedPing(1300, 1050, false) {
		t.Fatal("should not switch when improvement is below threshold")
	}
	if !shouldSwitchForDegradedPing(1400, 180, false) {
		t.Fatal("expected switch when current ping is >=1200ms and fast node <650ms exists")
	}
	if !shouldSwitchForDegradedPing(0, 0, false) {
		t.Fatal("expected switch on dead node")
	}
}

func TestDegradedFailoverDoesNotStopInDeadZone(t *testing.T) {
	now := time.Now()
	probed := []string{}
	best, delay := selectFailoverCandidateSequential(
		t.Context(),
		[]string{"active-slow", "med-slow", "fast-sg"},
		"active-slow",
		now,
		func(_ context.Context, name string) int {
			probed = append(probed, name)
			if name == "med-slow" {
				return 720
			}
			return 85
		},
	)
	if len(probed) != 2 || probed[0] != "med-slow" || probed[1] != "fast-sg" {
		t.Fatalf("probed = %v, want [med-slow fast-sg]", probed)
	}
	if best != "fast-sg" || delay != 85 {
		t.Fatalf("best = (%q, %d), want (fast-sg, 85)", best, delay)
	}
	if !shouldSwitchForDegradedPing(1350, delay, false) {
		t.Fatal("expected switch from 1350ms to 85ms")
	}
}
