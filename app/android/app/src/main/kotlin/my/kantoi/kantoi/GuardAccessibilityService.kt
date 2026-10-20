package my.kantoi.kantoi

import android.accessibilityservice.AccessibilityService
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Optional, turned on by the user. Jobs:
 * 1. Chats on screen: reads the messages in the open WhatsApp, Telegram or
 *    Messenger chat (an open chat posts no notification), and shows the
 *    floating risk badge with the chat's relationship check.
 * 2. Web & link blocker: reads the address bar of known browsers and closes
 *    scam websites.
 * 3. Notices when a banking or e-wallet app opens soon after a risky chat and
 *    shows the "before you pay" pause card.
 * Screens of other apps are never read; only the app's name is used.
 */
class GuardAccessibilityService : AccessibilityService() {
    private val main = Handler(Looper.getMainLooper())
    private var pendingScan: Runnable? = null
    private var pendingUrl: Runnable? = null
    private var lastPkg = ""
    private val seen = LinkedHashSet<String>()
    private val pausedFor = HashMap<String, Long>()

    /** Address-bar text -> (checked at, verdict). */
    private val verdicts = LinkedHashMap<String, Pair<Long, Map<*, *>?>>()
    private var lastBlocked = ""
    private var lastBlockedAt = 0L

    override fun onServiceConnected() {
        super.onServiceConnected()
        Overlays.service = this
        if (GuardEngine.isEnabled(this)) GuardEngine.warm(this)
    }

    override fun onDestroy() {
        if (Overlays.service === this) Overlays.service = null
        ChatBadge.hide()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (!GuardEngine.isEnabled(this)) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName || pkg == "com.android.systemui" || pkg.contains("inputmethod") || pkg.contains("keyboard")) return
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED && pkg != lastPkg) {
            lastPkg = pkg
            if (pkg !in chatScreens) ChatBadge.hide()
            maybePauseBeforePaying(pkg)
        }
        if (pkg in chatScreens && GuardEngine.guardOn(this, "chats")) {
            // Chats redraw constantly; read once things settle.
            pendingScan?.let { main.removeCallbacks(it) }
            val r = Runnable { scanChat(pkg) }
            pendingScan = r
            main.postDelayed(r, 1200)
        } else if (pkg in browsers || isBrowserLike(event)) {
            if (!GuardEngine.guardOn(this, "web")) return
            pendingUrl?.let { main.removeCallbacks(it) }
            val r = Runnable { scanAddressBar(pkg) }
            pendingUrl = r
            main.postDelayed(r, 600)
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

    // ---------------------------------------------------------------- chats

    private fun scanChat(pkg: String) {
        val root = rootInActiveWindow ?: return
        if (root.packageName?.toString() != pkg) return
        val screen = Rect().also { root.getBoundsInScreen(it) }
        val chat = chatTitle(root, pkg)
        if (chat == null) {
            // The chat list, calls or status screen: no badge.
            ChatBadge.hide()
            return
        }
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
            GuardEngine.check(this, msg) { GuardEngine.handle(this, it, "chats") }
        }
        // The relationship check behind the badge, on everything seen so far.
        val visible = texts.takeLast(40).map { mapOf("text" to it.first, "incoming" to it.second) }
        GuardEngine.call(this, "checkChat", mapOf("app" to pkg, "chat" to chat, "messages" to visible)) { r ->
            if (r != null && lastPkg == pkg && GuardEngine.guardOn(this, "chats")) ChatBadge.show(this, r)
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
        // Telegram and Messenger have no stable ids: an open chat has a typing
        // box, and its title is the first short text at the top.
        if (!hasEditable(root, 0)) return null
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

    private fun hasEditable(n: AccessibilityNodeInfo?, d: Int): Boolean {
        if (n == null || d > 30) return false
        if (n.isEditable) return true
        for (i in 0 until n.childCount) if (hasEditable(n.getChild(i), d + 1)) return true
        return false
    }

    // ------------------------------------------------------------ web pages

    private fun isBrowserLike(event: AccessibilityEvent) =
        event.className?.toString()?.contains("WebView") == true && event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED

    private fun scanAddressBar(pkg: String) {
        val root = rootInActiveWindow ?: return
        if (root.packageName?.toString() != pkg) return
        val bar = addressBar(root, pkg) ?: return
        // Half-typed addresses are not pages yet.
        if (bar.isFocused) return
        val text = bar.text?.toString()?.trim().orEmpty()
        if (text.length < 4 || text.contains(' ')) return
        val host = text.substringAfter("://").substringBefore('/').substringBefore(':').removePrefix("www.").lowercase()
        if (host in GuardEngine.allowedHosts(this)) return

        val now = System.currentTimeMillis()
        val cached = verdicts[text]
        if (cached != null && now - cached.first < 10 * 60 * 1000) {
            act(pkg, text, cached.second)
            return
        }
        GuardEngine.call(this, "checkSite", mapOf("url" to text)) { r ->
            verdicts[text] = now to r
            if (verdicts.size > 200) verdicts.remove(verdicts.keys.first())
            act(pkg, text, r)
        }
    }

    private fun act(pkg: String, url: String, r: Map<*, *>?) {
        if (r == null || r["block"] != true) return
        val host = r["host"]?.toString() ?: url
        val now = System.currentTimeMillis()
        // Leave the page first, then explain.
        performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
        if (host == lastBlocked && now - lastBlockedAt < 4000) return
        lastBlocked = host
        lastBlockedAt = now
        GuardEngine.count(this, "pages")
        GuardEngine.remember(this, mapOf(
            "app" to pkg,
            "chat" to host,
            "level" to r["level"],
            "label" to r["label"],
            "headline" to r["headline"],
            "reasons" to r["reasons"],
        ), "site", url)
        Notifier.warn(this, "Kantoi closed a scam website", "$host: ${r["headline"] ?: ""}", url, r["level"]?.toString())
        SiteBlocked.show(this, r, url)
    }

    /** The address bar: by view id in known browsers, else a text box holding a web address. */
    private fun addressBar(root: AccessibilityNodeInfo, pkg: String): AccessibilityNodeInfo? {
        for (id in urlBarIds[pkg].orEmpty() + genericUrlIds.map { "$pkg:id/$it" }) {
            root.findAccessibilityNodeInfosByViewId(id)?.firstOrNull { !it.text.isNullOrBlank() }?.let { return it }
        }
        return findUrlField(root, 0)
    }

    private fun findUrlField(n: AccessibilityNodeInfo?, d: Int): AccessibilityNodeInfo? {
        if (n == null || d > 25) return null
        val cls = n.className?.toString().orEmpty()
        val t = n.text?.toString()?.trim().orEmpty()
        if ((n.isEditable || cls.endsWith("EditText")) && looksLikeUrl.matches(t)) return n
        for (i in 0 until n.childCount) findUrlField(n.getChild(i), d + 1)?.let { return it }
        return null
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
        private val chatScreens = setOf(
            "com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger", "org.telegram.messenger.web", "com.facebook.orca",
        )
        private val urlBarIds = mapOf(
            "com.android.chrome" to listOf("com.android.chrome:id/url_bar"),
            "com.chrome.beta" to listOf("com.chrome.beta:id/url_bar"),
            "com.sec.android.app.sbrowser" to listOf(
                "com.sec.android.app.sbrowser:id/location_bar_edit_text",
                "com.sec.android.app.sbrowser:id/custom_tab_toolbar_url_bar_text",
            ),
            "org.mozilla.firefox" to listOf("org.mozilla.firefox:id/mozac_browser_toolbar_url_view"),
            "com.microsoft.emmx" to listOf("com.microsoft.emmx:id/url_bar"),
            "com.opera.browser" to listOf("com.opera.browser:id/url_field"),
            "com.opera.mini.native" to listOf("com.opera.mini.native:id/url_field"),
            "com.brave.browser" to listOf("com.brave.browser:id/url_bar"),
            "com.duckduckgo.mobile.android" to listOf("com.duckduckgo.mobile.android:id/omnibarTextInput"),
            "com.kiwibrowser.browser" to listOf("com.kiwibrowser.browser:id/url_bar"),
            "com.vivaldi.browser" to listOf("com.vivaldi.browser:id/url_bar"),
        )
        private val browsers = urlBarIds.keys + setOf("com.mi.globalbrowser", "com.UCMobile.intl", "com.huawei.browser")
        private val genericUrlIds = listOf("url_bar", "url", "url_field", "address_bar_edit_text")
        private val looksLikeUrl = Regex("""^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}([/:?#]\S*)?$""", RegexOption.IGNORE_CASE)

        private val paymentWords = listOf(
            "bank", "maybank", "cimb", "rhb", "hongleong", "hlb", "publicbank", "ambank", "bsn", "affin", "alliance",
            "ocbc", "uob", "hsbc", "agrobank", "muamalat", "tngdigital", "touchngo", "shopeepay", "bigpay", "gxbank", "boost",
        )
        private val paymentLabels = listOf("bank", "maybank", "mae", "cimb", "octo", "rhb", "touch 'n go", "tng", "e-wallet", "ewallet", "duitnow", "boost", "shopeepay")
    }
}
