package core

import (
	"context"
	"slices"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

const (
	delayTestConcurrency    = 50
	defaultTestURL          = "https://www.gstatic.com/generate_204"
	defaultDelayTestTimeout = 5 * time.Second
)

var (
	delayTestSlots             = make(slots, delayTestConcurrency)
	defaultExpectedDelayStatus = mustDelayTestStatus("200-299")

	testURL                 atomic.Pointer[string]
	missingDelayTestProxyAt atomic.Int64
)

func setTestURL(url string) {
	if url == "" {
		return
	}
	constant.DefaultTestURL = url
	testURL.Store(&url)
}

func currentTestURL() string {
	if url := testURL.Load(); url != nil && *url != "" {
		return *url
	}
	return defaultTestURL
}

const (
	delayTimedOut int32 = -1
	delayFailed   int32 = -2
)

func delayValue(delay uint16, timedOut bool) int32 {
	switch {
	case delay > 0:
		return int32(delay)
	case timedOut:
		return delayTimedOut
	default:
		return delayFailed
	}
}

// A name the tunnel does not know is what an apply that fell back to the
// default config looks like: every node of the profile fails its test. Say so
// once a second, not once per node, so the log names the real failure.
func reportMissingDelayTestProxy(name string) {
	now := time.Now().UnixNano()
	last := missingDelayTestProxyAt.Load()
	if last != 0 && now-last < int64(time.Second) {
		return
	}
	if !missingDelayTestProxyAt.CompareAndSwap(last, now) {
		return
	}
	logError("delay test: %q is not part of the applied config", name)
}

func normalizeProbeURL(rawURL string) string {
	switch rawURL {
	case "http://www.gstatic.com/generate_204":
		return "https://www.gstatic.com/generate_204"
	case "http://cp.cloudflare.com/generate_204":
		return "https://cp.cloudflare.com/generate_204"
	case "http://connectivitycheck.gstatic.com/generate_204":
		return "https://connectivitycheck.gstatic.com/generate_204"
	default:
		return rawURL
	}
}

// A nil answer means the test never got a slot, which says nothing about the proxy.
func handleTestDelay(params *TestDelayParams) *Delay {
	url := params.TestUrl
	if url == "" {
		url = currentTestURL()
	}
	probeURL := normalizeProbeURL(url)
	result := &Delay{Name: params.ProxyName, Url: url, Value: delayFailed}

	proxy := lookupProxy(params.ProxyName)
	if proxy == nil {
		reportMissingDelayTestProxy(params.ProxyName)
		return result
	}

	timeout, configured := configuredTestTimeout(proxy.Name(), url)
	if !configured {
		timeout = timeoutFromMillis(params.Timeout, defaultDelayTestTimeout)
	}
	if !delayTestSlots.acquireWithin(context.Background(), timeout) {
		return nil
	}
	defer delayTestSlots.release()

	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	delay, err := proxy.URLTest(ctx, probeURL, defaultExpectedDelayStatus)
	if err != nil || !proxy.AliveForTestUrl(probeURL) {
		delay = 0
	}
	result.Value = delayValue(delay, ctx.Err() != nil)
	return result
}

func mustDelayTestStatus(spec string) utils.IntRanges[uint16] {
	ranges, err := utils.NewUnsignedRanges[uint16](spec)
	if err != nil {
		panic(err)
	}
	return ranges
}

type testTimeoutProvider interface {
	TestTimeout(url string) (time.Duration, bool)
}

// The longest stands, so no scheduled check passes a node the manual test fails.
func configuredTestTimeout(name, url string) (time.Duration, bool) {
	var longest time.Duration
	for _, pd := range tunnel.ProvidersSnapshot() {
		timed, ok := pd.(testTimeoutProvider)
		if !ok {
			continue
		}
		timeout, ok := timed.TestTimeout(url)
		if !ok || timeout <= longest {
			continue
		}
		if slices.ContainsFunc(pd.Proxies(), func(p constant.Proxy) bool { return p.Name() == name }) {
			longest = timeout
		}
	}
	return longest, longest > 0
}
