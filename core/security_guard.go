package core

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"net"
	"runtime"
	"strings"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/log"
)

func sanitizeControllerAddress(addr string, forceLoopback bool) string {
	trimmed := strings.TrimSpace(addr)
	if trimmed == "" {
		return ""
	}
	host, port, err := net.SplitHostPort(trimmed)
	if err != nil || port == "" {
		return trimmed
	}
	if !forceLoopback {
		return trimmed
	}
	if strings.EqualFold(host, "localhost") {
		return trimmed
	}
	ip := net.ParseIP(host)
	if ip != nil && ip.IsLoopback() {
		return trimmed
	}
	return net.JoinHostPort("127.0.0.1", port)
}

func generateControllerSecret() string {
	var buf [16]byte
	if _, err := rand.Read(buf[:]); err == nil {
		return hex.EncodeToString(buf[:])
	}
	return fmt.Sprintf("%032x", time.Now().UnixNano())
}

func ensureControllerSecret(secret string, hasController bool) string {
	if !hasController {
		return secret
	}
	if strings.TrimSpace(secret) != "" {
		return secret
	}
	return generateControllerSecret()
}

func sanitizeControllerOrigins(origins []string, allowPrivate bool, hasController bool) ([]string, bool) {
	if !hasController || len(origins) == 0 {
		return origins, allowPrivate
	}
	filtered := make([]string, 0, len(origins))
	hadWildcard := false
	for _, origin := range origins {
		if strings.TrimSpace(origin) == "*" {
			hadWildcard = true
			continue
		}
		filtered = append(filtered, origin)
	}
	if hadWildcard {
		allowPrivate = false
	}
	return filtered, allowPrivate
}

// sanitizeConfigSecurity hardens untrusted subscription controller settings
// before applying them to the running Core.
func sanitizeConfigSecurity(cfg *config.Config) *config.Config {
	if cfg == nil || cfg.Controller == nil {
		return cfg
	}
	controller := cfg.Controller
	forceLoopback := runtime.GOOS == "android" || (cfg.General != nil && !cfg.General.AllowLan)

	origAddr := controller.ExternalController
	origTLS := controller.ExternalControllerTLS
	controller.ExternalController = sanitizeControllerAddress(origAddr, forceLoopback)
	controller.ExternalControllerTLS = sanitizeControllerAddress(origTLS, forceLoopback)
	if controller.ExternalController != origAddr || controller.ExternalControllerTLS != origTLS {
		log.Warnln("security guard: restricted external-controller binding to loopback")
	}

	hasController := controller.ExternalController != "" ||
		controller.ExternalControllerTLS != "" ||
		controller.ExternalControllerUnix != "" ||
		controller.ExternalControllerPipe != ""

	origSecret := controller.Secret
	controller.Secret = ensureControllerSecret(origSecret, hasController)
	if controller.Secret != origSecret {
		log.Warnln("security guard: generated random secret for active external-controller")
	}

	origOriginsLen := len(controller.Cors.AllowOrigins)
	controller.Cors.AllowOrigins, controller.Cors.AllowPrivateNetwork = sanitizeControllerOrigins(
		controller.Cors.AllowOrigins,
		controller.Cors.AllowPrivateNetwork,
		hasController,
	)
	if len(controller.Cors.AllowOrigins) != origOriginsLen {
		log.Warnln("security guard: stripped wildcard CORS origin from external-controller")
	}
	return cfg
}
