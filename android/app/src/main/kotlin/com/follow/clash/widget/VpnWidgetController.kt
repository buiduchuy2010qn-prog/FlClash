package com.follow.clash.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.os.Build
import com.follow.clash.RunState
import com.follow.clash.ServiceState
import com.follow.clash.common.GlobalState
import com.follow.clash.common.LiveTelemetry
import com.follow.clash.common.R as CommonR
import com.follow.clash.common.postAlertNotification
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

object VpnWidgetController {
    private val lock = Any()

    @Volatile
    private var started = false

    fun start(context: Context) {
        val ctx = context.applicationContext
        synchronized(lock) {
            if (started) return
            started = true
        }
        GlobalState.launch {
            ServiceState.runState.collectLatest { state ->
                if (VpnWidgetProvider.hasWidgets(ctx)) {
                    VpnWidgetProvider.updateAll(ctx)
                }
                if (state == RunState.STARTED) {
                    maybeDispatchExpiryAlert(ctx)
                }
            }
        }
        GlobalState.launch {
            LiveTelemetry.speedText.collectLatest {
                if (VpnWidgetProvider.hasWidgets(ctx)) {
                    VpnWidgetProvider.updateAll(ctx)
                }
            }
        }
    }

    fun updateSnapshot(context: Context, snapshot: VpnWidgetSnapshot) {
        val ctx = context.applicationContext
        VpnWidgetStore.save(ctx, snapshot)
        if (VpnWidgetProvider.hasWidgets(ctx)) {
            VpnWidgetProvider.updateAll(ctx)
        }
        maybeDispatchExpiryAlert(ctx)
    }

    fun canPinWidget(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(context) ?: return false
        return manager.isRequestPinAppWidgetSupported
    }

    fun pinWidget(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(context) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        return manager.requestPinAppWidget(
            VpnWidgetProvider.componentName(context),
            null,
            null,
        )
    }

    private fun maybeDispatchExpiryAlert(context: Context) {
        val decision = VpnWidgetStore.pendingExpiryAlert(context) ?: return
        val snapshot = VpnWidgetStore.load(context)
        val profileTitle = snapshot.profileName.ifBlank {
            context.getString(CommonR.string.app_name)
        }
        val title = context.getString(CommonR.string.widget_expiry_alert_title, profileTitle)
        val body = when (decision.urgency) {
            ExpiryUrgency.EXPIRED ->
                context.getString(CommonR.string.widget_expiry_alert_expired_body)
            ExpiryUrgency.HOURS ->
                context.getString(CommonR.string.widget_expiry_alert_hours_body, decision.value)
            ExpiryUrgency.DAYS ->
                context.getString(CommonR.string.widget_expiry_alert_days_body, decision.value)
            ExpiryUrgency.NONE -> return
        }
        if (context.postAlertNotification(NOTIFICATION_ID_EXPIRY, title, body)) {
            VpnWidgetStore.markExpiryAlertDispatched(context, decision.bucketKey)
        }
    }

    private const val NOTIFICATION_ID_EXPIRY = 2101
}
