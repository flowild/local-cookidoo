package de.rezeptgarten.rezeptgarten

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val apkUpdater = ApkUpdater(this)
    private val wifiStatus by lazy { WifiStatus(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkUpdater.register(flutterEngine.dartExecutor.binaryMessenger)
        wifiStatus.register(flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.rezeptgarten/storage")
            .setMethodCallHandler { call, result ->
                if (call.method == "noBackupDirectory") result.success(noBackupFilesDir.absolutePath)
                else result.notImplemented()
            }
        val preferences = getPreferences(MODE_PRIVATE)
        val collectionPreferences = getSharedPreferences("collection_order", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.rezeptgarten/preferences")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "weekDay" -> result.success(preferences.getInt("weekDay", 0))
                    "collectionOrder" -> {
                        val key = if (call.arguments == true) "debugCollectionOrder" else "collectionOrder"
                        result.success(collectionPreferences.getString(key, null))
                    }
                    "setCollectionOrder" -> {
                        val key = if (call.argument<Boolean>("debug") == true) "debugCollectionOrder" else "collectionOrder"
                        val order = call.argument<String>("order")
                        if (order == null) {
                            result.error("invalid_order", "Die Listenreihenfolge ist ungültig.", null)
                        } else {
                            collectionPreferences.edit().putString(key, order).apply()
                            result.success(null)
                        }
                    }
                    "debugMode" -> result.success(preferences.getBoolean("debugMode", false))
                    "setDebugMode" -> {
                        val enabled = call.arguments as? Boolean
                        if (enabled == null) {
                            result.error("invalid_debug_mode", "Der Debug-Modus ist ungültig.", null)
                        } else {
                            preferences.edit().putBoolean("debugMode", enabled).apply()
                            result.success(null)
                        }
                    }
                    "appearance" -> result.success(
                        mapOf("dark" to preferences.getBoolean("dark", false),
                              "accent" to preferences.getLong("accent", 0xff234d3cL))
                    )
                    "setAppearance" -> {
                        val dark = call.argument<Boolean>("dark")
                        val accent = call.argument<Number>("accent")?.toLong()
                        if (dark == null || accent == null || accent !in 0xff000000L..0xffffffffL) {
                            result.error("invalid_appearance", "Diese Darstellung ist ungültig.", null)
                        } else {
                            preferences.edit().putBoolean("dark", dark).putLong("accent", accent).apply()
                            result.success(null)
                        }
                    }
                    "version" -> result.success(packageManager.getPackageInfo(packageName, 0).versionName)
                    "setWeekDay" -> {
                        val day = call.arguments as? Int
                        if (day == null || day !in 0..6) {
                            result.error("invalid_day", "Dieser Wochentag ist ungültig.", null)
                        } else {
                            preferences.edit().putInt("weekDay", day).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.rezeptgarten/links")
            .setMethodCallHandler { call, result ->
                if (call.method != "openCookidoo") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = (call.arguments as? String)?.let(Uri::parse)
                if (uri == null || uri.scheme != "https" || uri.encodedUserInfo != null ||
                    uri.host !in setOf("cookidoo.de", "cookidoo.at", "cookidoo.ch") ||
                    (uri.port != -1 && uri.port != 443)
                ) {
                    result.error("invalid_link", "Dieser Cookidoo-Link ist ungültig.", null)
                    return@setMethodCallHandler
                }
                openLink(uri, result)
            }
    }

    @Deprecated("Deprecated in Android")
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        wifiStatus.onPermissionResult(requestCode)
    }

    private fun openLink(uri: Uri, result: MethodChannel.Result) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("no_handler", "Der Link konnte nicht geöffnet werden.", null)
        }
    }

    @Deprecated("Dispatches the package installer result from the Android activity.")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        apkUpdater.handleActivityResult(requestCode)
    }

    override fun onPostResume() {
        super.onPostResume()
        apkUpdater.resume()
    }

    override fun onPause() {
        apkUpdater.pause()
        super.onPause()
    }
}
