package tun

import (
	"net"
	"testing"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
)

type fakeProviderTunnel struct {
	udpCalls int
	lastPort uint16
	callback *utils.Callback[P.RuleProvider]
}

func (f *fakeProviderTunnel) HandleTCPConn(net.Conn, *constant.Metadata) {}

func (f *fakeProviderTunnel) HandleUDPPacket(_ constant.UDPPacket, metadata *constant.Metadata) {
	f.udpCalls++
	if metadata != nil {
		f.lastPort = metadata.DstPort
	}
}

func (f *fakeProviderTunnel) NatTable() constant.NatTable { return nil }

func (f *fakeProviderTunnel) Providers() map[string]P.ProxyProvider { return nil }

func (f *fakeProviderTunnel) RuleProviders() map[string]P.RuleProvider { return nil }

func (f *fakeProviderTunnel) RuleUpdateCallback() *utils.Callback[P.RuleProvider] {
	return f.callback
}

type fakeUDPPacket struct {
	dropped bool
}

func (p *fakeUDPPacket) Data() []byte { return nil }

func (p *fakeUDPPacket) WriteBack([]byte, net.Addr) (int, error) { return 0, nil }

func (p *fakeUDPPacket) Drop() { p.dropped = true }

func (p *fakeUDPPacket) LocalAddr() net.Addr { return nil }

func TestQuicBlockingTunnelDropsUDP443WhenEnabled(t *testing.T) {
	inner := &fakeProviderTunnel{callback: utils.NewCallback[P.RuleProvider]()}
	wrapped := newQuicBlockingTunnel(inner, true)

	if _, ok := wrapped.(P.Tunnel); !ok {
		t.Fatal("wrapped tunnel must implement constant/provider.Tunnel for sing_tun")
	}

	quicPkt := &fakeUDPPacket{}
	wrapped.HandleUDPPacket(quicPkt, &constant.Metadata{DstPort: 443})
	if !quicPkt.dropped {
		t.Fatal("expected UDP/443 QUIC packet to be dropped")
	}
	if inner.udpCalls != 0 {
		t.Fatalf("expected inner HandleUDPPacket not to be called for UDP/443, got %d", inner.udpCalls)
	}

	for _, port := range []uint16{53, 123, 3478, 5228, 19302} {
		pkt := &fakeUDPPacket{}
		wrapped.HandleUDPPacket(pkt, &constant.Metadata{DstPort: port})
		if pkt.dropped {
			t.Fatalf("expected non-QUIC UDP/%d packet not to be dropped", port)
		}
		if inner.lastPort != port {
			t.Fatalf("expected inner HandleUDPPacket to receive port %d, got %d", port, inner.lastPort)
		}
	}
	if inner.udpCalls != 5 {
		t.Fatalf("expected 5 forwarded non-443 packets, got %d", inner.udpCalls)
	}
}

func TestQuicBlockingTunnelForwardsUDP443WhenAllowed(t *testing.T) {
	inner := &fakeProviderTunnel{callback: utils.NewCallback[P.RuleProvider]()}
	wrapped := newQuicBlockingTunnel(inner, false)

	pkt := &fakeUDPPacket{}
	wrapped.HandleUDPPacket(pkt, &constant.Metadata{DstPort: 443})
	if pkt.dropped {
		t.Fatal("expected UDP/443 packet not to be dropped when allow-quic is true")
	}
	if inner.udpCalls != 1 || inner.lastPort != 443 {
		t.Fatalf("expected UDP/443 packet to be forwarded once, got calls=%d port=%d", inner.udpCalls, inner.lastPort)
	}
}
