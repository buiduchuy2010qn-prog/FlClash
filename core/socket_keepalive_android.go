//go:build android

package core

import (
	"strings"
	"syscall"
)

const (
	androidTCPKeepAliveIdleSec     = 45
	androidTCPKeepAliveIntervalSec = 15
	androidTCPKeepAliveCount       = 3
	androidTCPUserTimeoutOption    = 0x12 // Linux TCP_USER_TIMEOUT
	androidTCPUserTimeoutMs        = 30_000
)

func applyAndroidTCPKeepAlive(network string, conn syscall.RawConn) {
	if conn == nil || !strings.HasPrefix(network, "tcp") {
		return
	}
	_ = conn.Control(func(fd uintptr) {
		_ = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_KEEPALIVE, 1)
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPIDLE, androidTCPKeepAliveIdleSec)
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPINTVL, androidTCPKeepAliveIntervalSec)
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, syscall.TCP_KEEPCNT, androidTCPKeepAliveCount)
		_ = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_TCP, androidTCPUserTimeoutOption, androidTCPUserTimeoutMs)
	})
}
