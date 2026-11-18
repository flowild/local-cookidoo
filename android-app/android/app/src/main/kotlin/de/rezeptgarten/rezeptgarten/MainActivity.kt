package de.rezeptgarten.rezeptgarten

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private data class Export(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pendingExport: Export? = null
    private val exportRequestCode = 2173
    private val apkUpdater = ApkUpdater(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkUpdater.register(flutterEngine.dartExecutor.binaryMessenger)
        val preferences = getPreferences(MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.rezeptgarten/preferences")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "weekDay" -> result.success(preferences.getInt("weekDay", 0))
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.rezeptgarten/documents")
            .setMethodCallHandler { call, result ->
                if (call.method == "saveCollection") {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || pendingExport != null) {
                        result.error("invalid_export", "Der Export konnte nicht begonnen werden.", null)
                    } else {
                        createExportDocument(bytes, result)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun openLink(uri: Uri, result: MethodChannel.Result) {
        try {
            startActivity(Intent(Intent.ACTION_VIEW, uri))
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("no_handler", "Der Link konnte nicht geöffnet werden.", null)
        }
    }

    @Suppress("DEPRECATION")
    private fun createExportDocument(bytes: ByteArray, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, "rezeptgarten-sammlung.json")
        }
        pendingExport = Export(bytes, result)
        try {
            startActivityForResult(intent, exportRequestCode)
        } catch (_: ActivityNotFoundException) {
            pendingExport = null
            result.error("no_picker", "Die Dateiauswahl konnte nicht geöffnet werden.", null)
        }
    }

    @Deprecated("Dispatches the document picker result from the Android activity.")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (apkUpdater.handleActivityResult(requestCode)) return
        if (requestCode != exportRequestCode) return
        val export = pendingExport ?: return
        pendingExport = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null || uri.scheme != "content") {
            export.result.success(false)
            return
        }
        Thread {
            val saved = try {
                contentResolver.openOutputStream(uri)?.use { it.write(export.bytes) } != null
            } catch (_: Exception) {
                false
            }
            runOnUiThread {
                if (saved) {
                    export.result.success(true)
                } else {
                    export.result.error("save_failed", "Die Exportdatei konnte nicht gespeichert werden.", null)
                }
            }
        }.start()
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
