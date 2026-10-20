package my.kantoi.kantoi

import android.Manifest
import android.app.role.RoleManager
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

/**
 * Hands "Share to Kantoi" items (text or one file) to Flutter, and runs the
 * phone protection switches (kantoi/guard).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var guard: MethodChannel? = null
    private var pending: Map<String, Any?>? = null

    /** A tapped warning notification, waiting for Flutter to ask (cold start). */
    private var pendingTrace: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pending = readShare(intent)
        pendingTrace = readTrace(intent)
        if (GuardEngine.isEnabled(this)) GuardService.start(this)
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
        guard = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "kantoi/guard")
        guard?.setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> {
                    val trace = pendingTrace
                    pendingTrace = null
                    result.success(status(trace))
                }
                "enable" -> {
                    GuardEngine.setEnabled(this, call.arguments == true)
                    result.success(null)
                }
                "setGuard" -> {
                    val a = call.arguments as? Map<*, *>
                    val key = a?.get("key") as? String
                    if (key != null) GuardEngine.setGuard(this, key, a["on"] == true)
                    result.success(null)
                }
                "open" -> {
                    openSetting(call.arguments as? String)
                    result.success(null)
                }
                "preview" -> {
                    when (call.arguments as? String) {
                        "call" -> CallWarning.preview(this)
                        "site" -> SiteBlocked.preview(this)
                        "badge" -> ChatBadge.preview(this)
                        else -> PauseOverlay.preview(this)
                    }
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

    private fun status(trace: String?): Map<String, Any?> = mapOf(
        "enabled" to GuardEngine.isEnabled(this),
        "notifications" to listenerOn(),
        "overlay" to (Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(this)),
        "accessibility" to accessibilityOn(),
        "postNotifications" to (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED),
        "battery" to (Build.VERSION.SDK_INT < 23 ||
            (getSystemService(POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)),
        "callScreening" to callScreeningOn(),
        "callScreeningSupported" to (Build.VERSION.SDK_INT >= 29),
        "photos" to photosOn(),
        "recent" to GuardEngine.recent(this),
        "guards" to GuardEngine.guards(this),
        "stats" to GuardEngine.stats(this),
        "since" to GuardEngine.prefs(this).getLong("since", 0L),
        "openTrace" to trace,
    )

    /** Android 9 and older can't screen calls, so there is nothing to set up. */
    private fun callScreeningOn(): Boolean {
        if (Build.VERSION.SDK_INT < 29) return true
        val rm = getSystemService(RoleManager::class.java) ?: return false
        return rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) && rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)
    }

    private fun photosOn(): Boolean {
        val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        return checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
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
        if (which == "photos") {
            val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
            if (shouldAskOrOpen(perm)) requestPermissions(arrayOf(perm), 42)
            return
        }
        if (which == "callScreening") {
            if (Build.VERSION.SDK_INT >= 29) {
                val rm = getSystemService(RoleManager::class.java)
                if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_CALL_SCREENING) && !rm.isRoleHeld(RoleManager.ROLE_CALL_SCREENING)) {
                    startActivityForResult(rm.createRequestRoleIntent(RoleManager.ROLE_CALL_SCREENING), 43)
                    return
                }
                askAnswerCalls()
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

    /** After a denied runtime permission Android stops asking: open Kantoi's app settings instead. */
    private fun shouldAskOrOpen(perm: String): Boolean {
        val asked = GuardEngine.prefs(this).getBoolean("asked_$perm", false)
        if (asked && !shouldShowRequestPermissionRationale(perm) && checkSelfPermission(perm) != PackageManager.PERMISSION_GRANTED) {
            openSetting("appDetails")
            return false
        }
        GuardEngine.prefs(this).edit().putBoolean("asked_$perm", true).apply()
        return true
    }

    /** Lets the "Decline call" button on the call warning end a ringing call. */
    private fun askAnswerCalls() {
        if (Build.VERSION.SDK_INT >= 28 && checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.ANSWER_PHONE_CALLS), 44)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 43 && callScreeningOn()) askAnswerCalls()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // The picture watcher starts once Android allows it.
        if (requestCode == 42 && GuardEngine.isEnabled(this)) GuardService.start(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        readTrace(intent)?.let {
            guard?.invokeMethod("openTrace", it)
            return
        }
        val data = readShare(intent) ?: return
        channel?.invokeMethod("shared", data)
    }

    /** The link, number or message of a tapped warning notification. */
    private fun readTrace(intent: Intent?): String? {
        if (intent == null) return null
        val t = intent.getStringExtra(Notifier.EXTRA_TRACE) ?: return null
        // Handle each tap once, even if the activity is recreated.
        intent.removeExtra(Notifier.EXTRA_TRACE)
        return t.ifBlank { null }
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
