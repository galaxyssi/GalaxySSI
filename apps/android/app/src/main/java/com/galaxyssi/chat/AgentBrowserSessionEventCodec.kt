package com.galaxyssi.chat

import android.content.Context
import java.io.File
import java.nio.file.Files
import java.nio.file.LinkOption
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject

/** Authenticated, generation-bound terminal observations from the guest browser service. */
internal object AgentBrowserSessionEventCodec {
    private const val MAX_BYTES = 4096

    fun workspace(record: AgentBrowserUserRequest) = AgentWorkspaceScope.id("browser-control:${record.scope}")

    fun binding(record: AgentBrowserUserRequest): String {
        require(record.key == AgentBrowserUserRequest.key(record.scope, record.browserSessionId))
        require(record.generation.matches(Regex("[A-Za-z0-9_-]{1,80}")))
        return "galaxyssi-browser-handoff-event:v1:${record.key}:${record.generation}"
    }

    fun file(context: Context, record: AgentBrowserUserRequest): File {
        val name = MessageDigest.getInstance("SHA-256").digest(binding(record).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 255) }
        return File(context.filesDir, "agent-native-workspaces/${workspace(record)}/.galaxyssi-browser-events/$name.enc")
    }

    fun prepare(context: Context, record: AgentBrowserUserRequest): AgentNativeJsonObject {
        val file = file(context, record)
        val directory = file.parentFile!!
        listOf(directory.parentFile!!.parentFile!!, directory.parentFile!!, directory).forEach {
            check(!Files.isSymbolicLink(it.toPath())) { "Browser event directory cannot be a symbolic link" }
            check(it.isDirectory || it.mkdirs()) { "Browser event directory is unavailable" }
        }
        return mapOf("key" to record.key, "generation" to record.generation, "workspace_id" to workspace(record))
    }

    fun decode(record: AgentBrowserUserRequest, capability: String, envelope: ByteArray): String? {
        if (envelope.size !in 30..MAX_BYTES || envelope[0] != 1.toByte()) return null
        val key = deriveKey(record, capability)
        return try {
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, envelope, 1, 12))
            cipher.updateAAD(binding(record).toByteArray(Charsets.UTF_8))
            val plain = cipher.doFinal(envelope, 13, envelope.size - 13)
            try {
                val value = JSONObject(plain.toString(Charsets.UTF_8))
                value.optString("code").takeIf { it == "session_lost" &&
                    value.optString("session_id") == record.browserSessionId &&
                    value.optString("page_id") == record.pageId && value.optString("handoff_id") == record.handoffId }
            } finally { plain.fill(0) }
        } catch (_: Exception) { null } finally { key.fill(0) }
    }

    internal fun deriveKey(record: AgentBrowserUserRequest, capability: String): ByteArray {
        require(capability.matches(Regex("[a-f0-9]{64}")))
        val token = capability.toByteArray(Charsets.UTF_8)
        return try {
            Mac.getInstance("HmacSHA256").run {
                init(SecretKeySpec(token, "HmacSHA256"))
                doFinal(binding(record).toByteArray(Charsets.UTF_8))
            }
        } finally { token.fill(0) }
    }

    fun consume(context: Context, record: AgentBrowserUserRequest,
        store: AgentBrowserUserRequestStore): AgentBrowserUserRequest? {
        if (record.state != "active" || record.handoffId.isBlank() || store.load(record.key) != record) return null
        val file = file(context, record)
        val envelope = try {
            if (listOf(file.parentFile!!, file.parentFile!!.parentFile!!).any { Files.isSymbolicLink(it.toPath()) }) return null
            Files.newInputStream(file.toPath(), LinkOption.NOFOLLOW_LINKS).use { input ->
                val buffer = ByteArray(MAX_BYTES + 1)
                try {
                    var length = 0
                    while (length < buffer.size) {
                        val read = input.read(buffer, length, buffer.size - length)
                        if (read < 0) break
                        length += read
                    }
                    if (length > MAX_BYTES) return null
                    buffer.copyOf(length)
                } finally { buffer.fill(0) }
            }
        } catch (_: Exception) { return null }
        val code = try { decode(record, AgentBrowserHostAuthority.token(context, record.scope), envelope) }
            finally { envelope.fill(0) }
        return code?.let { store.interruptObserved(record, it, mapOf("operation" to "human_control_state")) }
    }
}
