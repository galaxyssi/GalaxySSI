package com.galaxyssi.chat

import android.content.Context
import com.google.crypto.tink.subtle.AesGcmHkdfStreaming
import org.json.JSONObject
import java.io.Closeable
import java.io.File
import java.io.InputStream
import java.io.InputStreamReader
import java.nio.charset.CodingErrorAction
import java.security.SecureRandom
import java.util.UUID

/** Legacy non-memory fields are isolated individually; their collection APIs are not yet incremental. */
internal class BackupFieldStaging(context: Context) : Closeable {
    private val id = UUID.randomUUID().toString()
    private val directory = File(context.cacheDir, "app-backup-staging/$id").apply { check(mkdirs()) }
    private val aead = ByteArray(32).also(SecureRandom()::nextBytes).let { material ->
        try { AesGcmHkdfStreaming(material, "HmacSha256", 32, 1024 * 1024, 0) } finally { material.fill(0) }
    }
    private val files = linkedMapOf<Pair<String, String>, File>()

    fun accept(section: String, key: String, input: InputStream) {
        AppBackupFields.requireKnown(section, key)
        val identity = section to key
        require(identity !in files) { "Duplicate backup field: $section/$key" }
        val file = File(directory, "${files.size}.enc")
        try {
            file.outputStream().use { out -> aead.newEncryptingStream(out, aad(identity)).use { encrypted ->
                val buffer = ByteArray(64 * 1024)
                try {
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        encrypted.write(buffer, 0, count)
                    }
                } finally { buffer.fill(0) }
            } }
            files[identity] = file
            AppBackupFields.validate(section, key, read(identity))
        } catch (failure: Throwable) { file.delete(); files.remove(identity); throw failure }
    }

    fun identities(): Set<Pair<String, String>> = files.keys.toSet()

    fun visit(block: (String, String, Any) -> Unit) {
        files.keys.forEach { (section, key) -> block(section, key, read(section to key)) }
    }

    private fun read(identity: Pair<String, String>): Any = files.getValue(identity).inputStream().use { input ->
        aead.newDecryptingStream(input, aad(identity)).use { decrypted ->
            readBackupJson(decrypted).also { require(it.length() == 1) { "Invalid backup field envelope" } }.get("value")
        }
    }

    private fun aad(identity: Pair<String, String>) = "$id:${identity.first}:${identity.second}".toByteArray(Charsets.UTF_8)

    override fun close() {
        files.values.forEach { it.delete() }
        files.clear()
        directory.delete()
    }
}

internal fun readBackupJson(input: InputStream): JSONObject {
    val decoder = Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
    val tokens = org.json.JSONTokener(InputStreamReader(input, decoder).readText())
    val value = tokens.nextValue()
    require(value is JSONObject && tokens.nextClean() == '\u0000') { "Invalid backup JSON record" }
    return value
}
