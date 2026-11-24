package tun

import (
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
)

type quicBlockingTunnel struct {
	constant.Tunnel
	providerTunnel P.Tunnel
	blockQuic      bool
}

var (
	_ constant.Tunnel = (*quicBlockingTunnel)(nil)
	_ P.Tunnel        = (*quicBlockingTunnel)(nil)
)

func newQuicBlockingTunnel(base constant.Tunnel, blockQuic bool) constant.Tunnel {
	pt, ok := base.(P.Tunnel)
	if !ok {
		return base
	}
	return &quicBlockingTunnel{
		Tunnel:         base,
		providerTunnel: pt,
		blockQuic:      blockQuic,
	}
}

func (t *quicBlockingTunnel) HandleUDPPacket(packet constant.UDPPacket, metadata *constant.Metadata) {
	if t.blockQuic && metadata != nil && metadata.DstPort == 443 {
		packet.Drop()
		return
	}
	t.Tunnel.HandleUDPPacket(packet, metadata)
}

func (t *quicBlockingTunnel) Providers() map[string]P.ProxyProvider {
	return t.providerTunnel.Providers()
}

func (t *quicBlockingTunnel) RuleProviders() map[string]P.RuleProvider {
	return t.providerTunnel.RuleProviders()
}

func (t *quicBlockingTunnel) RuleUpdateCallback() *utils.Callback[P.RuleProvider] {
	return t.providerTunnel.RuleUpdateCallback()
}
