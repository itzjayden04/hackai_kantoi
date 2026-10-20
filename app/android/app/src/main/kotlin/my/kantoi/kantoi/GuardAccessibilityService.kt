package my.kantoi.kantoi

import android.accessibilityservice.AccessibilityService
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Optional, turned on by the user. Two jobs:
 * 1. Reads the messages on screen in the open WhatsApp or Telegram chat (when
 *    a chat is open, those apps post no notification).
 * 2. Notices when a banking or e-wallet app opens soon after a risky chat and
 *    shows the "before you pay" pause card.
 * Screens of other apps are never read; only the app's name is used.
 */
class GuardAccessibilityService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    private var pendingScan: Runnable? = null
    private var lastPkg = ""
    private val seen = LinkedHashSet<String>()
    private val pausedFor = HashMap<String, Long>()

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!GuardEngine.isEnabled(this)) return
        val pkg = event.packageName?.toString() ?: return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && pkg != lastPkg) {
            lastPkg = pkg
            maybePauseBeforePaying(pkg)
        }
        if (pkg in chatScreens) {
            // Chats redraw constantly; read once things settle.
            pendingScan?.let { main.removeCallbacks(it) }
            val r = Runnable { scanChat(pkg) }
            pendingScan = r
            main.postDelayed(r, 1200)
        }
    }

    override fun onInterrupt() {}

    private fun maybePauseBeforePaying(pkg: String) {
        val since = System.currentTimeMillis() - GuardEngine.lastAlertAt
        if (GuardEngine.lastAlert == null || since > 30 * 60 * 1000) return
        val label = appLabel(pkg)
        if (!isPaymentApp(pkg, label)) return
        // Once per payment app per warning.
        if ((pausedFor[pkg] ?: 0L) >= GuardEngine.lastAlertAt) return
        pausedFor[pkg] = System.currentTimeMillis()
        PauseOverlay.showPaymentPause(this, label)
    }

    private fun scanChat(pkg: String) {
        val root = rootInActiveWindow ?: return
        if (root.packageName?.toString() != pkg) return
        val screen = Rect().also { root.getBoundsInScreen(it) }
        val chat = chatTitle(root, pkg) ?: return
        val texts = mutableListOf<Pair<String, Boolean>>()
        collect(root, screen.width(), texts, 0)
        // Newest messages are at the bottom; check only the last few new ones.
        for ((text, incoming) in texts.takeLast(6)) {
            val key = "$pkg|$chat|$text"
            if (!seen.add(key)) continue
            if (seen.size > 800) seen.remove(seen.first())
            val msg = mapOf<String, Any?>(
                "app" to pkg,
                "chat" to chat,
                "sender" to if (incoming) chat else "Me",
                "text" to text,
                "incoming" to incoming,
            )
            GuardEngine.check(this, msg) { GuardEngine.handle(this, it) }
        }
    }

    /** Message bubbles: text nodes that are not the typing box or buttons. */
    private fun collect(n: AccessibilityNodeInfo?, width: Int, out: MutableList<Pair<String, Boolean>>, depth: Int) {
        if (n == null || depth > 40) return
        val text = n.text?.toString()?.trim()
        if (text != null && text.length >= 12 && !n.isEditable && n.className?.toString()?.endsWith("TextView") == true) {
            val b = Rect().also { n.getBoundsInScreen(it) }
            // Incoming bubbles sit on the left, the user's own on the right.
            out.add(text to (b.centerX() < width / 2 || b.width() > width * 0.8))
        } else if (text == null) {
            val desc = n.contentDescription?.toString()?.trim()
            // Telegram draws messages itself and describes them for screen readers.
            if (desc != null && desc.length >= 12 && n.packageName?.toString()?.contains("telegram") == true && n.childCount == 0) {
                val b = Rect().also { n.getBoundsInScreen(it) }
                out.add(desc to (b.centerX() < width / 2 || b.width() > width * 0.8))
            }
        }
        for (i in 0 until n.childCount) collect(n.getChild(i), width, out, depth + 1)
    }

    private fun chatTitle(root: AccessibilityNodeInfo, pkg: String): String? {
        if (pkg.startsWith("com.whatsapp")) {
            root.findAccessibilityNodeInfosByViewId("$pkg:id/conversation_contact_name")?.firstOrNull()?.text?.let { return it.toString() }
            // No open conversation: the chat list, calls or status screen.
            return null
        }
        // Telegram has no stable ids; use the first short text at the top.
        val top = mutableListOf<String>()
        fun walk(n: AccessibilityNodeInfo?, d: Int) {
            if (n == null || d > 12 || top.isNotEmpty()) return
            val b = Rect().also { n.getBoundsInScreen(it) }
            val t = n.text?.toString()
            if (t != null && t.length in 2..40 && b.top < 300) top.add(t)
            for (i in 0 until n.childCount) walk(n.getChild(i), d + 1)
        }
        walk(root, 0)
        return top.firstOrNull()
    }

    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: PackageManager.NameNotFoundException) {
        pkg
    }

    private fun isPaymentApp(pkg: String, label: String): Boolean {
        val p = pkg.lowercase()
        val l = label.lowercase()
        return paymentWords.any { p.contains(it) } || paymentLabels.any { l.contains(it) }
    }

    companion object {
        private val chatScreens = setOf("com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger", "org.telegram.messenger.web")
        private val paymentWords = listOf(
            "bank", "maybank", "cimb", "rhb", "hongleong", "hlb", "publicbank", "ambank", "bsn", "affin", "alliance",
            "ocbc", "uob", "hsbc", "agrobank", "muamalat", "tngdigital", "touchngo", "shopeepay", "bigpay", "gxbank", "boost",
        )
        private val paymentLabels = listOf("bank", "maybank", "mae", "cimb", "octo", "rhb", "touch 'n go", "tng", "e-wallet", "ewallet", "duitnow", "boost", "shopeepay")
    }
}
