package my.kantoi.kantoi

import android.content.Context
import android.content.SharedPreferences
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
 * protection works while the app is closed. Requests are queued until the
 * Dart side says it is ready. Also keeps the guard switches, counters and
 * recent warnings that the Protection centre shows.
 */
object GuardEngine {
    private const val PREFS = "kantoi_guard"
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private val queue = ArrayDeque<Triple<String, Map<String, Any?>, (Map<*, *>?) -> Unit>>()
    private val main = Handler(Looper.getMainLooper())

    /** Time of the last warning, used to pause the user before a payment app. */
    var lastAlertAt = 0L
    var lastAlert: Map<*, *>? = null

    /** The guards in the Protection centre (Guard.key in guard_control.dart). */
    val guardKeys = listOf("calls", "messages", "chats", "web", "apps", "photos")

    /** The counters shown in the Protection centre. */
    val statKeys = listOf("warnings", "pages", "calls", "messages", "chats", "apps", "photos")

    fun prefs(ctx: Context): SharedPreferences = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(ctx: Context) = prefs(ctx).getBoolean("enabled", false)

    fun setEnabled(ctx: Context, on: Boolean) {
        val e = prefs(ctx).edit().putBoolean("enabled", on)
        if (on && !isEnabled(ctx)) e.putLong("since", System.currentTimeMillis())
        e.apply()
        if (on) GuardService.start(ctx) else GuardService.stop(ctx)
    }

    /** True when protection is on and this guard is switched on. */
    fun guardOn(ctx: Context, key: String) = isEnabled(ctx) && prefs(ctx).getBoolean("g_$key", true)

    fun setGuard(ctx: Context, key: String, on: Boolean) = prefs(ctx).edit().putBoolean("g_$key", on).apply()

    fun guards(ctx: Context) = guardKeys.associateWith { prefs(ctx).getBoolean("g_$it", true) }

    fun count(ctx: Context, key: String) {
        val p = prefs(ctx)
        p.edit().putInt("n_$key", p.getInt("n_$key", 0) + 1).apply()
    }

    fun stats(ctx: Context) = statKeys.associateWith { prefs(ctx).getInt("n_$it", 0) }

    /** Numbers the user chose to always block. */
    fun blockedNumbers(ctx: Context): Set<String> = prefs(ctx).getStringSet("blocked", emptySet()) ?: emptySet()

    fun blockNumber(ctx: Context, digits: String) {
        if (digits.isBlank()) return
        prefs(ctx).edit().putStringSet("blocked", blockedNumbers(ctx) + digits).apply()
    }

    /** Websites the user chose to open anyway. */
    fun allowedHosts(ctx: Context): Set<String> = prefs(ctx).getStringSet("allowHosts", emptySet()) ?: emptySet()

    fun allowHost(ctx: Context, host: String) = prefs(ctx).edit().putStringSet("allowHosts", allowedHosts(ctx) + host).apply()

    /** Starts the background engine early so the first check is quick. */
    fun warm(ctx: Context) = main.post {
        try {
            start(ctx.applicationContext)
        } catch (e: Exception) {
        }
    }

    /** Checks one message, then calls [done] on the main thread with the result. */
    fun check(ctx: Context, msg: Map<String, Any?>, done: (Map<*, *>?) -> Unit) = call(ctx, "check", msg, done)

    /** Runs one of the Dart checks (see guard_background.dart). */
    fun call(ctx: Context, method: String, args: Map<String, Any?>, done: (Map<*, *>?) -> Unit) {
        main.post {
            try {
                start(ctx.applicationContext)
                if (ready) send(method, args, done) else queue.addLast(Triple(method, args, done))
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
                    val (m, a, d) = queue.removeFirst()
                    send(m, a, d)
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

    private fun send(method: String, args: Map<String, Any?>, done: (Map<*, *>?) -> Unit) {
        val ch = channel ?: return done(null)
        ch.invokeMethod(method, args, object : MethodChannel.Result {
            override fun success(result: Any?) = done(result as? Map<*, *>)
            override fun error(code: String, message: String?, details: Any?) = done(null)
            override fun notImplemented() = done(null)
        })
    }

    /** Handles a scored message: notification plus the pause card. */
    fun handle(ctx: Context, result: Map<*, *>?, kind: String = "messages") {
        if (result == null || result["alert"] != true) return
        lastAlertAt = System.currentTimeMillis()
        lastAlert = result
        val chat = result["chat"]?.toString().orEmpty()
        val text = result["text"]?.toString().orEmpty()
        remember(ctx, result, if (kind == "chats") "chat" else "message", text)
        count(ctx, kind)
        val reasons = (result["reasons"] as? List<*>)?.joinToString(", ") { it.toString() }.orEmpty()
        Notifier.warn(
            ctx,
            if (chat.isNotBlank()) "Careful: $chat may be a scammer" else "Careful: this message may be a scam",
            listOf(result["headline"]?.toString().orEmpty(), reasons).filter { it.isNotBlank() }.joinToString("\n"),
            text,
            result["level"]?.toString(),
        )
        PauseOverlay.showWarning(ctx, result)
    }

    /**
     * Keeps the last 30 warnings on the phone for the Protection centre, and
     * counts them. [kind] is message, chat, call, site, app or photo; [target]
     * is what a tap traces.
     */
    fun remember(ctx: Context, r: Map<*, *>, kind: String, target: String) {
        val p = prefs(ctx)
        val old = JSONArray(p.getString("recent", "[]"))
        val o = JSONObject()
        for (k in listOf("app", "chat", "level", "label", "headline", "text")) o.put(k, r[k]?.toString() ?: "")
        o.put("reasons", JSONArray((r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList<String>()))
        o.put("at", System.currentTimeMillis())
        o.put("kind", kind)
        o.put("target", target)
        val out = JSONArray().put(o.toString())
        for (i in 0 until minOf(old.length(), 29)) out.put(old.getString(i))
        p.edit().putString("recent", out.toString()).putInt("n_warnings", p.getInt("n_warnings", 0) + 1).apply()
    }

    fun recent(ctx: Context): List<String> {
        val a = JSONArray(prefs(ctx).getString("recent", "[]"))
        return (0 until a.length()).map { a.getString(it) }
    }

    fun clearRecent(ctx: Context) = prefs(ctx).edit().remove("recent").apply()

    /** Chat apps whose notifications Kantoi checks. Everything else is ignored. */
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

    /** Email apps: their notifications carry the sender and subject (and often a preview). */
    val emailApps = setOf(
        "com.google.android.gm",
        "com.microsoft.office.outlook",
        "com.samsung.android.email.provider",
        "com.yahoo.mobile.client.android.mail",
    )
}
