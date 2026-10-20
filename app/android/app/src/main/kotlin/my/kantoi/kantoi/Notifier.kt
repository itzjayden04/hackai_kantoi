package my.kantoi.kantoi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** Kantoi's notifications: one per warning, plus the quiet "protecting" one. */
object Notifier {
    const val ALERTS = "kantoi_alerts"
    const val RUNNING = "kantoi_running"
    const val EXTRA_TRACE = "kantoi_open_trace"
    const val RUNNING_ID = 4700
    private var nextId = 4800

    fun channels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(ALERTS, "Scam warnings", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Tells you when a message, call, website, app or picture looks like a scam."
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(RUNNING, "Protection running", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows that Kantoi is protecting this phone."
                setShowBadge(false)
            },
        )
    }

    @Suppress("DEPRECATION")
    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel) else Notification.Builder(ctx)

    /** Opens Kantoi; with [target] set, Kantoi traces that link, number or message. */
    fun openApp(ctx: Context, target: String?, requestCode: Int): PendingIntent {
        val i = Intent(ctx, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            if (!target.isNullOrBlank()) putExtra(EXTRA_TRACE, target)
        }
        return PendingIntent.getActivity(ctx, requestCode, i, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    /** A warning. Tapping it opens Kantoi on [target]. */
    @Suppress("DEPRECATION")
    fun warn(ctx: Context, title: String, body: String, target: String?, level: String? = "danger") {
        val app = ctx.applicationContext
        channels(app)
        val id = nextId++
        if (nextId > 4999) nextId = 4800
        val n = builder(app, ALERTS)
            .setSmallIcon(R.drawable.ic_kantoi_shield)
            .setColor(KColor.forLevel(level))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(openApp(app, target, id))
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setAutoCancel(true)
            .apply { if (Build.VERSION.SDK_INT < 26) setPriority(Notification.PRIORITY_HIGH) }
            .build()
        try {
            (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).notify(id, n)
        } catch (e: SecurityException) {
        }
    }

    /** The persistent, low-key notification of the protection service. */
    @Suppress("DEPRECATION")
    fun running(ctx: Context): Notification {
        channels(ctx)
        return builder(ctx, RUNNING)
            .setSmallIcon(R.drawable.ic_kantoi_shield)
            .setColor(KColor.primaryContainer)
            .setContentTitle("Kantoi is protecting this phone")
            .setContentText("Checking calls, messages, websites, new apps and pictures.")
            .setContentIntent(openApp(ctx, null, RUNNING_ID))
            .setOngoing(true)
            .setShowWhen(false)
            .apply { if (Build.VERSION.SDK_INT < 26) setPriority(Notification.PRIORITY_MIN) }
            .build()
    }
}
