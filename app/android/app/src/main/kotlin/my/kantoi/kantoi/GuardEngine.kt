package my.kantoi.kantoi

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Runs Kantoi's Dart scam checks in the background (no screen), so phone
 * protection works while the app is closed. Messages are queued until the
 * Dart side says it is ready.
 */
object GuardEngine {
    private const val PREFS = "kantoi_guard"
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val queue = ArrayDeque<Pair<Map<String, Any?>, (Map<*, *>?) -> Unit>>()
    private val main = Handler(Looper.getMainLooper())

    /** Time of the last warning, used to pause the user before a payment app. */
    var lastAlertAt = 0L
    var lastAlert: Map<*, *>? = null

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context) = prefs(ctx).getBoolean("enabled", false)

    fun setEnabled(ctx: Context, on: Boolean) = prefs(ctx).edit().putBoolean("enabled", on).apply()

    /** Checks one message, then calls [done] on the main thread with the result. */
    fun check(ctx: Context, msg: Map<String, Any?>, done: (Map<*, *>?) -> Unit) {
        main.post {
            try {
                start(ctx.applicationContext)
                if (ready) send(msg, done) else queue.addLast(msg to done)
            } catch (e: Exception) {
                done(null)
            }
        }
    }

    private fun start(ctx: Context) {
        if (engine != null) return
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(ctx)
        loader.ensureInitializationComplete(ctx, null)
        val e = FlutterEngine(ctx)
        val ch = MethodChannel(e.dartExecutor.binaryMessenger, "kantoi/guard_bg")
        ch.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                ready = true
                while (queue.isNotEmpty()) {
                    val (m, d) = queue.removeFirst()
                    send(m, d)
                }
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "guardMain"))
        engine = e
        channel = ch
    }

    private fun send(msg: Map<String, Any?>, done: (Map<*, *>?) -> Unit) {
        val ch = channel ?: return done(null)
        ch.invokeMethod("check", msg, object : MethodChannel.Result {
            override fun success(result: Any?) = done(result as? Map<*, *>)
            override fun error(code: String, message: String?, details: Any?) = done(null)
            override fun notImplemented() = done(null)
        })
    }

    /** Handles a scored message: shows the pause card when the Dart side asks. */
    fun handle(ctx: Context, result: Map<*, *>?) {
        if (result == null || result["alert"] != true) return
        lastAlertAt = System.currentTimeMillis()
        lastAlert = result
        remember(ctx, result)
        PauseOverlay.showWarning(ctx, result)
    }

    /** Keeps the last 30 warnings on the phone for the Live tab. */
    private fun remember(ctx: Context, r: Map<*, *>) {
        val p = prefs(ctx)
        val old = JSONArray(p.getString("recent", "[]"))
        val o = JSONObject()
        for (k in listOf("app", "chat", "level", "label", "headline", "text")) o.put(k, r[k]?.toString() ?: "")
        o.put("reasons", JSONArray((r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList<String>()))
        o.put("at", System.currentTimeMillis())
        val out = JSONArray().put(o.toString())
        for (i in 0 until minOf(old.length(), 29)) out.put(old.getString(i))
        p.edit().putString("recent", out.toString()).apply()
    }

    fun recent(ctx: Context): List<String> {
        val a = JSONArray(prefs(ctx).getString("recent", "[]"))
        return (0 until a.length()).map { a.getString(it) }
    }

    fun clearRecent(ctx: Context) = prefs(ctx).edit().remove("recent").apply()

    /** Chat apps Kantoi watches. Everything else is ignored. */
    val chatApps = setOf(
        "com.whatsapp",
        "com.whatsapp.w4b",
        "org.telegram.messenger",
        "org.telegram.messenger.web",
        "org.thunderdog.challegram",
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms",
        "com.facebook.orca",
        "com.instagram.android",
    )
}
