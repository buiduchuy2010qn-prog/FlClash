package com.follow.clash

import android.content.Context
import com.follow.clash.common.GlobalState
import java.io.File

object RootHotspotManager {
    private const val SENTINEL = "FLCLASH_ROOT_GRANTED"
    private const val RULE_PREF = "18000"

    @Volatile
    var isActive: Boolean = false
        private set

    fun enable(context: Context): Boolean {
        if (!hasSuBinary()) {
            isActive = false
            return false
        }
        val script = """
            echo $SENTINEL
            sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
            TUN_IF=${'$'}(ip -o link show up | awk -F': ' '{print ${'$'}2}' | grep -E '^tun[0-9]+' | head -n1)
            if [ -z "${'$'}TUN_IF" ]; then
              echo FLCLASH_NO_TUN
              exit 2
            fi
            TUN_TABLE=${'$'}(ip rule show | grep -E 'oif \b|tun' | awk '/lookup/ {for(i=1;i<=NF;i++) if(${'$'}i=="lookup") print ${'$'}(i+1)}' | head -n1)
            if [ -z "${'$'}TUN_TABLE" ]; then
              TUN_TABLE=${'$'}(ip route show table all | awk -v dev="${'$'}TUN_IF" '${'$'}0 ~ ("dev " dev) {for(i=1;i<=NF;i++) if(${'$'}i=="table") {print ${'$'}(i+1); exit}}')
            fi
            iptables -t nat -N FLCLASH_HOTSPOT_NAT 2>/dev/null || true
            iptables -t nat -F FLCLASH_HOTSPOT_NAT
            iptables -N FLCLASH_HOTSPOT_FWD 2>/dev/null || true
            iptables -F FLCLASH_HOTSPOT_FWD
            iptables -t nat -C POSTROUTING -j FLCLASH_HOTSPOT_NAT 2>/dev/null || iptables -t nat -I POSTROUTING 1 -j FLCLASH_HOTSPOT_NAT
            iptables -C FORWARD -j FLCLASH_HOTSPOT_FWD 2>/dev/null || iptables -I FORWARD 1 -j FLCLASH_HOTSPOT_FWD
            iptables -t nat -A FLCLASH_HOTSPOT_NAT -o "${'$'}TUN_IF" -j MASQUERADE
            while ip rule del pref $RULE_PREF 2>/dev/null; do :; done
            for IFACE in ${'$'}(ip -o addr show up scope global | awk '{print ${'$'}2}' | grep -E '^(ap|swlan|wlan|rndis|ncm|usb)[0-9]*' | sort -u); do
              [ "${'$'}IFACE" = "${'$'}TUN_IF" ] && continue
              iptables -A FLCLASH_HOTSPOT_FWD -i "${'$'}IFACE" -o "${'$'}TUN_IF" -j ACCEPT
              iptables -A FLCLASH_HOTSPOT_FWD -i "${'$'}TUN_IF" -o "${'$'}IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
              if [ -n "${'$'}TUN_TABLE" ]; then
                ip rule add iif "${'$'}IFACE" lookup "${'$'}TUN_TABLE" pref $RULE_PREF 2>/dev/null || true
              fi
            done
            echo FLCLASH_HOTSPOT_OK
        """.trimIndent()
        val ok = runSuScript(script)
        isActive = ok
        return ok
    }

    fun disable(): Boolean {
        if (!hasSuBinary()) {
            isActive = false
            return true
        }
        val script = """
            echo $SENTINEL
            while ip rule del pref $RULE_PREF 2>/dev/null; do :; done
            iptables -t nat -D POSTROUTING -j FLCLASH_HOTSPOT_NAT 2>/dev/null || true
            iptables -t nat -F FLCLASH_HOTSPOT_NAT 2>/dev/null || true
            iptables -t nat -X FLCLASH_HOTSPOT_NAT 2>/dev/null || true
            iptables -D FORWARD -j FLCLASH_HOTSPOT_FWD 2>/dev/null || true
            iptables -F FLCLASH_HOTSPOT_FWD 2>/dev/null || true
            iptables -X FLCLASH_HOTSPOT_FWD 2>/dev/null || true
            echo FLCLASH_HOTSPOT_OK
        """.trimIndent()
        val ok = runSuScript(script)
        isActive = false
        return ok
    }

    fun disableIfActive() {
        if (!isActive) return
        disable()
    }

    private fun hasSuBinary(): Boolean {
        val dirs = System.getenv("PATH").orEmpty().split(':') + listOf("/system/xbin", "/sbin", "/system/bin")
        return dirs.any { it.isNotEmpty() && File(it, "su").exists() }
    }

    private fun runSuScript(script: String): Boolean {
        return runCatching {
            val process = ProcessBuilder("su").redirectErrorStream(true).start()
            process.outputStream.bufferedWriter().use { writer ->
                writer.write(script)
                writer.write("\nexit\n")
            }
            val output = process.inputStream.bufferedReader().readText()
            val code = process.waitFor()
            code == 0 && output.contains(SENTINEL) && output.contains("FLCLASH_HOTSPOT_OK")
        }.getOrElse { error ->
            GlobalState.log("RootHotspotManager su failed: $error")
            false
        }
    }
}
