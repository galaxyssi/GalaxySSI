package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** The Linux runtime receives a scoped capability, never the App's master key. */
internal object AgentBrowserHostAuthority {
    @Synchronized
    fun token(context: Context, scope: String): String {
        require(scope.matches(Regex("[a-f0-9]{64}")))
        val preferences = context.getSharedPreferences("browser_host_authority", Context.MODE_PRIVATE)
        val aad = "${context.packageName}:browser-host:v1".toByteArray()
        val saved = preferences.getString("master", null)
        val key = if (saved == null) SecureRandom().generateSeed(32) else {
            val envelope = Base64.decode(saved, Base64.NO_WRAP)
            try { AgentStorageCipher.decryptBinary(envelope, aad) } finally { envelope.fill(0) }
        }
        try {
            check(key.size == 32)
            if (saved == null) {
                val envelope = AgentStorageCipher.encryptBinary(key, aad)
                try {
                    check(preferences.edit().putString("master", Base64.encodeToString(envelope, Base64.NO_WRAP)).commit())
                } finally { envelope.fill(0) }
            }
            return Mac.getInstance("HmacSHA256").run {
                init(SecretKeySpec(key, "HmacSHA256"))
                doFinal(scope.toByteArray()).joinToString("") { "%02x".format(it.toInt() and 255) }
            }
        } finally { key.fill(0) }
    }
}
