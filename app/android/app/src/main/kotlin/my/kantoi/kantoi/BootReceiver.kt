package my.kantoi.kantoi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Turns protection back on after the phone restarts or Kantoi updates. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val ok = intent.action == Intent.ACTION_BOOT_COMPLETED || intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON"
        if (ok && GuardEngine.isEnabled(ctx)) GuardService.start(ctx)
    }
}
