package com.follow.clash

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val ctx = context?.applicationContext ?: return
        val action = intent?.action ?: return
        if (action !in SUPPORTED_ACTIONS) return
        if (!AutoVpnController.shouldStartOnBoot(ctx)) return
        if (VpnService.prepare(ctx) != null) return

        val pendingResult = goAsync()
        GlobalState.launch {
            try {
                delay(3_000L)
                if (AutoVpnController.shouldStartOnBoot(ctx) &&
                    VpnService.prepare(ctx) == null &&
                    !ServiceState.isRunRequested
                ) {
                    ServiceState.handleStartAction()
                }
            } catch (error: Exception) {
                GlobalState.log("BootReceiver failed: $error")
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        val SUPPORTED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
