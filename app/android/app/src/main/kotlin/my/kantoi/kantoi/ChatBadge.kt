package my.kantoi.kantoi

import android.content.Context
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout

/**
 * The floating risk badge on an open WhatsApp, Telegram or Messenger chat
 * (Stitch "chat-badge"). It shows the relationship check of the chat, run on
 * the messages Kantoi has seen; tapping it opens the reasons.
 */
object ChatBadge {
    private var badge: View? = null
    private var badgeWm: WindowManager? = null
    private var panel: View? = null
    private var panelWm: WindowManager? = null
    private var current: Map<*, *>? = null

    /** The chat the badge is showing, "app|chat". */
    var showingFor: String? = null
        private set

    fun show(ctx: Context, r: Map<*, *>) {
        val key = "${r["app"]}|${r["chat"]}"
        val same = key == showingFor && r["level"] == current?.get("level") && r["score"] == current?.get("score")
        current = r
        if (same && badge != null) return
        removeBadge()
        val app = ctx.applicationContext
        val ui = Ui(app)
        val level = r["level"]?.toString() ?: "safe"
        val color = KColor.forLevel(level)
        val label = if (level == "safe") "No scam signs yet" else r["label"]?.toString() ?: "Be careful"
        val pill = ui.row().apply {
            setPadding(ui.dp(12), ui.dp(7), ui.dp(14), ui.dp(7))
            background = ui.round(KColor.primaryContainer, 100, KColor.withAlpha(Color.WHITE, 0.25f))
            elevation = ui.dp(4).toFloat()
            addView(ui.text("🛡", 13f, Color.WHITE))
            addView(ui.text("Kantoi", 13f, Color.WHITE, 700), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(6) })
            addView(ui.text("●", 12f, color), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(8) })
            addView(ui.text(label, 13f, Color.WHITE, 600), LinearLayout.LayoutParams(-2, -2).apply { leftMargin = ui.dp(4) })
            setOnClickListener { current?.let { expand(ctx, it) } }
        }
        val wrap = FrameLayout(app).apply {
            setPadding(0, ui.dp(64), 0, 0)
            addView(pill)
        }
        badgeWm = Overlays.add(ctx, wrap, full = false, gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL) ?: return
        badge = wrap
        showingFor = key
    }

    private fun expand(ctx: Context, r: Map<*, *>) {
        removePanel()
        val app = ctx.applicationContext
        val ui = Ui(app)
        val level = r["level"]?.toString() ?: "safe"
        val color = KColor.forLevel(level)
        val card = ui.column(18).apply { background = ui.round(Color.WHITE, 24) }

        val head = ui.row()
        head.addView(ui.text(r["chat"]?.toString() ?: "This chat", 20f, KColor.onSurface, 700), LinearLayout.LayoutParams(0, -2, 1f))
        head.addView(ui.text("${r["score"] ?: 0} / 100", 14f, Color.WHITE, 700).apply {
            setPadding(ui.dp(12), ui.dp(5), ui.dp(12), ui.dp(5))
            background = ui.round(color, 100)
        })
        card.addView(head)
        card.addView(ui.text("Relationship risk · ${r["label"] ?: ""}", 13f, KColor.onSurfaceVariant, 600), ui.lp(top = 2))

        val pattern = r["pattern"]?.toString()
        card.addView(ui.column(14).apply {
            background = ui.round(if (level == "safe") KColor.surfaceLow else KColor.errorContainer, 14)
            if (!pattern.isNullOrBlank()) addView(ui.text(pattern, 15f, KColor.onErrorContainer, 700))
            addView(ui.text(r["headline"]?.toString().orEmpty(), 14f, if (level == "safe") KColor.onSurface else KColor.onErrorContainer))
        }, ui.lp(top = 12))

        val signals = (r["signals"] as? List<*>)?.mapNotNull { it as? Map<*, *> } ?: emptyList()
        if (signals.isNotEmpty()) {
            card.addView(ui.text("WHAT KANTOI NOTICED", 11f, KColor.onSurfaceVariant, 700), ui.lp(top = 14))
            for (s in signals) {
                card.addView(ui.reason("!", s["title"]?.toString().orEmpty(), s["detail"]?.toString(), color, KColor.surfaceLow), ui.lp(top = 8))
            }
        }
        val next = r["nextStep"]?.toString()
        if (!next.isNullOrBlank()) {
            card.addView(ui.text("✓  $next", 14f, KColor.primaryContainer, 600).apply {
                setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12))
                background = ui.round(KColor.surfaceHigh, 14)
            }, ui.lp(top = 12))
        }
        val close = ui.button("Close", Color.WHITE, KColor.primaryContainer)
        card.addView(close, ui.lp(h = ui.dp(50), top = 14))
        card.addView(ui.text("🔒  Based on ${r["messages"] ?: 0} messages Kantoi saw in this chat, checked on this phone.", 12f,
            KColor.onSurfaceVariant, center = true), ui.lp(top = 10))

        val root = Overlays.scrim(ui, card)
        root.setOnClickListener { removePanel() }
        card.isClickable = true
        close.setOnClickListener { removePanel() }
        panelWm = Overlays.add(ctx, root, full = true) ?: return
        panel = root
    }

    /** The opened badge, as a sample (closes with its button). */
    fun preview(ctx: Context) = expand(
        ctx,
        mapOf(
            "app" to "preview",
            "chat" to "Amanda (sample)",
            "level" to "suspicious",
            "label" to "Suspicious",
            "score" to 62,
            "pattern" to "Investment scam",
            "headline" to "This chat follows the pattern of an investment scam.",
            "nextStep" to "Don't send money. Ask for a live video call.",
            "messages" to 6,
            "signals" to listOf(
                mapOf("title" to "Started with a \"wrong number\" message", "detail" to "Many investment scams open this way."),
                mapOf("title" to "Unrealistic returns", "detail" to "\"Guaranteed 30% profit every week\""),
            ),
        ),
    )

    private fun removeBadge() {
        Overlays.remove(badgeWm, badge)
        badge = null
        badgeWm = null
        showingFor = null
    }

    private fun removePanel() {
        Overlays.remove(panelWm, panel)
        panel = null
        panelWm = null
    }

    fun hide() {
        removeBadge()
        removePanel()
        current = null
    }
}
