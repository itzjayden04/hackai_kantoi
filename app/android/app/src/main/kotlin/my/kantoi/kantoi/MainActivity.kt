package my.kantoi.kantoi

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
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
