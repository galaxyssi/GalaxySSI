package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.security.MessageDigest
import org.json.JSONObject

/** Authenticated per-frame copy/verification cursors; never contains a plaintext memory body. */
internal data class KnowledgePrimaryCopyState(
    val entry: String,
    val copied: Int = 0,
    val copiedChars: Long = 0,
    val copiedBytes: Long = 0,
    val copiedHash: String = EMPTY_HASH,
    val verified: Int = 0,
    val verifiedChars: Long = 0,
    val verifiedHash: String = EMPTY_HASH
) {
    fun validate(source: KnowledgePrimaryPartitions.Reference): KnowledgePrimaryCopyState = apply {
        require(entry.matches(Regex("[a-f0-9]{32}")) && entry != source.entry)
        require(copied in 0..source.chunks && verified in 0..copied)
        require(copiedChars in copied.toLong()..minOf(source.chars.toLong(), copied.toLong() * KnowledgePrimaryFrameCodec.CHARS))
        require(verifiedChars in verified.toLong()..minOf(copiedChars, verified.toLong() * KnowledgePrimaryFrameCodec.CHARS))
        require(copiedBytes in copied.toLong()..copied.toLong() * 262144)
        require((copied == source.chunks) == (copiedChars == source.chars.toLong()))
        require((verified == source.chunks) == (verifiedChars == source.chars.toLong()))
        require(verified == 0 || copied == source.chunks)
        require(copiedHash.matches(Regex("[a-f0-9]{64}")) && verifiedHash.matches(Regex("[a-f0-9]{64}")))
        require(copied != 0 || copiedHash == EMPTY_HASH)
        require(verified != 0 || verifiedHash == EMPTY_HASH)
    }

    fun encode() = JSONObject().put("version", 1).put("entry", entry).put("copied", copied)
        .put("copiedChars", copiedChars).put("copiedBytes", copiedBytes).put("copiedHash", copiedHash)
        .put("verified", verified).put("verifiedChars", verifiedChars).put("verifiedHash", verifiedHash).toString()

    companion object {
        val EMPTY_HASH = "0".repeat(64)
        fun decode(value: String): KnowledgePrimaryCopyState {
            require(value.length <= 4096)
            val json = JSONObject(value)
            require(json.getInt("version") == 1)
            return KnowledgePrimaryCopyState(json.getString("entry"), json.getInt("copied"), json.getLong("copiedChars"),
                json.getLong("copiedBytes"), json.getString("copiedHash"), json.getInt("verified"),
                json.getLong("verifiedChars"), json.getString("verifiedHash"))
        }
        fun chain(previous: String, ordinal: Int, compressed: String): String {
            val prefix = ByteArray(32) { previous.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
            val body = compressed.toByteArray(Charsets.UTF_8)
            return try {
                val digest = MessageDigest.getInstance("SHA-256")
                digest.update(prefix); digest.update(ByteBuffer.allocate(4).putInt(ordinal).array()); digest.update(body)
                digest.digest().joinToString("") { "%02x".format(it) }
            } finally { prefix.fill(0); body.fill(0) }
        }
    }
}
