package my.kantoi.kantoi

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The Scam Monitor: which messaging apps Kantoi watches, how much of each
 * message their notifications show, the user's per-app switches, and simple
 * per-app daily counts for the Check tab's chart. Everything stays on the phone.
 */
object MonitorApps {
    /** full = the message text; preview = part of it; sender = only who wrote; email = sender and subject. */
    data class App(val pkg: String, val name: String, val coverage: String, val group: String)

    val all = listOf(
        // SMS
        App("com.google.android.apps.messaging", "Messages (Google)", "full", "SMS"),
        App("com.samsung.android.messaging", "Samsung Messages", "full", "SMS"),
        App("com.android.mms", "Messages", "full", "SMS"),
        App("com.android.messaging", "Messaging", "full", "SMS"),
        App("com.hihonor.mms", "Honor Messages", "full", "SMS"),
        App("com.huawei.message", "Huawei Messages", "full", "SMS"),
        App("com.huawei.mms", "Huawei Messaging", "full", "SMS"),
        // Chat
        App("com.whatsapp", "WhatsApp", "full", "Chat"),
        App("com.whatsapp.w4b", "WhatsApp Business", "full", "Chat"),
        App("org.telegram.messenger", "Telegram", "full", "Chat"),
        App("org.telegram.messenger.web", "Telegram", "full", "Chat"),
        App("org.thunderdog.challegram", "Telegram X", "full", "Chat"),
        App("org.thoughtcrime.securesms", "Signal", "full", "Chat"),
        App("com.viber.voip", "Viber", "full", "Chat"),
        App("com.tencent.mm", "WeChat", "preview", "Chat"),
        App("jp.naver.line.android", "LINE", "full", "Chat"),
        App("com.imo.android.imoim", "imo", "full", "Chat"),
        App("kik.android", "Kik", "full", "Chat"),
        App("com.facebook.orca", "Messenger", "full", "Chat"),
        App("com.discord", "Discord", "full", "Chat"),
        App("com.Slack", "Slack", "full", "Chat"),
        App("com.microsoft.teams", "Microsoft Teams", "preview", "Chat"),
        // Social
        App("com.facebook.katana", "Facebook", "preview", "Social"),
        App("com.facebook.lite", "Facebook Lite", "preview", "Social"),
        App("com.instagram.android", "Instagram", "preview", "Social"),
        App("com.ss.android.ugc.trill", "TikTok", "preview", "Social"),
        App("com.zhiliaoapp.musically", "TikTok", "preview", "Social"),
        App("com.snapchat.android", "Snapchat", "sender", "Social"),
        App("com.twitter.android", "X (Twitter)", "preview", "Social"),
        App("com.reddit.frontpage", "Reddit", "preview", "Social"),
        App("com.pinterest", "Pinterest", "sender", "Social"),
        App("com.linkedin.android", "LinkedIn", "preview", "Social"),
        // Email
        App("com.google.android.gm", "Gmail", "email", "Email"),
        App("com.microsoft.office.outlook", "Outlook", "email", "Email"),
        App("com.yahoo.mobile.client.android.mail", "Yahoo Mail", "email", "Email"),
        App("com.samsung.android.email.provider", "Samsung Email", "email", "Email"),
        App("ch.protonmail.android", "Proton Mail", "email", "Email"),
        // Shopping and marketplaces
        App("com.thecarousell.Carousell", "Carousell", "preview", "Shopping"),
        App("com.shopee.my", "Shopee", "preview", "Shopping"),
        App("com.lazada.android", "Lazada", "preview", "Shopping"),
        App("com.ebay.mobile", "eBay", "preview", "Shopping"),
        App("org.craigslist.app", "craigslist", "preview", "Shopping"),
    )

    private val byPkg = all.associateBy { it.pkg }

    fun find(pkg: String): App? = byPkg[pkg]

    fun isEmail(pkg: String) = byPkg[pkg]?.coverage == "email"

    /** Watched when supported and not switched off by the user. */
    fun watched(ctx: Context, pkg: String): Boolean = pkg in byPkg && pkg !in off(ctx)

    private fun off(ctx: Context): Set<String> = GuardEngine.prefs(ctx).getStringSet("mon_off", emptySet()) ?: emptySet()

    fun setOn(ctx: Context, pkg: String, on: Boolean) {
        val s = off(ctx).toMutableSet()
        if (on) s.remove(pkg) else s.add(pkg)
        GuardEngine.prefs(ctx).edit().putStringSet("mon_off", s).apply()
    }

    /** Hide a scam notification and show Kantoi's warning in its place. */
    fun hideScams(ctx: Context) = GuardEngine.prefs(ctx).getBoolean("mon_hide", true)

    fun setHideScams(ctx: Context, on: Boolean) = GuardEngine.prefs(ctx).edit().putBoolean("mon_hide", on).apply()

    private fun installed(ctx: Context, pkg: String): Boolean = try {
        if (Build.VERSION.SDK_INT >= 33) {
            ctx.packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            ctx.packageManager.getPackageInfo(pkg, 0)
        }
        true
    } catch (e: Exception) {
        false
    }

    private fun day(t: Long = System.currentTimeMillis()) = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(t))

    /** Counts one checked message (alert = false) or one warning (alert = true) for today. */
    @Synchronized
    fun count(ctx: Context, pkg: String, alert: Boolean) {
        if (pkg !in byPkg) return
        val p = GuardEngine.prefs(ctx)
        val o = try {
            JSONObject(p.getString("mon_stats", "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
        val app = o.optJSONObject(pkg) ?: JSONObject()
        val d = day()
        val cell = app.optJSONArray(d) ?: org.json.JSONArray().put(0).put(0)
        val i = if (alert) 1 else 0
        cell.put(i, cell.optInt(i) + 1)
        app.put(d, cell)
        // Keep two weeks.
        val keep = (0 until 14).map { day(System.currentTimeMillis() - it * 86_400_000L) }.toSet()
        app.keys().asSequence().toList().filter { it !in keep }.forEach { app.remove(it) }
        o.put(pkg, app)
        p.edit().putString("mon_stats", o.toString()).apply()
    }

    /** Everything the Scam Monitor screen shows, for Flutter. */
    fun snapshot(ctx: Context): Map<String, Any?> {
        val stats = try {
            JSONObject(GuardEngine.prefs(ctx).getString("mon_stats", "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }
        val offSet = off(ctx)
        val apps = all.map { a ->
            val s = stats.optJSONObject(a.pkg)
            val days = mutableMapOf<String, List<Int>>()
            s?.keys()?.forEach { k ->
                val c = s.optJSONArray(k)
                if (c != null) days[k] = listOf(c.optInt(0), c.optInt(1))
            }
            mapOf(
                "pkg" to a.pkg,
                "name" to a.name,
                "coverage" to a.coverage,
                "group" to a.group,
                "installed" to installed(ctx, a.pkg),
                "on" to (a.pkg !in offSet),
                "days" to days,
            )
        }
        return mapOf("apps" to apps, "hide" to hideScams(ctx), "today" to day())
    }
}
