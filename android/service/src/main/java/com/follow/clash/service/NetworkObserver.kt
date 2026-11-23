package com.follow.clash.service

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkCapabilities.TRANSPORT_SATELLITE
import android.net.NetworkCapabilities.TRANSPORT_USB
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import androidx.core.content.getSystemService
import com.follow.clash.common.GlobalState
import com.follow.clash.core.Core
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.util.concurrent.ConcurrentHashMap

private data class NetworkInfo(
    @Volatile var losingUntilMillis: Long = 0,
    @Volatile var validated: Boolean = false,
    @Volatile var notSuspended: Boolean = true,
    @Volatile var blocked: Boolean = false,
    @Volatile var dnsList: List<InetAddress> = emptyList(),
) {
    val priorityPenalty: Int
        get() {
            var penalty = 0
            if (!validated) penalty += 50
            if (!notSuspended || blocked) penalty += 30
            if (losingUntilMillis > System.currentTimeMillis()) penalty += 25
            return penalty
        }
}

// Outlives every service run: the Core also tests delays and updates providers
// while stopped, and a `system` nameserver has no upstream until DNS arrives here.
object NetworkObserver {

    private val networkInfos = ConcurrentHashMap<Network, NetworkInfo>()
    private val connectivity by lazy {
        GlobalState.application.getSystemService<ConnectivityManager>()
    }
    private val handler by lazy {
        Handler(HandlerThread("NetworkObserve").apply { start() }.looper)
    }
    private var currentDnsList = listOf<String>()
    private var currentNetwork: Network? = null
    private var started = false

    @Volatile
    private var underlyingListener: ((Network?) -> Unit)? = null

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            addCapability(NetworkCapabilities.NET_CAPABILITY_FOREGROUND)
        }
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val capabilities = connectivity?.getNetworkCapabilities(network)
            networkInfos[network] = NetworkInfo(
                validated = capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_VALIDATED,
                ) == true,
                notSuspended = Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
                    capabilities?.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED,
                    ) != false,
            )
            scheduleUpdateDns()
        }

        override fun onCapabilitiesChanged(
            network: Network,
            networkCapabilities: NetworkCapabilities,
        ) {
            val info = networkInfos.computeIfAbsent(network) { NetworkInfo() }
            val wasValidated = info.validated
            val nowValidated = networkCapabilities.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_VALIDATED,
            )
            info.validated = nowValidated
            info.notSuspended = Build.VERSION.SDK_INT < Build.VERSION_CODES.P ||
                networkCapabilities.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED,
                )
            val urgent = network == currentNetwork && wasValidated && !nowValidated
            scheduleUpdateDns(urgent = urgent)
        }

        override fun onBlockedStatusChanged(network: Network, blocked: Boolean) {
            val info = networkInfos[network] ?: return
            info.blocked = blocked
            scheduleUpdateDns(urgent = blocked && network == currentNetwork)
        }

        override fun onLosing(network: Network, maxMsToLive: Int) {
            val info = networkInfos[network] ?: return
            info.losingUntilMillis = System.currentTimeMillis() + maxMsToLive
            scheduleUpdateDns(urgent = network == currentNetwork)
            if (maxMsToLive > 0) {
                handler.postDelayed({
                    if (networkInfos.containsKey(network)) {
                        updateDns()
                    }
                }, maxMsToLive.toLong() + 50)
            }
        }

        override fun onLost(network: Network) {
            networkInfos.remove(network)
            scheduleUpdateDns(urgent = network == currentNetwork)
        }

        override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
            networkInfos[network]?.dnsList = linkProperties.dnsServers
            scheduleUpdateDns()
        }
    }

    private val updateDnsTask = Runnable(::updateDns)

    fun setUnderlyingNetworkListener(listener: ((Network?) -> Unit)?) {
        underlyingListener = listener
        listener?.invoke(currentNetwork)
    }

    private fun scheduleUpdateDns(urgent: Boolean = false) {
        handler.removeCallbacks(updateDnsTask)
        val delay = if (urgent) FAST_SWITCH_DELAY_MILLIS else DNS_UPDATE_DELAY_MILLIS
        handler.postDelayed(updateDnsTask, delay)
    }

    @Synchronized
    fun start() {
        if (started) return
        runCatching { requireNotNull(connectivity).registerNetworkCallback(request, callback) }
            .onSuccess { started = true }
            .onFailure { error -> GlobalState.log("Unable to observe networks: $error") }
    }

    private fun networkPriority(entry: Map.Entry<Network, NetworkInfo>): Int {
        val capabilities = connectivity?.getNetworkCapabilities(entry.key)
        return when {
            capabilities == null -> 100
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> 90
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                capabilities.hasTransport(TRANSPORT_USB) -> 2

            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH) -> 3
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 4
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
                capabilities.hasTransport(TRANSPORT_SATELLITE) -> 5

            else -> 20
        } + entry.value.priorityPenalty
    }

    @Synchronized
    private fun updateDns() {
        val preferred = networkInfos.entries.minByOrNull(::networkPriority)
        val dnsList = preferred
            ?.value
            ?.dnsList
            .orEmpty()
            .map { address -> address.asSocketAddressText(DNS_PORT) }
            .distinct()
        if (dnsList != currentDnsList) {
            currentDnsList = dnsList
            Core.updateDNS(dnsList.joinToString(","))
        }
        val network = preferred?.key
        if (network == null) {
            if (currentNetwork != null) {
                currentNetwork = null
                underlyingListener?.invoke(null)
            }
            return
        }
        val previous = currentNetwork
        if (previous != network) {
            currentNetwork = network
            underlyingListener?.invoke(network)
            if (previous != null) {
                Core.resetNetwork()
            }
        }
    }
}

private const val DNS_PORT = 53
private const val FAST_SWITCH_DELAY_MILLIS = 25L
private const val DNS_UPDATE_DELAY_MILLIS = 120L

private fun InetAddress.asSocketAddressText(port: Int): String = when (this) {
    is Inet6Address -> "[$hostAddress]:$port"
    is Inet4Address -> "$hostAddress:$port"
    else -> error("Unsupported address type: ${javaClass.name}")
}
