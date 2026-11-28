package com.follow.clash.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.follow.clash.R
import com.follow.clash.RunState
import com.follow.clash.ServiceState
import com.follow.clash.common.Components
import com.follow.clash.common.LiveTelemetry
import com.follow.clash.common.QuickAction
import com.follow.clash.common.R as CommonR
import com.follow.clash.common.intent
import com.follow.clash.common.quickIntent

class VpnWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        updateWidgets(context, appWidgetManager, appWidgetIds)
    }

    companion object {
        fun componentName(context: Context): ComponentName =
            ComponentName(context, VpnWidgetProvider::class.java)

        fun hasWidgets(context: Context): Boolean {
            val manager = AppWidgetManager.getInstance(context) ?: return false
            return manager.getAppWidgetIds(componentName(context)).isNotEmpty()
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context) ?: return
            val ids = manager.getAppWidgetIds(componentName(context))
            if (ids.isEmpty()) return
            updateWidgets(context, manager, ids)
        }

        private fun updateWidgets(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val runState = ServiceState.runState.value
            val snapshot = VpnWidgetStore.load(context)
            val liveSpeed = LiveTelemetry.speedText.value
            val nowMs = System.currentTimeMillis()

            for (appWidgetId in appWidgetIds) {
                val views = buildRemoteViews(
                    context = context,
                    runState = runState,
                    snapshot = snapshot,
                    liveSpeed = liveSpeed,
                    nowMs = nowMs,
                )
                appWidgetManager.updateAppWidget(appWidgetId, views)
            }
        }

        private fun buildRemoteViews(
            context: Context,
            runState: RunState,
            snapshot: VpnWidgetSnapshot,
            liveSpeed: String,
            nowMs: Long,
        ): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.widget_vpn_control)

            val launchIntent = Components.mainActivity.intent.apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val openAppPi = PendingIntent.getActivity(
                context,
                100,
                launchIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppPi)

            val togglePi = PendingIntent.getActivity(
                context,
                101,
                QuickAction.TOGGLE.quickIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_power_btn, togglePi)

            val fastestIntent = Intent("${context.packageName}.action.SWITCH_FASTEST")
                .setPackage(context.packageName)
            val fastestPi = PendingIntent.getBroadcast(
                context,
                102,
                fastestIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            views.setOnClickPendingIntent(R.id.widget_fastest_btn, fastestPi)

            when (runState) {
                RunState.STARTED -> {
                    views.setImageViewResource(R.id.widget_status_dot, R.drawable.widget_dot_connected)
                    views.setTextViewText(
                        R.id.widget_status_text,
                        context.getString(CommonR.string.widget_status_connected),
                    )
                    views.setTextColor(
                        R.id.widget_status_text,
                        ContextCompat.getColor(context, R.color.widget_connected),
                    )
                    views.setInt(R.id.widget_power_btn, "setBackgroundResource", R.drawable.widget_btn_on)
                    views.setViewVisibility(R.id.widget_fastest_btn, View.VISIBLE)
                }

                RunState.STARTING, RunState.STOPPING -> {
                    views.setImageViewResource(R.id.widget_status_dot, R.drawable.widget_dot_connecting)
                    views.setTextViewText(
                        R.id.widget_status_text,
                        context.getString(CommonR.string.widget_status_connecting),
                    )
                    views.setTextColor(
                        R.id.widget_status_text,
                        ContextCompat.getColor(context, R.color.widget_caution),
                    )
                    views.setInt(R.id.widget_power_btn, "setBackgroundResource", R.drawable.widget_btn_on)
                    views.setViewVisibility(R.id.widget_fastest_btn, View.GONE)
                }

                RunState.STOPPED -> {
                    views.setImageViewResource(R.id.widget_status_dot, R.drawable.widget_dot_stopped)
                    views.setTextViewText(
                        R.id.widget_status_text,
                        context.getString(CommonR.string.widget_status_stopped),
                    )
                    views.setTextColor(
                        R.id.widget_status_text,
                        ContextCompat.getColor(context, R.color.widget_text_secondary),
                    )
                    views.setInt(R.id.widget_power_btn, "setBackgroundResource", R.drawable.widget_btn_off)
                    views.setViewVisibility(R.id.widget_fastest_btn, View.GONE)
                }
            }

            when (snapshot.securityLevel) {
                "danger" -> {
                    views.setInt(R.id.widget_shield_badge, "setBackgroundResource", R.drawable.widget_badge_danger)
                    views.setTextViewText(
                        R.id.widget_shield_badge,
                        context.getString(CommonR.string.widget_shield_danger),
                    )
                    views.setTextColor(
                        R.id.widget_shield_badge,
                        ContextCompat.getColor(context, R.color.widget_danger),
                    )
                }

                "caution" -> {
                    views.setInt(R.id.widget_shield_badge, "setBackgroundResource", R.drawable.widget_badge_caution)
                    views.setTextViewText(
                        R.id.widget_shield_badge,
                        context.getString(CommonR.string.widget_shield_caution),
                    )
                    views.setTextColor(
                        R.id.widget_shield_badge,
                        ContextCompat.getColor(context, R.color.widget_caution),
                    )
                }

                else -> {
                    views.setInt(R.id.widget_shield_badge, "setBackgroundResource", R.drawable.widget_badge_safe)
                    views.setTextViewText(
                        R.id.widget_shield_badge,
                        context.getString(CommonR.string.widget_shield_safe),
                    )
                    views.setTextColor(
                        R.id.widget_shield_badge,
                        ContextCompat.getColor(context, R.color.widget_connected),
                    )
                }
            }

            views.setViewVisibility(
                R.id.widget_speed_badge,
                if (snapshot.speedBoost) View.VISIBLE else View.GONE,
            )

            val profileLabel = snapshot.profileName.ifBlank {
                context.getString(CommonR.string.widget_no_profile)
            }
            views.setTextViewText(R.id.widget_profile_name, profileLabel)

            val nodeLabel = when {
                snapshot.activeNode.isBlank() -> context.getString(CommonR.string.widget_no_node)
                snapshot.activeDelayMs != null && snapshot.activeDelayMs > 0 ->
                    context.getString(
                        CommonR.string.widget_node_with_ping,
                        snapshot.activeNode,
                        snapshot.activeDelayMs,
                    )
                else -> snapshot.activeNode
            }
            views.setTextViewText(R.id.widget_node_info, nodeLabel)

            val speedLabel = if (runState == RunState.STARTED && liveSpeed.isNotBlank()) {
                liveSpeed
            } else {
                context.getString(CommonR.string.widget_speed_idle)
            }
            views.setTextViewText(R.id.widget_speed_text, speedLabel)

            val devicesLabel = when {
                snapshot.onlineDevices != null && snapshot.deviceLimit != null ->
                    context.getString(
                        CommonR.string.widget_devices_ratio,
                        snapshot.onlineDevices,
                        snapshot.deviceLimit,
                    )
                snapshot.deviceLimit != null ->
                    context.getString(CommonR.string.widget_devices_limit, snapshot.deviceLimit)
                else -> context.getString(CommonR.string.widget_devices_empty)
            }
            val devicesColor = when {
                snapshot.onlineDevices != null &&
                    snapshot.deviceLimit != null &&
                    snapshot.deviceLimit > 0 &&
                    snapshot.onlineDevices > snapshot.deviceLimit ->
                    ContextCompat.getColor(context, R.color.widget_danger)
                snapshot.onlineDevices != null &&
                    snapshot.deviceLimit != null &&
                    snapshot.deviceLimit > 0 &&
                    snapshot.onlineDevices >= snapshot.deviceLimit ->
                    ContextCompat.getColor(context, R.color.widget_caution)
                snapshot.onlineDevices != null ->
                    ContextCompat.getColor(context, R.color.widget_connected)
                else -> ContextCompat.getColor(context, R.color.widget_text_secondary)
            }
            views.setTextViewText(R.id.widget_devices_text, devicesLabel)
            views.setTextColor(R.id.widget_devices_text, devicesColor)

            val (urgency, value) = evaluateExpiryStatus(snapshot.expireEpochSec, nowMs)
            val expiryLabel = when (urgency) {
                ExpiryUrgency.EXPIRED -> context.getString(CommonR.string.widget_expiry_expired)
                ExpiryUrgency.HOURS -> context.getString(CommonR.string.widget_expiry_hours, value)
                ExpiryUrgency.DAYS -> context.getString(CommonR.string.widget_expiry_days, value)
                ExpiryUrgency.NONE -> context.getString(CommonR.string.widget_expiry_empty)
            }
            val expiryColor = when {
                urgency == ExpiryUrgency.EXPIRED || urgency == ExpiryUrgency.HOURS ->
                    ContextCompat.getColor(context, R.color.widget_danger)
                urgency == ExpiryUrgency.DAYS && value <= 5 ->
                    ContextCompat.getColor(context, R.color.widget_caution)
                urgency == ExpiryUrgency.DAYS ->
                    ContextCompat.getColor(context, R.color.widget_connected)
                else -> ContextCompat.getColor(context, R.color.widget_text_secondary)
            }
            views.setTextViewText(R.id.widget_expiry_text, expiryLabel)
            views.setTextColor(R.id.widget_expiry_text, expiryColor)

            return views
        }
    }
}
