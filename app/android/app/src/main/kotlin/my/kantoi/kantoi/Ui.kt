package my.kantoi.kantoi

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

/** The app's design tokens (K in theme.dart), for the native warning cards. */
object KColor {
    val primary = Color.parseColor("#00236F")
    val primaryContainer = Color.parseColor("#1E3A8A")
    val surface = Color.parseColor("#F8F9FF")
    val surfaceLow = Color.parseColor("#EFF4FF")
    val surfaceMid = Color.parseColor("#E5EEFF")
    val surfaceHigh = Color.parseColor("#DCE9FF")
    val onSurface = Color.parseColor("#0B1C30")
    val onSurfaceVariant = Color.parseColor("#444651")
    val outlineVariant = Color.parseColor("#C5C5D3")
    val error = Color.parseColor("#BA1A1A")
    val errorContainer = Color.parseColor("#FFDAD6")
    val onErrorContainer = Color.parseColor("#93000A")
    val red = Color.parseColor("#DC2626")
    val orange = Color.parseColor("#EA580C")
    val amber = Color.parseColor("#D97706")
    val green = Color.parseColor("#15803D")
    val night = Color.parseColor("#0B1220")
    val nightCard = Color.parseColor("#131C2E")
    val scrim = Color.parseColor("#B30B1C30")

    fun forLevel(level: String?) = when (level) {
        "danger" -> red
        "suspicious" -> orange
        "caution" -> amber
        else -> green
    }

    fun withAlpha(c: Int, a: Float) = Color.argb((a * 255).toInt(), Color.red(c), Color.green(c), Color.blue(c))
}

/** Small helpers so each native card reads like its Stitch layout. */
class Ui(val ctx: Context) {
    fun dp(v: Int) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v.toFloat(), ctx.resources.displayMetrics).toInt()

    fun text(s: String, size: Float, color: Int, weight: Int = 400, center: Boolean = false) = TextView(ctx).apply {
        text = s
        textSize = size
        setTextColor(color)
        typeface = when {
            weight >= 700 -> Typeface.DEFAULT_BOLD
            weight >= 500 && Build.VERSION.SDK_INT >= 28 -> Typeface.create(Typeface.DEFAULT, 600, false)
            weight >= 500 -> Typeface.DEFAULT_BOLD
            else -> Typeface.DEFAULT
        }
        setLineSpacing(0f, 1.2f)
        if (center) gravity = Gravity.CENTER_HORIZONTAL
    }

    fun round(color: Int, radius: Int, stroke: Int? = null, strokeWidth: Int = 1) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(radius).toFloat()
        if (stroke != null) setStroke(dp(strokeWidth), stroke)
    }

    fun column(pad: Int = 0) = LinearLayout(ctx).apply {
        orientation = LinearLayout.VERTICAL
        setPadding(dp(pad), dp(pad), dp(pad), dp(pad))
    }

    fun row() = LinearLayout(ctx).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }

    /** A pill like Pill in kit.dart: dot + upper-case label. */
    fun pill(label: String, color: Int, bg: Int) = TextView(ctx).apply {
        text = "●  ${label.uppercase()}"
        textSize = 12f
        letterSpacing = 0.04f
        setTextColor(color)
        typeface = Typeface.DEFAULT_BOLD
        setPadding(dp(12), dp(6), dp(12), dp(6))
        background = round(bg, 100)
    }

    /** A filled or tonal button, 52dp tall like the app's FilledButton. */
    fun button(label: String, fg: Int, bg: Int, stroke: Int? = null) = TextView(ctx).apply {
        text = label
        textSize = 16f
        gravity = Gravity.CENTER
        setTextColor(fg)
        typeface = Typeface.DEFAULT_BOLD
        background = round(bg, 14, stroke)
        isClickable = true
        isFocusable = true
    }

    /** A reason card: tinted icon square + title (+ detail). */
    fun reason(icon: String, title: String, detail: String?, tint: Int, bg: Int): View {
        val r = row().apply {
            gravity = Gravity.TOP
            setPadding(dp(14), dp(12), dp(14), dp(12))
            background = round(bg, 14)
        }
        r.addView(text(icon, 16f, tint, 700, center = true).apply {
            gravity = Gravity.CENTER
            background = round(KColor.withAlpha(tint, 0.14f), 10)
        }, LinearLayout.LayoutParams(dp(34), dp(34)))
        val col = column()
        col.addView(text(title, 16f, KColor.onSurface, 600))
        if (!detail.isNullOrBlank()) col.addView(text(detail, 14f, KColor.onSurfaceVariant))
        r.addView(col, LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(12) })
        return r
    }

    fun lp(w: Int = -1, h: Int = -2, top: Int = 0) = LinearLayout.LayoutParams(w, h).apply { topMargin = dp(top) }
}

/** A countdown ring drawn around the "Continue" label of the pause card. */
class RingView(ctx: Context, private val color: Int, private val track: Int) : View(ctx) {
    var progress = 0f
        set(v) {
            field = v
            invalidate()
        }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
    }

    override fun onDraw(canvas: Canvas) {
        val w = width.coerceAtMost(height).toFloat()
        val stroke = w * 0.12f
        paint.strokeWidth = stroke
        val r = RectF(stroke, stroke, w - stroke, w - stroke)
        paint.color = track
        canvas.drawArc(r, 0f, 360f, false, paint)
        paint.color = color
        canvas.drawArc(r, -90f, 360f * progress, false, paint)
    }
}

/**
 * Puts Kantoi's cards on top of other apps. Inside the accessibility service
 * the card uses the service's own layer (no extra permission needed);
 * elsewhere it needs "Display over other apps".
 */
object Overlays {
    /** The running accessibility service, if the user turned it on. */
    @Volatile
    var service: AccessibilityService? = null

    fun canShow(ctx: Context) = service != null || ctx is AccessibilityService ||
        Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(ctx)

    /** Adds [view]; returns the WindowManager to remove it with, or null. */
    fun add(ctx: Context, view: View, full: Boolean, gravity: Int = Gravity.CENTER, wide: Boolean = false): WindowManager? {
        val overlayOk = Build.VERSION.SDK_INT < 23 || Settings.canDrawOverlays(ctx)
        val a11y: AccessibilityService? = (ctx as? AccessibilityService) ?: if (overlayOk) null else service
        val host: Context = a11y ?: ctx.applicationContext
        if (a11y == null && !overlayOk) return null
        val type = when {
            a11y != null -> WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY
            Build.VERSION.SDK_INT >= 26 -> WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else -> {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
        }
        val match = WindowManager.LayoutParams.MATCH_PARENT
        val wrap = WindowManager.LayoutParams.WRAP_CONTENT
        var flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
        if (!full) flags = flags or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
        val lp = WindowManager.LayoutParams(if (full || wide) match else wrap, if (full) match else wrap, type, flags, PixelFormat.TRANSLUCENT)
        lp.gravity = gravity
        val wm = host.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        return try {
            wm.addView(view, lp)
            wm
        } catch (e: Exception) {
            null
        }
    }

    fun remove(wm: WindowManager?, view: View?) {
        if (wm == null || view == null) return
        try {
            wm.removeView(view)
        } catch (e: Exception) {
        }
    }

    /** Wraps a card in a dimmed, scrollable full-screen layer. */
    fun scrim(ui: Ui, card: View, top: View? = null): FrameLayout {
        val root = FrameLayout(ui.ctx).apply { setBackgroundColor(KColor.scrim) }
        val inner = ui.column().apply {
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(ui.dp(18), ui.dp(36), ui.dp(18), ui.dp(24))
        }
        if (top != null) inner.addView(top, LinearLayout.LayoutParams(-2, -2).apply { gravity = Gravity.CENTER_HORIZONTAL })
        inner.addView(card, LinearLayout.LayoutParams(-1, -2))
        val scroll = android.widget.ScrollView(ui.ctx).apply {
            isFillViewport = true
            addView(FrameLayout(ui.ctx).apply { addView(inner, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER)) })
        }
        root.addView(scroll, FrameLayout.LayoutParams(-1, -1))
        return root
    }
}
