package core

import (
	"testing"

	"github.com/metacubex/mihomo/config"
)

func TestSanitizeControllerAddress(t *testing.T) {
	if got := sanitizeControllerAddress("", true); got != "" {
		t.Fatalf("empty address mismatch: got %q", got)
	}
	for _, raw := range []string{"0.0.0.0:9090", ":9090", "[::]:9090", "192.168.1.10:9090"} {
		if got := sanitizeControllerAddress(raw, true); got != "127.0.0.1:9090" {
			t.Fatalf("expected loopback bind for %q, got %q", raw, got)
		}
	}
	for _, safe := range []string{"127.0.0.1:9090", "[::1]:9090", "localhost:9090"} {
		if got := sanitizeControllerAddress(safe, true); got != safe {
			t.Fatalf("expected loopback %q preserved, got %q", safe, got)
		}
	}
	if got := sanitizeControllerAddress("0.0.0.0:9090", false); got != "0.0.0.0:9090" {
		t.Fatalf("expected explicit allow-lan bind kept when forceLoopback=false, got %q", got)
	}
}

func TestSanitizeControllerSecretAndCors(t *testing.T) {
	cfg := &config.Config{
		General: &config.General{AllowLan: false},
		Controller: &config.Controller{
			ExternalController: "0.0.0.0:9090",
			Secret:             "",
			Cors: config.Cors{
				AllowOrigins:        []string{"*", "http://localhost:8080"},
				AllowPrivateNetwork: true,
			},
		},
	}
	sanitizeConfigSecurity(cfg)
	if cfg.Controller.ExternalController != "127.0.0.1:9090" {
		t.Fatalf("unexpected controller addr: %q", cfg.Controller.ExternalController)
	}
	if len(cfg.Controller.Secret) != 32 {
		t.Fatalf("expected 32-char generated secret, got %q", cfg.Controller.Secret)
	}
	if len(cfg.Controller.Cors.AllowOrigins) != 1 || cfg.Controller.Cors.AllowOrigins[0] != "http://localhost:8080" {
		t.Fatalf("expected wildcard stripped, got %#v", cfg.Controller.Cors.AllowOrigins)
	}
	if cfg.Controller.Cors.AllowPrivateNetwork {
		t.Fatal("expected AllowPrivateNetwork reset when wildcard origin was stripped")
	}

	disabled := &config.Config{
		General:    &config.General{AllowLan: false},
		Controller: &config.Controller{Secret: ""},
	}
	sanitizeConfigSecurity(disabled)
	if disabled.Controller.Secret != "" {
		t.Fatalf("expected empty secret when controller disabled, got %q", disabled.Controller.Secret)
	}
}
