package com.follow.clash.widget

import android.content.Context
import androidx.core.content.edit
import kotlin.math.ceil
import kotlin.math.max

data class VpnWidgetSnapshot(
    val profileName: String = "",
    val activeNode: String = "",
    val activeDelayMs: Int? = null,
    val onlineDevices: Int? = null,
    val deviceLimit: Int? = null,
    val expireEpochSec: Long? = null,
    val securityLevel: String = "safe",
    val securityScore: Int = 100,
    val speedBoost: Boolean = false,
    val expiryAlertsEnabled: Boolean = true,
)

enum class ExpiryUrgency {
    NONE,
    DAYS,
    HOURS,
    EXPIRED,
}

data class ExpiryAlertDecision(
    val urgency: ExpiryUrgency,
    val value: Int,
    val bucketKey: String,
)

internal fun evaluateExpiryStatus(
    expireEpochSec: Long?,
    nowMillis: Long,
): Pair<ExpiryUrgency, Int> {
    if (expireEpochSec == null || expireEpochSec <= 0L) {
        return ExpiryUrgency.NONE to 0
    }
    val diffMs = expireEpochSec * 1000L - nowMillis
    if (diffMs <= 0L) {
        return ExpiryUrgency.EXPIRED to 0
    }
    val hoursLeft = diffMs / 3_600_000L
    if (hoursLeft < 24L) {
        return ExpiryUrgency.HOURS to max(1, hoursLeft.toInt())
    }
    val daysLeft = ceil(diffMs.toDouble() / 86_400_000.0).toInt().coerceAtLeast(1)
    return ExpiryUrgency.DAYS to daysLeft
}

internal fun evaluateNativeExpiryAlert(
    snapshot: VpnWidgetSnapshot,
    lastBucket: String?,
    lastAlertMs: Long,
    nowMillis: Long,
    thresholdDays: Int = 3,
    cooldownMs: Long = 12L * 3_600_000L,
): ExpiryAlertDecision? {
    if (!snapshot.expiryAlertsEnabled) return null
    val (urgency, value) = evaluateExpiryStatus(snapshot.expireEpochSec, nowMillis)
    val shouldWarn = when (urgency) {
        ExpiryUrgency.EXPIRED, ExpiryUrgency.HOURS -> true
        ExpiryUrgency.DAYS -> value <= thresholdDays
        ExpiryUrgency.NONE -> false
    }
    if (!shouldWarn) return null
    val bucket = "${urgency.name}:$value"
    val escalated = urgency == ExpiryUrgency.EXPIRED && lastBucket?.startsWith("EXPIRED") != true ||
        urgency == ExpiryUrgency.HOURS && lastBucket?.startsWith("DAYS") == true
    val elapsed = nowMillis - lastAlertMs
    if (lastAlertMs > 0L && !escalated && elapsed < cooldownMs && lastBucket == bucket) {
        return null
    }
    return ExpiryAlertDecision(urgency = urgency, value = value, bucketKey = bucket)
}

object VpnWidgetStore {
    private const val PREFS_NAME = "flclash_home_widget"
    private const val KEY_PROFILE_NAME = "profile_name"
    private const val KEY_ACTIVE_NODE = "active_node"
    private const val KEY_ACTIVE_DELAY = "active_delay"
    private const val KEY_ONLINE_DEVICES = "online_devices"
    private const val KEY_DEVICE_LIMIT = "device_limit"
    private const val KEY_EXPIRE_EPOCH = "expire_epoch"
    private const val KEY_SECURITY_LEVEL = "security_level"
    private const val KEY_SECURITY_SCORE = "security_score"
    private const val KEY_SPEED_BOOST = "speed_boost"
    private const val KEY_EXPIRY_ALERTS = "expiry_alerts"
    private const val KEY_LAST_ALERT_BUCKET = "last_alert_bucket"
    private const val KEY_LAST_ALERT_MS = "last_alert_ms"

    fun load(context: Context): VpnWidgetSnapshot {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val delay = prefs.getInt(KEY_ACTIVE_DELAY, -1).takeIf { it > 0 }
        val online = prefs.getInt(KEY_ONLINE_DEVICES, -1).takeIf { it >= 0 }
        val limit = prefs.getInt(KEY_DEVICE_LIMIT, -1).takeIf { it > 0 }
        val expire = prefs.getLong(KEY_EXPIRE_EPOCH, 0L).takeIf { it > 0L }
        return VpnWidgetSnapshot(
            profileName = prefs.getString(KEY_PROFILE_NAME, "").orEmpty(),
            activeNode = prefs.getString(KEY_ACTIVE_NODE, "").orEmpty(),
            activeDelayMs = delay,
            onlineDevices = online,
            deviceLimit = limit,
            expireEpochSec = expire,
            securityLevel = prefs.getString(KEY_SECURITY_LEVEL, "safe").orEmpty(),
            securityScore = prefs.getInt(KEY_SECURITY_SCORE, 100),
            speedBoost = prefs.getBoolean(KEY_SPEED_BOOST, false),
            expiryAlertsEnabled = prefs.getBoolean(KEY_EXPIRY_ALERTS, true),
        )
    }

    fun save(context: Context, snapshot: VpnWidgetSnapshot) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit {
            putString(KEY_PROFILE_NAME, snapshot.profileName)
            putString(KEY_ACTIVE_NODE, snapshot.activeNode)
            putInt(KEY_ACTIVE_DELAY, snapshot.activeDelayMs ?: -1)
            putInt(KEY_ONLINE_DEVICES, snapshot.onlineDevices ?: -1)
            putInt(KEY_DEVICE_LIMIT, snapshot.deviceLimit ?: -1)
            putLong(KEY_EXPIRE_EPOCH, snapshot.expireEpochSec ?: 0L)
            putString(KEY_SECURITY_LEVEL, snapshot.securityLevel)
            putInt(KEY_SECURITY_SCORE, snapshot.securityScore)
            putBoolean(KEY_SPEED_BOOST, snapshot.speedBoost)
            putBoolean(KEY_EXPIRY_ALERTS, snapshot.expiryAlertsEnabled)
        }
    }

    fun pendingExpiryAlert(context: Context, nowMillis: Long = System.currentTimeMillis()): ExpiryAlertDecision? {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val snapshot = load(context)
        val lastBucket = prefs.getString(KEY_LAST_ALERT_BUCKET, null)
        val lastAlertMs = prefs.getLong(KEY_LAST_ALERT_MS, 0L)
        return evaluateNativeExpiryAlert(
            snapshot = snapshot,
            lastBucket = lastBucket,
            lastAlertMs = lastAlertMs,
            nowMillis = nowMillis,
        )
    }

    fun markExpiryAlertDispatched(
        context: Context,
        bucketKey: String,
        nowMillis: Long = System.currentTimeMillis(),
    ) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit {
            putString(KEY_LAST_ALERT_BUCKET, bucketKey)
            putLong(KEY_LAST_ALERT_MS, nowMillis)
        }
    }
}
