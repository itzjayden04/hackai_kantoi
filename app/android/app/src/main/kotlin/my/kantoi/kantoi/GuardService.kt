package my.kantoi.kantoi

import android.Manifest
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.provider.MediaStore

/**
 * "Kantoi is protecting this phone": a quiet foreground service that keeps
 * the checks running and hosts the two watchers that need a live process:
 * new apps (PACKAGE_ADDED) and new pictures (MediaStore).
 */
class GuardService : Service() {
    private var worker: HandlerThread? = null
    private var observer: ContentObserver? = null
    private var lastImageId = -1L

    private val packages = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            if (intent.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return
            val pkg = intent.data?.schemeSpecificPart ?: return
            if (pkg == packageName || !GuardEngine.guardOn(ctx, "apps")) return
            checkApp(pkg)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Shows "Kantoi is protecting this phone". Android requires this soon after
     * every startForegroundService() call, not only the first one, or it
     * stops the app, so both onCreate and onStartCommand call it.
     */
    private fun goForeground(): Boolean {
        val n = Notifier.running(this)
        return try {
            if (Build.VERSION.SDK_INT >= 34) {
                startForeground(Notifier.RUNNING_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(Notifier.RUNNING_ID, n)
            }
            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onCreate() {
        super.onCreate()
        if (!goForeground()) {
            // Android refused (e.g. started from the background); try again next time.
            stopSelf()
            return
        }
        running = true
        GuardEngine.warm(this)
        val f = IntentFilter(Intent.ACTION_PACKAGE_ADDED).apply { addDataScheme("package") }
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(packages, f, Context.RECEIVER_NOT_EXPORTED) else registerReceiver(packages, f)
        watchPictures()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Answer this start request first, even when about to stop.
        val ok = goForeground()
        if (!ok || !GuardEngine.isEnabled(this)) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (observer == null) watchPictures()
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        try {
            unregisterReceiver(packages)
        } catch (e: Exception) {
        }
        observer?.let { contentResolver.unregisterContentObserver(it) }
        observer = null
        worker?.quitSafely()
        super.onDestroy()
    }

    // ------------------------------------------------------------- new apps

    @Suppress("DEPRECATION")
    private fun checkApp(pkg: String) {
        val pm = packageManager
        val info: PackageInfo = try {
            pm.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES or PackageManager.GET_RECEIVERS)
        } catch (e: Exception) {
            return
        }
        val label = info.applicationInfo?.let { pm.getApplicationLabel(it).toString() } ?: pkg
        val installer = try {
            if (Build.VERSION.SDK_INT >= 30) pm.getInstallSourceInfo(pkg).installingPackageName else pm.getInstallerPackageName(pkg)
        } catch (e: Exception) {
            null
        }
        val facts = mapOf(
            "name" to label,
            "package" to pkg,
            "installer" to installer,
            "permissions" to (info.requestedPermissions?.toList() ?: emptyList()),
            "accessibility" to (info.services?.any { it.permission == Manifest.permission.BIND_ACCESSIBILITY_SERVICE } == true),
            "notificationListener" to (info.services?.any { it.permission == Manifest.permission.BIND_NOTIFICATION_LISTENER_SERVICE } == true),
            "deviceAdmin" to (info.receivers?.any { it.permission == Manifest.permission.BIND_DEVICE_ADMIN } == true),
        )
        val app = applicationContext
        GuardEngine.call(app, "checkApp", facts) { r ->
            if (r == null) return@call
            GuardEngine.count(app, "apps")
            val reasons = (r["reasons"] as? List<*>)?.map { it.toString() } ?: emptyList()
            if (r["warn"] == true) {
                GuardEngine.remember(app, mapOf(
                    "app" to pkg,
                    "chat" to label,
                    "level" to r["level"],
                    "label" to r["label"],
                    "headline" to r["headline"],
                    "reasons" to reasons,
                ), "app", label)
                Notifier.warn(app, "Careful: the new app \"$label\" may be a scam app",
                    "${r["headline"]}\n${reasons.joinToString(", ")}", label, r["level"]?.toString())
            } else {
                Notifier.warn(app, "Kantoi checked the new app \"$label\"",
                    "${r["headline"]}${if (reasons.isNotEmpty()) " " + reasons.joinToString(", ") else ""}", null, "safe")
            }
        }
    }

    // ------------------------------------------------------- new pictures

    private fun canReadPictures(): Boolean {
        val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        return Build.VERSION.SDK_INT < 23 || checkSelfPermission(perm) == PackageManager.PERMISSION_GRANTED
    }

    private fun watchPictures() {
        if (observer != null || !canReadPictures()) return
        val t = HandlerThread("kantoi-pictures").also { it.start() }
        worker = t
        val h = Handler(t.looper)
        val o = object : ContentObserver(h) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                h.removeCallbacksAndMessages(null)
                // A picture is written in steps; look once it settles.
                h.postDelayed({ checkNewestPicture() }, 1500)
            }
        }
        try {
            contentResolver.registerContentObserver(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true, o)
            observer = o
        } catch (e: Exception) {
        }
    }

    private fun checkNewestPicture() {
        if (!GuardEngine.guardOn(this, "photos") || !canReadPictures()) return
        val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val cols = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_ADDED, MediaStore.Images.Media.SIZE)
        val newest = try {
            contentResolver.query(uri, cols, null, null, "${MediaStore.Images.Media.DATE_ADDED} DESC")?.use { c ->
                if (!c.moveToFirst()) null else Triple(c.getLong(0), c.getLong(1), c.getLong(2))
            }
        } catch (e: Exception) {
            null
        } ?: return
        val (id, added, size) = newest
        // Only pictures from the last minute, each once, and not huge ones.
        if (id == lastImageId || System.currentTimeMillis() / 1000 - added > 60 || size > 15L * 1024 * 1024) return
        lastImageId = id
        val bytes = try {
            contentResolver.openInputStream(ContentUris.withAppendedId(uri, id))?.use { it.readBytes() }
        } catch (e: Exception) {
            null
        } ?: return
        val app = applicationContext
        GuardEngine.call(app, "checkImage", mapOf("bytes" to bytes)) { r ->
            if (r == null) return@call
            val qr = r["qr"]?.toString() ?: return@call
            val site = r["site"] as? Map<*, *> ?: return@call
            if (site["block"] != true) return@call
            val host = site["host"]?.toString() ?: qr
            GuardEngine.count(app, "photos")
            GuardEngine.remember(app, mapOf(
                "app" to "photo",
                "chat" to host,
                "level" to site["level"],
                "label" to site["label"],
                "headline" to site["headline"],
                "reasons" to site["reasons"],
                "text" to qr,
            ), "photo", qr)
            Notifier.warn(app, "Scam link in a QR code", "A new picture has a QR code that leads to $host. ${site["headline"] ?: ""} Don't scan it or pay.",
                qr, site["level"]?.toString())
        }
    }

    companion object {
        /** True while the service is up, so opening the app does not start it again. */
        @Volatile
        var running = false

        fun start(ctx: Context) {
            if (running) return
            val i = Intent(ctx, GuardService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
            } catch (e: Exception) {
                // Not allowed from the background right now; the next app start or boot retries.
            }
        }

        fun stop(ctx: Context) {
            try {
                ctx.stopService(Intent(ctx, GuardService::class.java))
            } catch (e: Exception) {
            }
        }
    }
}
