package my.kantoi.kantoi

import android.Manifest
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.PowerManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Hands "Share to Kantoi" items (text or one file) to Flutter. */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = readShare(intent)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kantoi/share").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pending)
                    pending = null
                } else {
                    result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kantoi/guard").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(
                    mapOf(
                        "enabled" to GuardEngine.isEnabled(this),
                        "notifications" to listenerOn(),
                        "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)),
                        "accessibility" to accessibilityOn(),
                        "postNotifications" to (Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED),
                        "battery" to (Build.VERSION.SDK_INT < 23 ||
                            (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)),
                        "recent" to GuardEngine.recent(this),
                    ),
                )
                "enable" -> {
                    GuardEngine.setEnabled(this, call.arguments == true)
                    result.success(null)
                }
                "open" -> {
                    openSetting(call.arguments as? String)
                    result.success(null)
                }
                "preview" -> {
                    PauseOverlay.preview(this)
                    result.success(null)
                }
                "clear" -> {
                    GuardEngine.clearRecent(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun listenerOn(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(this, GuardNotificationListener::class.java)
        return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
    }

    private fun accessibilityOn(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES) ?: return false
        val me = ComponentName(this, GuardAccessibilityService::class.java)
        return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
    }

    private fun openSetting(which: String?) {
        if (which == "postNotifications") {
            if (Build.VERSION.SDK_INT >= 33) {
                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 41)
            }
            return
        }
        val i = when (which) {
            "battery" -> Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            "appDetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
            "notifications" -> Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
            "overlay" -> Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName"))
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            else -> return
        }
        try {
            startActivity(i)
        } catch (e: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val data = readShare(intent) ?: return
        channel?.invokeMethod("shared", data)
    }

    private fun readShare(intent: Intent?): Map<String, Any?>? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_SEND_MULTIPLE) return null
        val uri: Uri? = streamUri(intent)
        var bytes: ByteArray? = null
        var name: String? = null
        if (uri != null) {
            try {
                contentResolver.openInputStream(uri)?.use { s ->
                    val b = s.readBytes()
                    if (b.size <= 25 * 1024 * 1024) bytes = b
                }
                contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                    if (c.moveToFirst()) name = c.getString(0)
                }
            } catch (e: Exception) {
                // Unreadable shares fall back to any text that came with them.
            }
        }
        // Handle each share once, even if the activity is recreated.
        intent.action = Intent.ACTION_MAIN
        return mapOf(
            "text" to intent.getStringExtra(Intent.EXTRA_TEXT),
            "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT),
            "mime" to (uri?.let { contentResolver.getType(it) } ?: intent.type),
            "name" to name,
            "bytes" to bytes,
        )
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? {
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            val list: ArrayList<Uri>? = if (Build.VERSION.SDK_INT >= 33) {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
            } else {
                intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
            }
            return list?.firstOrNull()
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }
}
