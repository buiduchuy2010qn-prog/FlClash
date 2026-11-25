package com.follow.clash

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoVpnControllerTest {
    @Test
    fun isUsableValidatedWifiRequiresValidatedNonCaptiveNonSuspended() {
        assertTrue(isUsableValidatedWifi(validated = true, captivePortal = false, notSuspended = true))
        assertFalse(isUsableValidatedWifi(validated = false, captivePortal = false, notSuspended = true))
        assertFalse(isUsableValidatedWifi(validated = true, captivePortal = true, notSuspended = true))
        assertFalse(isUsableValidatedWifi(validated = true, captivePortal = false, notSuspended = false))
    }

    @Test
    fun captiveOrUnvalidatedWifiDoesNotStopVpnAndAllowsCellularStart() {
        assertEquals(
            AutoVpnAction.START,
            decideAutoVpnAction(
                onCellular = true,
                offWifi = true,
                hasValidatedWifi = false,
                hasCellular = true,
                isRunRequested = false,
            ),
        )
        assertEquals(
            AutoVpnAction.NONE,
            decideAutoVpnAction(
                onCellular = true,
                offWifi = true,
                hasValidatedWifi = false,
                hasCellular = true,
                isRunRequested = true,
            ),
        )
    }

    @Test
    fun validatedCleanWifiStopsRunningVpn() {
        assertEquals(
            AutoVpnAction.STOP,
            decideAutoVpnAction(
                onCellular = true,
                offWifi = true,
                hasValidatedWifi = true,
                hasCellular = true,
                isRunRequested = true,
            ),
        )
        assertEquals(
            AutoVpnAction.NONE,
            decideAutoVpnAction(
                onCellular = true,
                offWifi = true,
                hasValidatedWifi = true,
                hasCellular = true,
                isRunRequested = false,
            ),
        )
    }
}
