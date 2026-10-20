package my.kantoi.kantoi

import android.animation.ValueAnimator
import android.content.Context
import android.content.Intent
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.LinearLayout

/**
 * The pause card (Stitch "pause-card"): a calm full-screen card drawn over the
 * chat or payment app when Kantoi sees a likely scam. "Continue" unlocks after
 * a 5-second ring. If Kantoi can't draw over other apps, the warning
 * notification (always posted) is all the user sees.
 */
object PauseOverlay {
    private var shown: View? = null
    private var wm: WindowManager? = null
    private var ring: ValueAnimator? = null

    /** Warning about a message or chat that looks like a scam. */
    fun showWarning(ctx: Context, r: Map<*, *>) {
        val chat = r["chat"]?.toString().orEmpty()
        val text = r["text"]?.toString().orEmpty()
        show(
            ctx,
            level = r["level"]?.toString() ?: "suspicious",
            tag = r["scamType"]?.toString() ?: r["label"]?.toString() ?: "Suspicious",
            title = "Pause. This looks like a scam.",
            body = listOf(
                if (chat.isNotBlank()) "From your chat with $chat." else "",
                r["headline"]?.toString().orEmpty(),
            ).filter { it.isNotBlank() }.joinToString(" "),
            reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList(),
            next = r["nextStep"]?.toString(),
            primary = "Stop and check in Kantoi" to { openKantoi(ctx, text) },
        )
    }

    /** Shown when a banking or e-wallet app opens soon after a risky chat. */
    fun showPaymentPause(ctx: Context, appLabel: String) {
        val r = GuardEngine.lastAlert ?: return
        val chat = r["chat"]?.toString().orEmpty()
        if (!Overlays.canShow(ctx)) {
            Notifier.warn(ctx, "Wait. Are you about to send money?", "You opened $appLabel soon after a risky chat. Talk to someone you trust first.", null)
            return
        }
        show(
            ctx,
            level = "danger",
            tag = "Before you pay",
            title = "Wait. Are you about to send money?",
            body = "You opened $appLabel soon after a chat${if (chat.isNotBlank()) " with $chat" else ""} that Kantoi flagged as " +
                "\"${r["label"] ?: "suspicious"}\". Scammers rush you so you don't stop to check.",
            reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList(),
            next = "Talk to someone you trust first. If you already paid, call your bank and the NSRC on 997 now.",
            primary = "Don't pay, go back" to { goHome(ctx) },
        )
    }

    /** A sample card so the user sees what it looks like. */
    fun preview(ctx: Context) = showWarning(
        ctx,
        mapOf(
            "level" to "danger",
            "label" to "Very likely a scam",
            "scamType" to "Investment scam (sample)",
            "chat" to "Amanda",
            "headline" to "This follows the pattern of an investment scam: a stranger, fast friendship, then a \"sure profit\" and a transfer.",
            "reasons" to listOf("Started with a \"wrong number\" message", "Unrealistic returns", "Money came up fast"),
            "nextStep" to "Don't send money. Ask for a live video call and talk to someone you trust.",
            "text" to "My uncle is a crypto trader. Guaranteed 30% profit every week. Transfer RM5000 to start today.",
        ),
    )

    private fun show(
        ctx: Context,
        level: String,
        tag: String,
        title: String,
        body: String,
        reasons: List<String>,
        next: String?,
        primary: Pair<String, () -> Unit>,
    ) {
        if (!Overlays.canShow(ctx)) return
        dismiss()
        val app = ctx.applicationContext
        val ui = Ui(app)
        val accent = if (level == "danger") KColor.red else KColor.orange

        val card = ui.column().apply {
            setPadding(ui.dp(22), ui.dp(26), ui.dp(22), ui.dp(18))
            background = android.graphics.drawable.LayerDrawable(
                arrayOf<android.graphics.drawable.Drawable>(ui.round(accent, 24), ui.round(android.graphics.Color.WHITE, 24)),
            ).apply { setLayerInset(1, 0, ui.dp(5), 0, 0) }
        }
        card.addView(ui.text(title, 26f, KColor.onSurface, 700, center = true))
        if (body.isNotBlank()) card.addView(ui.text(body, 15f, KColor.onSurfaceVariant, center = true), ui.lp(top = 8))
        for (r in reasons.take(3)) card.addView(ui.reason("!", r, null, accent, KColor.surfaceLow), ui.lp(top = 10))
        if (!next.isNullOrBlank()) {
            card.addView(ui.row().apply {
                setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12))
                background = ui.round(KColor.surfaceHigh, 14)
                addView(ui.text("✓", 16f, KColor.primaryContainer, 700))
                addView(ui.text(next, 15f, KColor.primaryContainer, 600), LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = ui.dp(10) })
            }, ui.lp(top = 14))
        }

        val stop = ui.button(primary.first, android.graphics.Color.WHITE, KColor.primaryContainer)
        card.addView(stop, ui.lp(h = ui.dp(54), top = 18))

        // "Continue" with a ring that fills over 5 seconds before it unlocks.
        val ringView = RingView(app, KColor.primaryContainer, KColor.outlineVariant)
        val label = ui.text("Continue", 15f, KColor.onSurfaceVariant, 600)
        val cont = ui.row().apply {
            gravity = Gravity.CENTER
            background = ui.round(KColor.surfaceLow, 100)
            addView(ringView, LinearLayout.LayoutParams(ui.dp(20), ui.dp(20)))
            addView(label, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(10) })
            isEnabled = false
            alpha = 0.7f
        }
        card.addView(cont, ui.lp(h = ui.dp(50), top = 8))
        card.addView(ui.text("Kantoi checked this on your phone. Nothing was sent or paid.", 13f, KColor.onSurfaceVariant, center = true), ui.lp(top = 12))

        // The hand badge and the scam-type pill sit above the card.
        val top = ui.column().apply { gravity = Gravity.CENTER_HORIZONTAL }
        top.addView(ui.text("✋", 30f, android.graphics.Color.WHITE, center = true).apply {
            gravity = Gravity.CENTER
            background = ui.round(accent, 100)
            elevation = ui.dp(6).toFloat()
        }, LinearLayout.LayoutParams(ui.dp(72), ui.dp(72)).apply { gravity = Gravity.CENTER_HORIZONTAL })
        top.addView(ui.pill(tag, KColor.onErrorContainer, KColor.errorContainer), LinearLayout.LayoutParams(-2, -2).apply {
            gravity = Gravity.CENTER_HORIZONTAL
            topMargin = ui.dp(10)
            bottomMargin = ui.dp(12)
        })
        val root: FrameLayout = Overlays.scrim(ui, card, top)

        stop.setOnClickListener {
            dismiss()
            primary.second()
        }
        cont.setOnClickListener { if (cont.isEnabled) dismiss() }

        val manager = Overlays.add(ctx, root, full = true) ?: return
        shown = root
        wm = manager
        ring = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 5000
            interpolator = LinearInterpolator()
            addUpdateListener {
                val v = it.animatedValue as Float
                ringView.progress = v
                label.text = if (v < 1f) "Continue in ${5 - (v * 5).toInt()}s" else "Continue"
            }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                override fun onAnimationEnd(animation: android.animation.Animator) {
                    cont.isEnabled = true
                    cont.alpha = 1f
                    ringView.visibility = View.GONE
                    label.text = "Continue"
                    label.setTextColor(KColor.onSurface)
                }
            })
            start()
        }
    }

    fun dismiss() {
        ring?.removeAllListeners()
        ring?.cancel()
        ring = null
        Overlays.remove(wm, shown)
        shown = null
        wm = null
    }

    /** Opens Kantoi and runs the full check of the message. */
    private fun openKantoi(ctx: Context, text: String) {
        val i = Intent(ctx.applicationContext, MainActivity::class.java).apply {
            action = Intent.ACTION_SEND
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        ctx.applicationContext.startActivity(i)
    }

    fun goHome(ctx: Context) {
        val i = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ctx.applicationContext.startActivity(i)
    }
}
