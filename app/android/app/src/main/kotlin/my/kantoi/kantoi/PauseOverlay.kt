package my.kantoi.kantoi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.CountDownTimer
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * The pause card: a calm full-screen card drawn over the chat or payment app
 * when Kantoi sees a likely scam. If Android doesn't allow drawing over other
 * apps, a notification is shown instead.
 */
object PauseOverlay {
    private var shown: View? = null
    private var timer: CountDownTimer? = null

    private const val RED = "#DC2626"
    private const val ORANGE = "#EA580C"
    private const val BRAND = "#1E3A8A"

    /** Warning about a message or chat that looks like a scam. */
    fun showWarning(ctx: Context, r: Map<*, *>) {
        val danger = r["level"] == "danger"
        val chat = r["chat"]?.toString().orEmpty()
        val reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList()
        val text = r["text"]?.toString().orEmpty()
        show(
            ctx,
            accent = if (danger) RED else ORANGE,
            badge = "Kantoi · ${r["label"] ?: "Suspicious"}",
            title = if (chat.isNotBlank()) "Pause. This chat with $chat looks like a scam." else "Pause. This message looks like a scam.",
            body = r["headline"]?.toString().orEmpty(),
            reasons = reasons,
            next = r["nextStep"]?.toString(),
            primary = "See why" to { openKantoi(ctx, text) },
            secondary = "I'll be careful",
            waitSeconds = if (danger) 5 else 0,
        )
    }

    /** Shown when a banking or e-wallet app opens soon after a risky chat. */
    fun showPaymentPause(ctx: Context, appLabel: String) {
        val r = GuardEngine.lastAlert ?: return
        val chat = r["chat"]?.toString().orEmpty()
        val reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList()
        show(
            ctx,
            accent = RED,
            badge = "Kantoi · Before you pay",
            title = "Wait. Are you about to send money?",
            body = "You opened $appLabel soon after a chat${if (chat.isNotBlank()) " with $chat" else ""} that Kantoi flagged as " +
                "${r["label"] ?: "suspicious"}. Scammers rush you so you don't stop to check.",
            reasons = reasons,
            next = "Talk to someone you trust first. If you already paid, call your bank and the NSRC on 997 now.",
            primary = "Don't pay, go back" to { goHome(ctx) },
            secondary = "Continue",
            waitSeconds = 10,
        )
    }

    /** A sample card so the user sees what it looks like. */
    fun preview(ctx: Context) = showWarning(
        ctx,
        mapOf(
            "level" to "danger",
            "label" to "Very likely a scam",
            "chat" to "Amanda",
            "headline" to "This follows the pattern of an investment scam: a stranger, fast friendship, then a \"sure profit\" and a transfer.",
            "reasons" to listOf("Started with a \"wrong number\" message", "Unrealistic returns", "Money came up fast"),
            "nextStep" to "Don't send money. Ask for a live video call and talk to someone you trust.",
            "text" to "My uncle is a crypto trader. Guaranteed 30% profit every week. Transfer RM5000 to start today.",
        ),
    )

    private fun show(
        ctx: Context,
        accent: String,
        badge: String,
        title: String,
        body: String,
        reasons: List<String>,
        next: String?,
        primary: Pair<String, () -> Unit>,
        secondary: String,
        waitSeconds: Int,
    ) {
        if (Build.VERSION.SDK_INT >= 23 && !Settings.canDrawOverlays(ctx)) {
            notify(ctx, title, listOf(body, reasons.joinToString(", ")).filter { it.isNotBlank() }.joinToString("\n"))
            return
        }
        dismiss(ctx)
        val app = ctx.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), app.resources.displayMetrics).toInt()
        fun label(s: String, size: Float, color: String, bold: Boolean = false) = TextView(app).apply {
            text = s
            textSize = size
            setTextColor(Color.parseColor(color))
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setLineSpacing(0f, 1.15f)
        }

        val card = LinearLayout(app).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(20), dp(22), dp(18))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadius = dp(22).toFloat()
                setStroke(dp(3), Color.parseColor(accent))
            }
        }
        card.addView(label(badge.uppercase(), 12f, accent, bold = true))
        card.addView(label(title, 21f, "#0F172A", bold = true).apply { setPadding(0, dp(6), 0, dp(8)) })
        if (body.isNotBlank()) card.addView(label(body, 15f, "#334155"))
        if (reasons.isNotEmpty()) {
            card.addView(label("Warning signs", 13f, "#64748B", bold = true).apply { setPadding(0, dp(12), 0, dp(2)) })
            for (r in reasons.take(3)) card.addView(label("•  $r", 15f, "#0F172A"))
        }
        if (!next.isNullOrBlank()) {
            card.addView(label(next, 15f, BRAND, bold = true).apply {
                setPadding(dp(12), dp(10), dp(12), dp(10))
                background = GradientDrawable().apply {
                    setColor(Color.parseColor("#EEF2FF"))
                    cornerRadius = dp(12).toFloat()
                }
            }, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(14) })
        }

        val first = Button(app).apply {
            text = primary.first
            isAllCaps = false
            textSize = 16f
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                setColor(Color.parseColor(accent))
                cornerRadius = dp(14).toFloat()
            }
        }
        val second = Button(app).apply {
            isAllCaps = false
            textSize = 15f
            setTextColor(Color.parseColor("#334155"))
            background = GradientDrawable().apply {
                setColor(Color.parseColor("#F1F5F9"))
                cornerRadius = dp(14).toFloat()
            }
        }
        card.addView(first, LinearLayout.LayoutParams(-1, dp(52)).apply { topMargin = dp(18) })
        card.addView(second, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(8) })

        val root = FrameLayout(app).apply {
            setBackgroundColor(Color.parseColor("#B30F172A"))
            val scroll = ScrollView(app).apply {
                isFillViewport = true
                addView(FrameLayout(app).apply {
                    setPadding(dp(18), dp(24), dp(18), dp(24))
                    addView(card, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
                })
            }
            addView(scroll, FrameLayout.LayoutParams(-1, -1))
        }

        first.setOnClickListener {
            dismiss(app)
            primary.second()
        }
        second.setOnClickListener { dismiss(app) }

        // A short, visible wait is the point of a pause card.
        if (waitSeconds > 0) {
            second.isEnabled = false
            second.alpha = 0.6f
            timer = object : CountDownTimer(waitSeconds * 1000L, 1000L) {
                override fun onTick(left: Long) {
                    second.text = "$secondary (${(left / 1000) + 1})"
                }

                override fun onFinish() {
                    second.text = secondary
                    second.isEnabled = true
                    second.alpha = 1f
                }
            }.start()
        } else {
            second.text = secondary
        }

        val type = if (Build.VERSION.SDK_INT >= 26) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        )
        try {
            wm.addView(root, lp)
            shown = root
        } catch (e: Exception) {
            notify(ctx, title, body)
        }
    }

    fun dismiss(ctx: Context) {
        timer?.cancel()
        timer = null
        val v = shown ?: return
        shown = null
        try {
            (ctx.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager).removeView(v)
        } catch (e: Exception) {
        }
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

    private fun goHome(ctx: Context) {
        val i = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        ctx.applicationContext.startActivity(i)
    }

    private fun notify(ctx: Context, title: String, body: String) {
        val app = ctx.applicationContext
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel("kantoi_alerts", "Scam warnings", NotificationManager.IMPORTANCE_HIGH))
        }
        val open = PendingIntent.getActivity(
            app, 0, Intent(app, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(app, "kantoi_alerts") else {
            @Suppress("DEPRECATION")
            Notification.Builder(app)
        }
        val n = b.setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(4721, n)
        } catch (e: SecurityException) {
        }
    }
}
