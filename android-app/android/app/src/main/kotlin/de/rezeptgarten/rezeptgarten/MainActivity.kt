package de.rezeptgarten.rezeptgarten

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                try {
                    startActivity(Intent(Intent.ACTION_VIEW, uri))
                    result.success(null)
                } catch (_: ActivityNotFoundException) {
                    result.error("no_handler", "Cookidoo-Link konnte nicht geöffnet werden.", null)
                }
            }
    }
}
