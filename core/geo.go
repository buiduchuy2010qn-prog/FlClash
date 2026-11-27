package core

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/common/orderedmap"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

type geoResource struct {
	update func() error
	url    func() string
	setUrl func(string)
}

var geoResources = map[string]geoResource{
	"MMDB":    {update: updater.UpdateMMDB, url: geodata.MmdbUrl, setUrl: geodata.SetMmdbUrl},
	"ASN":     {update: updater.UpdateASN, url: geodata.ASNUrl, setUrl: geodata.SetASNUrl},
	"GEOIP":   {update: updater.UpdateGeoIp, url: geodata.GeoIpUrl, setUrl: geodata.SetGeoIpUrl},
	"GEOSITE": {update: updater.UpdateGeoSite, url: geodata.GeoSiteUrl, setUrl: geodata.SetGeoSiteUrl},
}

// mihomo's updaters read these links without a lock, so an unchanged one is never rewritten.
func setGeoResourceUrl(geoType string, link string) {
	resource, exist := geoResources[strings.ToUpper(geoType)]
	if !exist {
		log.Warnln("geox-url: unknown geo resource %q", geoType)
		return
	}
	if link != "" && link != resource.url() {
		resource.setUrl(link)
	}
}

func claimGeoUpdate(geoType string) bool {
	return claimUpdate(geoUpdateScope + geoType)
}

func releaseGeoUpdate(geoType string) {
	releaseUpdate(geoUpdateScope + geoType)
}

func handleUpdateGeoData(params GeoUpdateParams) error {
	geoType := params.Type
	resource, exist := geoResources[geoType]
	if !exist {
		logError("updateGeoData: unknown geo resource %q", geoType)
		return fmt.Errorf("unknown geo resource: %s", geoType)
	}
	if !claimGeoUpdate(geoType) {
		return fmt.Errorf("geo update already in progress: %s", geoType)
	}
	safeGo("updateGeoData("+geoType+")", func() {
		defer releaseGeoUpdate(geoType)
		if err := resource.update(); err != nil {
			logError("updateGeoData(%s) error: %v", geoType, err)
		}
	})
	return nil
}

func onGeoUpdate(geoType string, updating bool, skipped bool, updateErr error) {
	if updating {
		claimUpdateAs(geoUpdateScope+geoType, true)
	} else {
		releaseHookUpdate(geoUpdateScope + geoType)
		scheduleReclaimOwnership()
		if !skipped && updateErr == nil {
			changeRoute(routeMoved)
		}
	}
	status := GeoUpdateStatus{Type: geoType, Updating: updating, Skipped: skipped}
	if updateErr != nil {
		status.Error = updateErr.Error()
	}
	sendMessage(GeoUpdateMessage, status)
}

var (
	registerGeoUpdater = updater.RegisterGeoUpdaterWithCancel
	stopGeoUpdater     = updater.StopGeoUpdater
)

func syncGeoUpdater(autoUpdate *bool, interval *int) {
	changed := false
	if autoUpdate != nil && *autoUpdate != updater.GeoAutoUpdate() {
		updater.SetGeoAutoUpdate(*autoUpdate)
		changed = true
	}
	if interval != nil && *interval != updater.GeoUpdateInterval() {
		updater.SetGeoUpdateInterval(*interval)
		changed = true
	}
	if changed {
		reconcileGeoUpdater()
	}
}

func reconcileGeoUpdater() {
	if updater.GeoAutoUpdate() {
		registerGeoUpdater()
		return
	}
	stopGeoUpdater()
}

const deferredGeoDownloadDelay = 3 * time.Second

var (
	deferredGeoMu    sync.Mutex
	deferredGeoTypes []string
	deferredGeoTimer *time.Timer
)

type geoUsage struct {
	mmdb    bool
	geoip   bool
	geosite bool
	asn     bool
}

type geoAvailability struct {
	mmdb    bool
	geoip   bool
	geosite bool
	asn     bool
}

func geoFileExists(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir() && info.Size() > 0
}

func currentGeoAvailability() geoAvailability {
	return geoAvailability{
		mmdb:    geoFileExists(constant.Path.MMDB()),
		geoip:   geoFileExists(constant.Path.GeoIP()),
		geosite: geoFileExists(constant.Path.GeoSite()),
		asn:     geoFileExists(constant.Path.ASN()),
	}
}

func isGeoSitePattern(value string) bool {
	for _, part := range strings.Split(strings.ToLower(value), ",") {
		if strings.HasPrefix(strings.TrimSpace(part), "geosite:") {
			return true
		}
	}
	return false
}

func policyHasGeoSite(policy *orderedmap.OrderedMap[string, any]) bool {
	if policy == nil || policy.Len() == 0 {
		return false
	}
	for pair := policy.Oldest(); pair != nil; pair = pair.Next() {
		if isGeoSitePattern(pair.Key) {
			return true
		}
	}
	return false
}

func prunePolicyGeoSite(policy *orderedmap.OrderedMap[string, any]) bool {
	if policy == nil || policy.Len() == 0 {
		return false
	}
	removed := false
	for pair := policy.Oldest(); pair != nil; {
		next := pair.Next()
		if isGeoSitePattern(pair.Key) {
			policy.Delete(pair.Key)
			removed = true
		}
		pair = next
	}
	return removed
}

func ruleGeoNeeds(rule string, geodataMode bool) geoUsage {
	var needs geoUsage
	visitRuleParts(rule, func(kind, payload string) bool {
		switch kind {
		case "GEOIP", "SRC-GEOIP":
			if !strings.EqualFold(payload, "LAN") {
				if geodataMode {
					needs.geoip = true
				} else {
					needs.mmdb = true
				}
			}
		case "GEOSITE":
			needs.geosite = true
		case "IP-ASN", "SRC-IP-ASN":
			needs.asn = true
		}
		return false
	})
	return needs
}

func mergeGeoUsage(dst *geoUsage, src geoUsage) {
	dst.mmdb = dst.mmdb || src.mmdb
	dst.geoip = dst.geoip || src.geoip
	dst.geosite = dst.geosite || src.geosite
	dst.asn = dst.asn || src.asn
}

func analyzeGeoUsage(raw *config.RawConfig) geoUsage {
	var usage geoUsage
	if raw == nil {
		return usage
	}
	for _, rule := range raw.Rule {
		mergeGeoUsage(&usage, ruleGeoNeeds(rule, raw.GeodataMode))
	}
	for _, rules := range raw.SubRules {
		for _, rule := range rules {
			mergeGeoUsage(&usage, ruleGeoNeeds(rule, raw.GeodataMode))
		}
	}
	if raw.DNS.Enable {
		if len(raw.DNS.Fallback) > 0 && raw.DNS.FallbackFilter.GeoIP && !strings.EqualFold(strings.TrimSpace(raw.DNS.FallbackFilter.GeoIPCode), "LAN") {
			if raw.GeodataMode {
				usage.geoip = true
			} else {
				usage.mmdb = true
			}
		}
		if len(raw.DNS.Fallback) > 0 && len(raw.DNS.FallbackFilter.GeoSite) > 0 {
			usage.geosite = true
		}
		if policyHasGeoSite(raw.DNS.NameServerPolicy) || policyHasGeoSite(raw.DNS.ProxyServerNameserverPolicy) {
			usage.geosite = true
		}
		for _, item := range raw.DNS.FakeIPFilter {
			if isGeoSitePattern(item) {
				usage.geosite = true
				break
			}
		}
	}
	return usage
}

func pruneUnusedGeoFiles(raw *config.RawConfig) {
	if !isAndroidRuntime || raw == nil || len(raw.Proxy) == 0 {
		return
	}
	usage := analyzeGeoUsage(raw)
	if !usage.geoip {
		_ = os.Remove(constant.Path.GeoIP())
	}
	if !usage.asn {
		_ = os.Remove(constant.Path.ASN())
	}
	if !usage.geosite {
		_ = os.Remove(constant.Path.GeoSite())
	}
	if !usage.mmdb {
		_ = os.Remove(constant.Path.MMDB())
	}
}

func filterUnavailableGeoRules(raw *config.RawConfig) []string {
	if raw == nil {
		return nil
	}
	avail := currentGeoAvailability()
	missing := map[string]bool{}
	recordMissing := func(needs geoUsage) bool {
		unavailable := false
		if needs.mmdb && !avail.mmdb {
			missing["MMDB"] = true
			unavailable = true
		}
		if needs.geoip && !avail.geoip {
			missing["GEOIP"] = true
			unavailable = true
		}
		if needs.geosite && !avail.geosite {
			missing["GEOSITE"] = true
			unavailable = true
		}
		if needs.asn && !avail.asn {
			missing["ASN"] = true
			unavailable = true
		}
		return unavailable
	}
	filterRules := func(rules []string) []string {
		if len(rules) == 0 {
			return rules
		}
		filtered := make([]string, 0, len(rules))
		for _, rule := range rules {
			if recordMissing(ruleGeoNeeds(rule, raw.GeodataMode)) {
				continue
			}
			filtered = append(filtered, rule)
		}
		return filtered
	}
	raw.Rule = filterRules(raw.Rule)
	for name, rules := range raw.SubRules {
		raw.SubRules[name] = filterRules(rules)
	}
	if raw.DNS.Enable {
		if len(raw.DNS.Fallback) > 0 && raw.DNS.FallbackFilter.GeoIP && !strings.EqualFold(strings.TrimSpace(raw.DNS.FallbackFilter.GeoIPCode), "LAN") {
			var fbGeo geoUsage
			if raw.GeodataMode {
				fbGeo.geoip = true
			} else {
				fbGeo.mmdb = true
			}
			if recordMissing(fbGeo) {
				raw.DNS.FallbackFilter.GeoIP = false
			}
		}
		if len(raw.DNS.Fallback) > 0 && len(raw.DNS.FallbackFilter.GeoSite) > 0 && !avail.geosite {
			missing["GEOSITE"] = true
			raw.DNS.FallbackFilter.GeoSite = nil
		}
		if !avail.geosite {
			if prunePolicyGeoSite(raw.DNS.NameServerPolicy) {
				missing["GEOSITE"] = true
			}
			if prunePolicyGeoSite(raw.DNS.ProxyServerNameserverPolicy) {
				missing["GEOSITE"] = true
			}
			if len(raw.DNS.FakeIPFilter) > 0 {
				filtered := make([]string, 0, len(raw.DNS.FakeIPFilter))
				for _, item := range raw.DNS.FakeIPFilter {
					if isGeoSitePattern(item) {
						missing["GEOSITE"] = true
						continue
					}
					filtered = append(filtered, item)
				}
				raw.DNS.FakeIPFilter = filtered
			}
		}
	}
	var deferred []string
	for _, name := range []string{"MMDB", "GEOIP", "GEOSITE", "ASN"} {
		if missing[name] {
			deferred = append(deferred, name)
		}
	}
	return deferred
}

func setDeferredGeoResources(types []string) {
	deferredGeoMu.Lock()
	defer deferredGeoMu.Unlock()
	deferredGeoTypes = types
}

func deferredGeoSnapshot() []string {
	deferredGeoMu.Lock()
	defer deferredGeoMu.Unlock()
	return append([]string(nil), deferredGeoTypes...)
}

var isWindowsPlatform = runtime.GOOS == "windows"

func isWindowsHostRuntime() bool {
	return isWindowsPlatform && !isAndroidRuntime
}

func stripSystemDNSServers(servers []string) ([]string, bool) {
	if len(servers) == 0 {
		return servers, false
	}
	kept := make([]string, 0, len(servers))
	removedSystem := false
	for _, entry := range servers {
		trimmed := strings.ToLower(strings.TrimSpace(entry))
		if trimmed == "system" || trimmed == "system://" {
			removedSystem = true
			continue
		}
		kept = append(kept, entry)
	}
	return kept, removedSystem
}

func ensureRawDoTHosts(raw *config.RawConfig) {
	if raw.Hosts == nil {
		raw.Hosts = make(map[string]any)
	}
	for _, entry := range androidDoTHosts {
		if _, exists := raw.Hosts[entry.host]; !exists {
			ips := make([]string, len(entry.ips))
			copy(ips, entry.ips)
			raw.Hosts[entry.host] = ips
		}
	}
}

func enforceWindowsDualStackGuard(raw *config.RawConfig) {
	if !isWindowsHostRuntime() || raw == nil {
		return
	}
	if !raw.IPv6 && len(raw.Tun.RouteAddress) == 0 {
		raw.Tun.StrictRoute = true
	}
	if !raw.Tun.StrictRoute || !raw.DNS.Enable {
		return
	}
	ensureRawDoTHosts(raw)
	raw.DNS.NameServer, _ = stripSystemDNSServers(raw.DNS.NameServer)
	raw.DNS.DefaultNameserver, _ = stripSystemDNSServers(raw.DNS.DefaultNameserver)
	proxyServers, hadSystemProxy := stripSystemDNSServers(raw.DNS.ProxyServerNameserver)
	raw.DNS.ProxyServerNameserver = proxyServers
	directServers, hadSystemDirect := stripSystemDNSServers(raw.DNS.DirectNameServer)
	raw.DNS.DirectNameServer = directServers
	if len(raw.DNS.DefaultNameserver) == 0 {
		raw.DNS.DefaultNameserver = []string{"1.1.1.1", "8.8.8.8", "223.5.5.5"}
	}
	if hadSystemProxy && len(raw.DNS.ProxyServerNameserver) == 0 {
		raw.DNS.ProxyServerNameserver = []string{"1.1.1.1", "8.8.8.8", "223.5.5.5"}
	}
	if hadSystemDirect && len(raw.DNS.DirectNameServer) == 0 {
		raw.DNS.DirectNameServer = []string{"1.1.1.1", "8.8.8.8"}
	}
	if len(raw.DNS.NameServer) == 0 {
		raw.DNS.NameServer = []string{"1.1.1.1", "8.8.8.8", "https://1.1.1.1/dns-query", "https://8.8.8.8/dns-query"}
	}
}

func prepareRawConfigForParse(raw *config.RawConfig) {
	pruneUnusedGeoFiles(raw)
	setDeferredGeoResources(filterUnavailableGeoRules(raw))
	enforceWindowsDualStackGuard(raw)
}

func scheduleDeferredGeoDownloads() {
	if !isRunning.Load() {
		return
	}
	deferredGeoMu.Lock()
	defer deferredGeoMu.Unlock()
	if len(deferredGeoTypes) == 0 {
		return
	}
	if deferredGeoTimer != nil {
		deferredGeoTimer.Stop()
	}
	deferredGeoTimer = time.AfterFunc(deferredGeoDownloadDelay, func() {
		if !isRunning.Load() {
			return
		}
		deferredGeoMu.Lock()
		pending := deferredGeoTypes
		deferredGeoTypes = nil
		deferredGeoMu.Unlock()
		for _, geoType := range pending {
			_ = handleUpdateGeoData(GeoUpdateParams{Type: geoType})
		}
	})
}
