package com.follow.clash.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class VpnWidgetStoreTest {
    private val nowMs = 1_800_000_000_000L

    @Test
    fun evaluateExpiryStatusHandlesDaysHoursExpiredAndNone() {
        assertEquals(ExpiryUrgency.NONE to 0, evaluateExpiryStatus(null, nowMs))
        assertEquals(ExpiryUrgency.NONE to 0, evaluateExpiryStatus(0L, nowMs))

        val expiredEpoch = (nowMs - 60_000L) / 1000L
        assertEquals(ExpiryUrgency.EXPIRED to 0, evaluateExpiryStatus(expiredEpoch, nowMs))

        val hoursEpoch = (nowMs + 10L * 3_600_000L) / 1000L
        assertEquals(ExpiryUrgency.HOURS to 10, evaluateExpiryStatus(hoursEpoch, nowMs))

        val daysEpoch = (nowMs + 50L * 3_600_000L) / 1000L
        assertEquals(ExpiryUrgency.DAYS to 3, evaluateExpiryStatus(daysEpoch, nowMs))
    }

    @Test
    fun evaluateNativeExpiryAlertRespectsCooldownAndEscalates() {
        val snapshot = VpnWidgetSnapshot(
            profileName = "Main",
            expireEpochSec = (nowMs + 40L * 3_600_000L) / 1000L,
            expiryAlertsEnabled = true,
        )
        val first = evaluateNativeExpiryAlert(snapshot, null, 0L, nowMs)
        assertNotNull(first)
        assertEquals(ExpiryUrgency.DAYS, first!!.urgency)
        assertEquals(2, first.value)

        val suppressed = evaluateNativeExpiryAlert(
            snapshot,
            first.bucketKey,
            nowMs,
            nowMs + 3_600_000L,
        )
        assertNull(suppressed)

        val escalatedHours = evaluateNativeExpiryAlert(
            snapshot.copy(expireEpochSec = (nowMs + 8L * 3_600_000L) / 1000L),
            first.bucketKey,
            nowMs,
            nowMs + 3_600_000L,
        )
        assertNotNull(escalatedHours)
        assertEquals(ExpiryUrgency.HOURS, escalatedHours!!.urgency)

        val disabled = evaluateNativeExpiryAlert(
            snapshot.copy(expiryAlertsEnabled = false),
            null,
            0L,
            nowMs,
        )
        assertNull(disabled)
    }
}
