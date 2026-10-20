package my.kantoi.kantoi

import android.app.Notification
import android.os.Bundle
import android.os.Parcelable
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Reads new message notifications from chat apps (WhatsApp, Telegram, SMS) and
 * hands each new message to Kantoi's checks. Notifications from other apps are
 * ignored, and nothing is stored unless a message is flagged.
 */
class GuardNotificationListener : NotificationListenerService() {
    private val seen = LinkedHashSet<String>()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (!GuardEngine.isEnabled(this)) return
        val pkg = sbn.packageName ?: return
        if (pkg !in GuardEngine.chatApps) return
        val n = sbn.notification ?: return
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = n.extras ?: return

        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val conversation = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
        val chat = conversation ?: title

        val messages = readMessages(extras)
        if (messages.isEmpty()) {
            val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: return
            messages.add(title to text)
        }
        for ((sender, text) in messages.takeLast(3)) {
            if (isSummary(text)) continue
            val key = "$pkg|$chat|$text"
            if (!seen.add(key)) continue
            if (seen.size > 500) seen.remove(seen.first())
            val msg = mapOf<String, Any?>(
                "app" to pkg,
                "chat" to chat.ifBlank { sender },
                "sender" to sender.ifBlank { chat },
                "text" to text,
                "incoming" to true,
            )
            GuardEngine.check(this, msg) { GuardEngine.handle(this, it) }
        }
    }

    /** Messages from a MessagingStyle notification, oldest first. */
    @Suppress("DEPRECATION")
    private fun readMessages(extras: Bundle): MutableList<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        val arr: Array<Parcelable>? = extras.getParcelableArray(Notification.EXTRA_MESSAGES)
        arr?.forEach { p ->
            val b = p as? Bundle ?: return@forEach
            val text = b.getCharSequence("text")?.toString() ?: return@forEach
            val sender = b.getCharSequence("sender")?.toString()
                ?: personName(b)
                ?: ""
            out.add(sender to text)
        }
        return out
    }

    @Suppress("DEPRECATION")
    private fun personName(b: Bundle): String? {
        if (android.os.Build.VERSION.SDK_INT < 28) return null
        return (b.get("sender_person") as? android.app.Person)?.name?.toString()
    }

    /** "5 new messages" style lines carry nothing to check. */
    private fun isSummary(text: String): Boolean {
        val t = text.trim().lowercase()
        if (t.length < 4) return true
        return Regex("""^\d+ (new )?messages?( from \d+ chats?)?$""").matches(t) ||
            t == "checking for new messages" || t.startsWith("this message was deleted")
    }
}
