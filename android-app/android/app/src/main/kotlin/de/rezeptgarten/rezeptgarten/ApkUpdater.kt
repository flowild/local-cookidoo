package de.rezeptgarten.rezeptgarten

import android.app.Activity
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.URL
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManagerFactory

class ApkFileProvider : FileProvider()

internal class ApkUpdater(private val activity: Activity) {
    private val permissionRequest = 2174
    private var result: MethodChannel.Result? = null
    private var ready: File? = null
    private var awaitingPermission = false
    private var resumed = false

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "de.rezeptgarten/update").setMethodCallHandler { call, reply ->
            when {
                call.method != "downloadAndInstall" -> reply.notImplemented()
                result != null -> reply.error("busy", "Ein APK-Download läuft bereits.", null)
                else -> start(reply)
            }
        }
    }

    private fun start(reply: MethodChannel.Result) {
        result = reply
        Thread {
            try {
                val apk = download()
                activity.runOnUiThread {
                    if (activity.isFinishing || activity.isDestroyed) {
                        apk.delete()
                        finish(error = "Der APK-Download wurde abgebrochen.")
                    } else {
                        ready = apk
                        openWhenReady()
                    }
                }
            } catch (error: UpdateException) {
                activity.runOnUiThread { finish(error = error.message) }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    finish(error = "Die APK konnte nicht geladen werden. Prüfe die Verbindung zum Heimnetz.")
                }
            }
        }.start()
    }

    fun resume() {
        resumed = true
        openWhenReady()
    }

    fun pause() {
        resumed = false
    }

    fun handleActivityResult(requestCode: Int): Boolean {
        if (requestCode != permissionRequest) return false
        awaitingPermission = false
        if (!canInstall()) {
            ready?.delete()
            finish(error = "Android benötigt die Freigabe zum Installieren von Apps aus dieser Quelle.")
        } else {
            openWhenReady()
        }
        return true
    }

    private fun canInstall() =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

    @Suppress("DEPRECATION")
    private fun openWhenReady() {
        val apk = ready ?: return
        if (!resumed || awaitingPermission) return
        try {
            if (!canInstall()) {
                awaitingPermission = true
                activity.startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")),
                    permissionRequest,
                )
                return
            }
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
            activity.startActivity(Intent(Intent.ACTION_INSTALL_PACKAGE, uri).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            finish("installerOpened")
        } catch (_: Exception) {
            apk.delete()
            finish(error = "Der Android-Installer konnte nicht geöffnet werden.")
        }
    }

    private fun finish(status: String? = null, error: String? = null) {
        val reply = result
        result = null
        ready = null
        awaitingPermission = false
        if (error == null) reply?.success(status)
        else reply?.error("apk_update", error, null)
    }

    @Suppress("DEPRECATION")
    private fun download(): File {
        val test = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        val channel = if (test) "test" else "release"
        val base = if (test) "https://192.168.184.30/android/test/" else "https://192.168.184.30/android/"
        val transport = trustedTransport()
        val manifest = JSONObject(read(base + "latest.json", transport) { connection ->
            connection.inputStream.use { input ->
                val buffer = ByteArray(4097)
                var size = 0
                while (size < buffer.size) {
                    val count = input.read(buffer, size, buffer.size - size)
                    if (count == -1) break
                    size += count
                }
                if (size == buffer.size) throw UpdateException("Die Update-Informationen sind ungültig.")
                String(buffer, 0, size, Charsets.UTF_8)
            }
        })
        val build = manifest.getLong("versionCode")
        val version = manifest.getString("version")
        val hash = manifest.getString("sha256")
        val size = manifest.getLong("size")
        val filename = manifest.getString("file")
        if (
            build !in 1L..2_100_000_000L || !version.matches(Regex("[0-9]{1,10}\\.[0-9]{1,10}\\.[0-9]{1,10}")) ||
            !hash.matches(Regex("[a-f0-9]{64}")) || size !in 1L..(512L * 1024 * 1024) ||
            filename != "rezeptgarten-$channel-$version-$build-${hash.take(12)}.apk"
        ) throw UpdateException("Die Update-Informationen sind ungültig.")

        val manager = activity.packageManager
        val installed = manager.getPackageInfo(activity.packageName, 0)
        if (build < versionCode(installed)) {
            throw UpdateException("Die APK auf dem Server ist älter als die installierte Version.")
        }
        val directory = File(activity.cacheDir, "apk-updates")
        check(directory.isDirectory || directory.mkdirs())
        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
        directory.listFiles()?.filter { it.isFile && it.lastModified() < cutoff }?.forEach { it.delete() }
        val apk = File.createTempFile("rezeptgarten-", ".apk", directory)
        try {
            val digest = MessageDigest.getInstance("SHA-256")
            val deadline = SystemClock.elapsedRealtime() + 300_000
            var received = 0L
            read(base + filename, transport) { connection ->
                connection.inputStream.use { input ->
                    apk.outputStream().use { output ->
                        val buffer = ByteArray(65536)
                        while (true) {
                            val count = input.read(buffer)
                            if (count == -1) break
                            received += count
                            if (received > size) throw UpdateException("Die heruntergeladene APK hat eine falsche Größe.")
                            if (SystemClock.elapsedRealtime() > deadline) {
                                throw UpdateException("Der APK-Download hat zu lange gedauert.")
                            }
                            output.write(buffer, 0, count)
                            digest.update(buffer, 0, count)
                        }
                    }
                }
            }
            val checksum = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
            if (received != size || checksum != hash) {
                throw UpdateException("Die heruntergeladene APK hat die Integritätsprüfung nicht bestanden.")
            }
            val archive = manager.getPackageArchiveInfo(apk.absolutePath, 0)
            if (archive == null || archive.packageName != activity.packageName ||
                versionCode(archive) != build || archive.versionName != version
            ) throw UpdateException("Die heruntergeladene APK passt nicht zu dieser Installation.")
            return apk
        } catch (error: Exception) {
            apk.delete()
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: android.content.pm.PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode else info.versionCode.toLong()

    private fun trustedTransport(): SSLSocketFactory {
        val path = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/rezeptgarten-ca.pem")
        val certificate = activity.assets.open(path).use {
            CertificateFactory.getInstance("X.509").generateCertificate(it)
        }
        val trust = KeyStore.getInstance(KeyStore.getDefaultType()).apply {
            load(null, null)
            setCertificateEntry("rezeptgarten", certificate)
        }
        val managers = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply {
            init(trust)
        }
        return SSLContext.getInstance("TLS").apply { init(null, managers.trustManagers, null) }.socketFactory
    }

    private fun <T> read(url: String, transport: SSLSocketFactory, consume: (HttpsURLConnection) -> T): T {
        val connection = URL(url).openConnection() as HttpsURLConnection
        try {
            connection.sslSocketFactory = transport
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.connectTimeout = 8000
            connection.readTimeout = 15000
            when (connection.responseCode) {
                200 -> return consume(connection)
                404 -> throw UpdateException("Für diesen Downloadkanal ist derzeit keine APK verfügbar.")
                else -> throw UpdateException("Der Rezeptgarten-Server konnte die APK nicht bereitstellen.")
            }
        } finally {
            connection.disconnect()
        }
    }

    private class UpdateException(override val message: String) : Exception(message)
}
