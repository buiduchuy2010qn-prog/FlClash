package com.follow.clash

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.edit
import com.follow.clash.common.GlobalState
import kotlinx.coroutines.launch

internal enum class AutoVpnAction {
    NONE,
    START,
    STOP,
}

internal fun isUsableValidatedWifi(
    validated: Boolean,
    captivePortal: Boolean,
    notSuspended: Boolean,
): Boolean = validated && !captivePortal && notSuspended

internal fun decideAutoVpnAction(
    onCellular: Boolean,
    offWifi: Boolean,
    hasValidatedWifi: Boolean,
    hasCellular: Boolean,
    isRunRequested: Boolean,
): AutoVpnAction {
    if (offWifi && hasValidatedWifi) {
        return if (isRunRequested) AutoVpnAction.STOP else AutoVpnAction.NONE
    }
    if (onCellular && !hasValidatedWifi && hasCellular) {
        return if (!isRunRequested) AutoVpnAction.START else AutoVpnAction.NONE
    }
    return AutoVpnAction.NONE
}

object AutoVpnController {
    private const val NATIVE_PREFS = "flclash_auto_vpn"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val KEY_ON_CELLULAR = "auto_vpn_on_cellular"
    private const val KEY_OFF_WIFI = "auto_vpn_off_wifi"
    private const val KEY_START_ON_BOOT = "auto_start_on_boot"
    private const val DEBOUNCE_MS = 1_000L
    private const val MANUAL_COOLDOWN_MS = 45_000L

    private val lock = Any()
    private val wifiValidStates = mutableMapOf<Network, Boolean>()
    private val cellularNetworks = mutableSetOf<Network>()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val evaluateRunnable = Runnable { evaluateTransition() }

    @Volatile
    private var appContext: Context? = null

    @Volatile
    private var started = false

    @Volatile
    private var lastManualActionElapsedMs = 0L

    fun start(context: Context) {
        val ctx = context.applicationContext
        appContext = ctx
        synchronized(lock) {
            if (started) return
            started = true
        }
        val cm = ctx.getSystemService(ConnectivityManager::class.java) ?: return
        val wifiRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        val cellularRequest = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        runCatching {
            cm.registerNetworkCallback(wifiRequest, networkCallback(isWifi = true))
            cm.registerNetworkCallback(cellularRequest, networkCallback(isWifi = false))
        }.onFailure { error ->
            GlobalState.log("AutoVpnController register failed: $error")
        }
    }

    fun updateSettings(
        context: Context,
        onCellular: Boolean,
        offWifi: Boolean,
        startOnBoot: Boolean,
    ) {
        context.applicationContext.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE).edit {
            putBoolean(KEY_ON_CELLULAR, onCellular)
            putBoolean(KEY_OFF_WIFI, offWifi)
            putBoolean(KEY_START_ON_BOOT, startOnBoot)
        }
    }

    fun notifyManualAction() {
        lastManualActionElapsedMs = SystemClock.elapsedRealtime()
    }

    fun shouldStartOnBoot(context: Context): Boolean =
        readBool(context.applicationContext, KEY_START_ON_BOOT)

    private fun readBool(context: Context, key: String): Boolean {
        val nativePrefs = context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)
        if (nativePrefs.contains(key)) {
            return nativePrefs.getBoolean(key, false)
        }
        val flutterPrefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        return flutterPrefs.getBoolean("flutter.$key", false)
    }

    private fun isValidatedWifiCapabilities(caps: NetworkCapabilities?): Boolean {
        if (caps == null) return false
        val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        val captivePortal = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)
        val notSuspended = Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED)
        return isUsableValidatedWifi(
            validated = validated,
            captivePortal = captivePortal,
            notSuspended = notSuspended,
        )
    }

    private fun networkCallback(isWifi: Boolean) = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            if (isWifi) {
                val cm = appContext?.getSystemService(ConnectivityManager::class.java)
                val valid = isValidatedWifiCapabilities(cm?.getNetworkCapabilities(network))
                synchronized(lock) {
                    wifiValidStates[network] = valid
                }
            } else {
                synchronized(lock) {
                    cellularNetworks.add(network)
                }
            }
            scheduleEvaluate()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            if (!isWifi) return
            val valid = isValidatedWifiCapabilities(networkCapabilities)
            val changed = synchronized(lock) {
                val previous = wifiValidStates[network]
                wifiValidStates[network] = valid
                previous != valid
            }
            if (changed) {
                scheduleEvaluate()
            }
        }

        override fun onLost(network: Network) {
            synchronized(lock) {
                if (isWifi) {
                    wifiValidStates.remove(network)
                } else {
                    cellularNetworks.remove(network)
                }
            }
            scheduleEvaluate()
        }
    }

    private fun scheduleEvaluate() {
        mainHandler.removeCallbacks(evaluateRunnable)
        mainHandler.postDelayed(evaluateRunnable, DEBOUNCE_MS)
    }

    private fun evaluateTransition() {
        val ctx = appContext ?: return
        val onCellular = readBool(ctx, KEY_ON_CELLULAR)
        val offWifi = readBool(ctx, KEY_OFF_WIFI)
        if (!onCellular && !offWifi) return

        val lastManual = lastManualActionElapsedMs
        if (lastManual > 0L && SystemClock.elapsedRealtime() - lastManual < MANUAL_COOLDOWN_MS) {
            return
        }

        val hasValidatedWifi: Boolean
        val hasCellular: Boolean
        synchronized(lock) {
            hasValidatedWifi = wifiValidStates.values.any { it }
            hasCellular = cellularNetworks.isNotEmpty()
        }

        when (
            decideAutoVpnAction(
                onCellular = onCellular,
                offWifi = offWifi,
                hasValidatedWifi = hasValidatedWifi,
                hasCellular = hasCellular,
                isRunRequested = ServiceState.isRunRequested,
            )
        ) {
            AutoVpnAction.START -> {
                if (VpnService.prepare(ctx) == null) {
                    GlobalState.launch {
                        ServiceState.handleStartAction()
                    }
                }
            }
            AutoVpnAction.STOP -> {
                GlobalState.launch {
                    ServiceState.handleStopAction()
                }
            }
            AutoVpnAction.NONE -> Unit
        }
    }
}
