package de.rezeptgarten.rezeptgarten

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class WifiStatus(private val activity: MainActivity) {
    private val connectivity = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val wifi = activity.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null
    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = publish()
        override fun onLost(network: Network) = publish()
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) = publish()
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "de.rezeptgarten/network").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(current())
                "requestPermission" -> {
                    if (permissionResult != null) {
                        result.error("busy", "Die Berechtigungsanfrage läuft bereits.", null)
                    } else if (hasPreciseLocation()) {
                        result.success(current())
                    } else {
                        permissionResult = result
                        activity.requestPermissions(
                            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
                            2174,
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "de.rezeptgarten/network_changes").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
                connectivity.registerDefaultNetworkCallback(callback)
                publish()
            }
            override fun onCancel(arguments: Any?) {
                connectivity.unregisterNetworkCallback(callback)
                sink = null
            }
        })
    }

    private fun hasPreciseLocation() =
        activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun onPermissionResult(requestCode: Int) {
        if (requestCode == 2174) {
            permissionResult?.success(current())
            permissionResult = null
            publish()
        }
    }

    @Suppress("DEPRECATION")
    private fun current(): Map<String, Any?> {
        val network = connectivity.activeNetwork
        val capabilities = network?.let { connectivity.getNetworkCapabilities(it) }
        val isWifi = capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        val granted = hasPreciseLocation()
        val ssid = if (isWifi && granted) wifi.connectionInfo?.ssid?.removeSurrounding("\"") else null
        return mapOf("ssid" to ssid?.takeUnless { it == "<unknown ssid>" }, "permission" to granted, "wifi" to isWifi,
                     "online" to (capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true))
    }

    private fun publish() {
        handler.post { sink?.success(current()) }
    }
}
