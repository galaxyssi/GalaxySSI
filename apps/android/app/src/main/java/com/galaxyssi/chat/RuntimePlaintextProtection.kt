package com.galaxyssi.chat

import android.content.Context

internal object RuntimePlaintextProtection {
    private val transientFilePrefixes = listOf(
        "agent_audio_",
        "galaxyssi_tts_",
        "voice_",
        "voice_cmd_"
    )
    private val transientDirectoryNames = setOf(
        "debug-agent-inputs",
        "decrypted",
        "diagnostics",
        "plaintext-previews"
    )

    fun clearKnownTemporaryFiles(context: Context) {
        val cacheRoot = context.cacheDir ?: return
        cacheRoot.listFiles().orEmpty().forEach { child ->
            when {
                child.isDirectory && child.name in transientDirectoryNames -> child.deleteRecursively()
                child.isFile && transientFilePrefixes.any(child.name::startsWith) -> child.delete()
            }
        }
    }

    fun isRuntimeDiagnosticsVisible(): Boolean = BuildConfig.SENSITIVE_DIAGNOSTICS_ENABLED
}
