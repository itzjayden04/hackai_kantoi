package my.kantoi.kantoi

import android.app.Notification
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads new message notifications from the Scam Monitor's apps (chat, SMS,
 * social, email and marketplaces; see MonitorApps) and hands each new
 * message to Kantoi's checks. Notifications from other apps are ignored, and nothing is stored
 * unless a message is flagged.
 */
class GuardNotificationListener : NotificationListenerService() {
    private val seen = LinkedHashSet<String>()

    override fun onListenerConnected() {
        super.onListenerConnected()
        // Start the checks early so the first message is not slowed down.
        if (GuardEngine.isEnabled(this)) GuardEngine.warm(this)
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        // Some phones (Honor, Huawei, Xiaomi) unbind listeners to save power;
        // ask Android to connect us again.
        try {
            NotificationListenerService.requestRebind(ComponentName(this, GuardNotificationListener::class.java))
        } catch (e: Exception) {
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            read(sbn)
        } catch (e: Exception) {
            // A malformed notification from another app must never stop the listener.
        }
    }

    private fun read(sbn: StatusBarNotification) {
        if (!GuardEngine.guardOn(this, "messages")) return
        val pkg = sbn.packageName ?: return
        if (!MonitorApps.watched(this, pkg)) return
        val email = MonitorApps.isEmail(pkg)
        val n = sbn.notification ?: return
        // "3 new messages" group summaries repeat what the child notifications hold.
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.extras ?: return

        val title = cleanTitle(extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: "")
        val conversation = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()?.let { cleanTitle(it) }
        val chat = conversation?.takeIf { it.isNotBlank() } ?: title

        val messages = mutableListOf<Msg>()
        if (email) {
            // Title is the sender; the big text holds subject and preview.
            val body = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
            messages.add(Msg(title, title, body, true))
        } else {
            messages.addAll(readMessages(extras, chat))
            if (messages.isEmpty()) messages.addAll(readLines(extras, chat))
            if (messages.isEmpty()) {
                val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
                    ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
                messages.add(Msg(chat, title, text, true))
            }
        }
        for (m in messages.takeLast(5)) {
            if (isSummary(m.text) || m.chat.isBlank() && m.sender.isBlank()) continue
            val key = "$pkg|${m.chat}|${m.incoming}|${m.text}"
            if (!seen.add(key)) continue
            if (seen.size > 500) seen.remove(seen.first())
            val msg = mapOf<String, Any?>(
                "app" to pkg,
                "chat" to m.chat.ifBlank { m.sender },
                "sender" to m.sender.ifBlank { m.chat },
                "text" to m.text,
                "incoming" to m.incoming,
            )
            if (m.incoming) MonitorApps.count(this, pkg, false)
            val notifKey = sbn.key
            GuardEngine.check(this, msg) {
                GuardEngine.handle(this, it)
                // Take the scam out of the notification shade; Kantoi's own
                // warning (posted by handle) replaces it.
                if (it != null && it["alert"] == true && it["level"] == "danger" && MonitorApps.hideScams(this)) {
                    try {
                        cancelNotification(notifKey)
                    } catch (e: Exception) {
                    }
                }
            }
        }
    }

    private data class Msg(val chat: String, val sender: String, val text: String, val incoming: Boolean)

    /** Messages from a MessagingStyle notification (WhatsApp, Telegram, Google Messages), oldest first. */
    @Suppress("DEPRECATION")
    private fun readMessages(extras: Bundle, chat: String): List<Msg> {
        val arr: Array<Parcelable> = extras.getParcelableArray(Notification.EXTRA_MESSAGES) ?: return emptyList()
        val self = extras.getCharSequence(Notification.EXTRA_SELF_DISPLAY_NAME)?.toString()
        val raw = arr.mapNotNull { p ->
            val b = p as? Bundle ?: return@mapNotNull null
            val text = b.getCharSequence("text")?.toString() ?: return@mapNotNull null
            val sender = b.getCharSequence("sender")?.toString() ?: personName(b)
            sender to text
        }
        // A message with no sender is the phone owner's own reply, but only
        // trust that when other messages do name their sender.
        val named = raw.any { it.first != null }
        return raw.map { (sender, text) ->
            val mine = (named && sender == null) || (self != null && sender == self)
            Msg(chat, if (mine) "Me" else sender ?: chat, text, !mine)
        }
    }

    /**
     * InboxStyle notifications (older WhatsApp, some SMS apps): one line per
     * message. When the title is a summary ("WhatsApp", "5 new messages"), each
     * line reads "Name: text" or "Name @ Group: text".
     */
    private fun readLines(extras: Bundle, chat: String): List<Msg> {
        val lines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES) ?: return emptyList()
        val aggregate = chat.isBlank() || isSummary(chat) || chat.equals("WhatsApp", true) || chat.equals("Telegram", true) ||
            chat.equals("Messages", true)
        return lines.mapNotNull { cs ->
            val line = cs?.toString()?.trim().orEmpty()
            if (line.isEmpty()) return@mapNotNull null
            val m = if (aggregate) Regex("""^(.{1,60}?): (.+)$""", RegexOption.DOT_MATCHES_ALL).find(line) else null
            if (m != null) {
                val who = m.groupValues[1]
                val group = who.substringAfter(" @ ", "")
                val sender = who.substringBefore(" @ ")
                Msg(group.ifBlank { sender }, sender, m.groupValues[2], true)
            } else {
                Msg(chat, chat, line, true)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun personName(b: Bundle): String? {
        if (Build.VERSION.SDK_INT < 28) return null
        return (b.get("sender_person") as? android.app.Person)?.name?.toString()
    }

    /** "Ali (2 messages)" and "Ali: 3 new messages" become "Ali". */
    private fun cleanTitle(t: String): String =
        t.replace(Regex("""\s*\(\d+ (new )?(messages?|mesej)\)\s*$""", RegexOption.IGNORE_CASE), "")
            .replace(Regex(""":\s*\d+ (new )?(messages?|mesej).*$""", RegexOption.IGNORE_CASE), "")
            .trim()

    /** "5 new messages" lines, calls and media placeholders carry nothing to check. */
    private fun isSummary(text: String): Boolean {
        val t = text.trim().lowercase()
        if (t.length < 4) return true
        return summary.matches(t) ||
            t == "checking for new messages" || t.startsWith("this message was deleted") || t.startsWith("mesej ini telah dipadam") ||
            t in placeholders || callLines.any { t.startsWith(it) }
    }

    companion object {
        private val summary = Regex(
            """^(you have )?\d+ (new |unread )?(messages?|mesej)( (baharu|baru))?( from \d+ (chats?|conversations?|sembang))?\.?$""",
        )
        private val callLines = listOf(
            "incoming voice call", "incoming video call", "missed voice call", "missed video call",
            "panggilan suara masuk", "panggilan video masuk", "panggilan tidak dijawab",
        )
        private val placeholders = setOf(
            "📷 photo", "📷 foto", "🎤 voice message", "🎥 video", "voice message", "photo", "video", "sticker", "gif",
            "ringing…", "calling…", "ringing...", "calling...",
        )
    }
}
