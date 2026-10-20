package my.kantoi.kantoi

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout

/**
 * Full-screen "Kantoi closed this page" card (Stitch "site-blocked"), shown
 * after the Web & link blocker pressed Back on a scam website.
 */
object SiteBlocked {
    private var shown: View? = null
    private var wm: WindowManager? = null
    private val main = Handler(Looper.getMainLooper())

    fun show(ctx: Context, r: Map<*, *>, url: String) {
        dismiss()
        val app = ctx.applicationContext
        val ui = Ui(app)
        val host = r["host"]?.toString() ?: url
        val level = r["level"]?.toString() ?: "danger"
        val reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList()

        val root = ui.column().apply {
            setBackgroundColor(KColor.surface)
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(ui.dp(20), ui.dp(36), ui.dp(20), ui.dp(24))
        }
        // The address bar with the page crossed out.
        root.addView(ui.column().apply {
            background = ui.round(Color.WHITE, 16, KColor.outlineVariant)
            setPadding(ui.dp(14), ui.dp(10), ui.dp(14), ui.dp(10))
            addView(ui.text("⛔  CLOSED BY KANTOI", 12f, KColor.error, 700))
            addView(ui.text(host, 15f, KColor.error, 600).apply { paintFlags = paintFlags or Paint.STRIKE_THRU_TEXT_FLAG }, ui.lp(top = 4))
        }, ui.lp())
        root.addView(ui.text("🛡", 44f, Color.WHITE, center = true).apply {
            gravity = Gravity.CENTER
            background = ui.round(KColor.primaryContainer, 100, KColor.withAlpha(KColor.error, 0.35f), 6)
        }, LinearLayout.LayoutParams(ui.dp(104), ui.dp(104)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = ui.dp(24)
        })
        root.addView(ui.pill(r["label"]?.toString() ?: "Scam website", KColor.onErrorContainer, KColor.errorContainer),
            LinearLayout.LayoutParams(-2, -2).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = ui.dp(14)
            })
        root.addView(ui.text("Kantoi closed this page", 28f, KColor.onSurface, 700, center = true), ui.lp(top = 12))
        root.addView(ui.text(r["headline"]?.toString() ?: "This website looks like a scam.", 15f, KColor.onSurfaceVariant, center = true), ui.lp(top = 6))

        val sheet = ui.column(16).apply { background = ui.round(Color.WHITE, 18, KColor.outlineVariant) }
        sheet.addView(ui.text("WEBSITE", 11f, KColor.onSurfaceVariant, 700))
        sheet.addView(ui.text(host, 18f, KColor.forLevel(level), 700), ui.lp(top = 2))
        if (reasons.isNotEmpty()) {
            sheet.addView(ui.text("WHY KANTOI CLOSED IT", 11f, KColor.onSurfaceVariant, 700), ui.lp(top = 14))
            for (reason in reasons) sheet.addView(ui.reason("!", reason, null, KColor.error, KColor.surfaceLow), ui.lp(top = 8))
        }
        sheet.addView(ui.text("🔒  Checked on this phone. Nothing was typed or sent.", 13f, KColor.onSurfaceVariant), ui.lp(top = 14))
        root.addView(sheet, ui.lp(top = 18))

        val back = ui.button("←  Go back to safety", Color.WHITE, KColor.primaryContainer)
        val trace = ui.button("Check this website in Kantoi", KColor.primaryContainer, KColor.surfaceHigh)
        val anyway = ui.text("Open anyway (not recommended)", 14f, KColor.onSurfaceVariant, 500, center = true).apply {
            paintFlags = paintFlags or Paint.UNDERLINE_TEXT_FLAG
            setPadding(0, ui.dp(14), 0, ui.dp(8))
            gravity = Gravity.CENTER
        }
        root.addView(back, ui.lp(h = ui.dp(54), top = 18))
        root.addView(trace, ui.lp(h = ui.dp(50), top = 8))
        root.addView(anyway, ui.lp())

        back.setOnClickListener { dismiss() }
        trace.setOnClickListener {
            dismiss()
            try {
                Notifier.openApp(app, url, 4600).send()
            } catch (e: Exception) {
            }
        }
        // Opening a scam page takes a second, deliberate tap.
        var armed = false
        anyway.setOnClickListener {
            if (!armed) {
                armed = true
                anyway.text = "Tap again to open $host. Never type passwords or codes there."
                anyway.setTextColor(KColor.error)
                main.postDelayed({
                    armed = false
                    anyway.text = "Open anyway (not recommended)"
                    anyway.setTextColor(KColor.onSurfaceVariant)
                }, 5000)
                return@setOnClickListener
            }
            GuardEngine.allowHost(app, host)
            dismiss()
            try {
                val target = if (url.startsWith("http")) url else "https://$url"
                app.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(target)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (e: Exception) {
            }
        }

        val scroll = android.widget.ScrollView(app).apply {
            setBackgroundColor(KColor.surface)
            isFillViewport = true
            addView(root)
        }
        wm = Overlays.add(ctx, scroll, full = true) ?: return
        shown = scroll
    }

    fun preview(ctx: Context) = show(
        ctx,
        mapOf(
            "host" to "maybank-login.example",
            "level" to "danger",
            "label" to "Sample: fake bank website",
            "headline" to "This website pretends to be Maybank, but it is not Maybank's real website.",
            "reasons" to listOf("Pretends to be Maybank"),
        ),
        "maybank-login.example",
    )

    fun dismiss() {
        Overlays.remove(wm, shown)
        shown = null
        wm = null
    }
}
