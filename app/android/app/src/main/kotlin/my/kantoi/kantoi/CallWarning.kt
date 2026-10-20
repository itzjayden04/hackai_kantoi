package my.kantoi.kantoi

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telecom.TelecomManager
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.Toast

/**
 * The call warning (Stitch "call-warning"), shown at the top of the screen
 * while a risky number rings. Kantoi only knows the number: it never hears
 * the call. The phone's own answer and decline buttons stay usable below.
 */
object CallWarning {
    private var shown: View? = null
    private var wm: WindowManager? = null
    private val main = Handler(Looper.getMainLooper())
    private val autoHide = Runnable { dismiss() }

    fun show(ctx: Context, r: Map<*, *>, digits: String) {
        val number = r["number"]?.toString() ?: digits
        val level = r["level"]?.toString() ?: "suspicious"
        val reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList()
        val title = r["title"]?.toString() ?: "Suspicious caller"
        if (!Overlays.canShow(ctx)) {
            Notifier.warn(ctx, "$title: $number", "Answer carefully. ${reasons.joinToString(" ")}", number, level)
            return
        }
        dismiss()
        val app = ctx.applicationContext
        val ui = Ui(app)
        val accent = KColor.forLevel(level)

        val panel = ui.column().apply {
            setPadding(ui.dp(16), ui.dp(36), ui.dp(16), ui.dp(16))
            background = ui.round(Color.parseColor("#213145"), 28)
            gravity = Gravity.CENTER_HORIZONTAL
        }
        panel.addView(ui.text("☎", 30f, KColor.onSurfaceVariant, center = true).apply {
            gravity = Gravity.CENTER
            background = ui.round(KColor.surfaceHigh, 100)
        }, LinearLayout.LayoutParams(ui.dp(64), ui.dp(64)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        panel.addView(ui.pill("Incoming call · Kantoi check", KColor.onErrorContainer, KColor.errorContainer),
            LinearLayout.LayoutParams(-2, -2).apply {
                gravity = Gravity.CENTER_HORIZONTAL
                topMargin = ui.dp(10)
            })
        panel.addView(ui.text(number, 26f, Color.parseColor("#EAF1FF"), 700, center = true), ui.lp(top = 6))

        val card = ui.column().apply { background = ui.round(Color.WHITE, 22) }
        card.addView(ui.text("●  ANSWER CAREFULLY", 13f, Color.WHITE, 700).apply {
            setPadding(ui.dp(16), ui.dp(12), ui.dp(16), ui.dp(12))
            background = android.graphics.drawable.GradientDrawable().apply {
                setColor(accent)
                val r0 = ui.dp(22).toFloat()
                cornerRadii = floatArrayOf(r0, r0, r0, r0, 0f, 0f, 0f, 0f)
            }
        })
        val body = ui.column(16)
        body.addView(ui.text(title, 21f, KColor.onErrorContainer, 700))
        for (reason in reasons.take(3)) body.addView(ui.reason("!", reason, null, accent, KColor.surfaceLow), ui.lp(top = 10))
        body.addView(ui.reason("✓", "Golden rule", "Police, courts, banks and LHDN never ask you to transfer money or give codes over the phone. Hang up and call them back on their official number.",
            KColor.error, Color.parseColor("#FFF1F0")), ui.lp(top = 10))

        val decline = ui.button("Decline call", Color.WHITE, KColor.error)
        val block = ui.button("Always block this number", KColor.primaryContainer, Color.WHITE, KColor.outlineVariant)
        val hide = ui.text("Hide this warning", 14f, KColor.onSurfaceVariant, 600, center = true).apply {
            setPadding(0, ui.dp(10), 0, ui.dp(4))
            gravity = Gravity.CENTER
        }
        body.addView(decline, ui.lp(h = ui.dp(52), top = 16))
        if (digits.isNotBlank()) body.addView(block, ui.lp(h = ui.dp(50), top = 8))
        body.addView(hide, ui.lp())
        body.addView(ui.text("Kantoi sees only the number, never the call itself.", 12f, KColor.onSurfaceVariant, center = true), ui.lp(top = 4))
        card.addView(body)
        panel.addView(card, ui.lp(top = 14))

        decline.setOnClickListener {
            dismiss()
            if (!endCall(app)) Toast.makeText(app, "Press the red button to decline the call.", Toast.LENGTH_LONG).show()
        }
        block.setOnClickListener {
            GuardEngine.blockNumber(app, digits)
            dismiss()
            endCall(app)
            Toast.makeText(app, "Kantoi will block calls from $number.", Toast.LENGTH_LONG).show()
        }
        hide.setOnClickListener { dismiss() }

        val wrap = android.widget.FrameLayout(app).apply {
            setPadding(ui.dp(8), ui.dp(8), ui.dp(8), 0)
            addView(panel)
        }
        val manager = Overlays.add(ctx, wrap, full = false, gravity = Gravity.TOP, wide = true) ?: run {
            Notifier.warn(ctx, "$title: $number", "Answer carefully. ${reasons.joinToString(" ")}", number, level)
            return
        }
        shown = wrap
        wm = manager
        main.postDelayed(autoHide, 60_000)
    }

    fun preview(ctx: Context) = show(
        ctx,
        mapOf(
            "number" to "+60 3-0000 0000 (sample)",
            "level" to "suspicious",
            "title" to "Suspicious caller",
            "reasons" to listOf("Wrong length for a Malaysian phone number. Caller IDs can be faked."),
        ),
        "",
    )

    fun dismiss() {
        main.removeCallbacks(autoHide)
        Overlays.remove(wm, shown)
        shown = null
        wm = null
    }

    /** Ends the ringing call when Android lets Kantoi (needs "Phone calls" permission). */
    @Suppress("DEPRECATION")
    private fun endCall(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 28) return false
        if (ctx.checkSelfPermission(Manifest.permission.ANSWER_PHONE_CALLS) != PackageManager.PERMISSION_GRANTED) return false
        return try {
            (ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager).endCall()
        } catch (e: Exception) {
            false
        }
    }
}
