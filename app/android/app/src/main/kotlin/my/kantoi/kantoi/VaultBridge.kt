package my.kantoi.kantoi

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The safe word vault's phone side (kantoi/vault): encrypts the vault with a
 * key that never leaves Android's hardware keystore, unlocks it with the
 * phone's fingerprint, face or PIN, and blocks screenshots while it is open.
 */
class VaultBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "kantoi/vault")
    private var pendingUnlock: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "encrypt" -> result.success(encrypt(call.arguments as String))
                    "decrypt" -> result.success(decrypt(call.arguments as String))
                    "hasLock" -> result.success(hasLock())
                    "unlock" -> unlock(call.arguments as? String ?: "Unlock your safe words", result)
                    "secure" -> {
                        if (call.arguments == true) {
                            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("vault", e.message, null)
            }
        }
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    /** Returns base64 of IV (12 bytes) + ciphertext. */
    private fun encrypt(plain: String): String {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        val out = c.iv + c.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(out, Base64.NO_WRAP)
    }

    private fun decrypt(b64: String): String {
        val all = Base64.decode(b64, Base64.NO_WRAP)
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, all, 0, 12))
        return String(c.doFinal(all, 12, all.size - 12), Charsets.UTF_8)
    }

    private fun hasLock(): Boolean {
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        return km.isDeviceSecure
    }

    /**
     * Answers "ok", "cancelled" or "nolock" (the phone has no screen lock, so
     * there is nothing to check against).
     */
    private fun unlock(title: String, result: MethodChannel.Result) {
        if (!hasLock()) {
            result.success("nolock")
            return
        }
        if (Build.VERSION.SDK_INT >= 30) {
            val prompt = BiometricPrompt.Builder(activity)
                .setTitle(title)
                .setSubtitle("Kantoi safe word vault")
                .setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
                )
                .build()
            prompt.authenticate(CancellationSignal(), activity.mainExecutor, object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult?) = result.success("ok")
                override fun onAuthenticationError(code: Int, msg: CharSequence?) = result.success("cancelled")
            })
            return
        }
        val km = activity.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
        @Suppress("DEPRECATION")
        val i: Intent? = km.createConfirmDeviceCredentialIntent(title, "Kantoi safe word vault")
        if (i == null) {
            result.success("nolock")
            return
        }
        pendingUnlock = result
        @Suppress("DEPRECATION")
        activity.startActivityForResult(i, REQUEST)
    }

    /** MainActivity forwards its activity results here. */
    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST) return false
        pendingUnlock?.success(if (resultCode == Activity.RESULT_OK) "ok" else "cancelled")
        pendingUnlock = null
        return true
    }

    companion object {
        private const val ALIAS = "kantoi_vault"
        private const val REQUEST = 51
    }
}
