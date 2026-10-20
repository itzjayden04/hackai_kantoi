package my.kantoi.kantoi

import android.os.Build
import android.telecom.Call
import android.telecom.CallScreeningService

/**
 * Call guard. Android hands Kantoi the number of each incoming call (only
 * the number) once the user picks Kantoi as their caller ID & spam app.
 * Numbers the user chose to always block are declined; any other call rings
 * as normal, and a risky one gets the "Answer carefully" warning.
 */
class KantoiCallScreeningService : CallScreeningService() {
    override fun onScreenCall(details: Call.Details) {
        if (Build.VERSION.SDK_INT >= 29 && details.callDirection != Call.Details.DIRECTION_INCOMING) {
            respondToCall(details, CallResponse.Builder().build())
            return
        }
        val raw = details.handle?.schemeSpecificPart
        val digits = raw?.filter { it.isDigit() }.orEmpty()
        val on = GuardEngine.guardOn(this, "calls")
        val blocked = on && digits.isNotEmpty() && GuardEngine.blockedNumbers(this).any { sameNumber(it, digits) }
        respondToCall(
            details,
            CallResponse.Builder()
                .setDisallowCall(blocked)
                .setRejectCall(blocked)
                .setSkipCallLog(false)
                .setSkipNotification(false)
                .build(),
        )
        if (!on || blocked) return

        val app = applicationContext
        GuardEngine.call(app, "checkCall", mapOf("number" to raw, "marked" to false)) { r ->
            if (r == null || r["warn"] != true) return@call
            GuardEngine.count(app, "calls")
            GuardEngine.remember(app, mapOf(
                "chat" to (r["number"] ?: raw),
                "level" to r["level"],
                "label" to r["label"],
                "headline" to r["title"],
                "reasons" to r["reasons"],
                "app" to "call",
            ), "call", r["number"]?.toString() ?: raw.orEmpty())
            Notifier.warn(
                app,
                "${r["title"]}: ${r["number"]}",
                "Answer carefully. " + ((r["reasons"] as? List<*>)?.joinToString(" ") ?: ""),
                r["number"]?.toString(),
                r["level"]?.toString(),
            )
            CallWarning.show(Overlays.service ?: app, r, digits)
        }
    }

    /** "0123456789" and "60123456789" are the same Malaysian number. */
    private fun sameNumber(a: String, b: String): Boolean {
        val x = a.trimStart('0').removePrefix("60")
        val y = b.trimStart('0').removePrefix("60")
        return x.isNotEmpty() && x == y
    }
}
