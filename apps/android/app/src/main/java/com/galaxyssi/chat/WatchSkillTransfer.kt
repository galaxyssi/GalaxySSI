package com.galaxyssi.chat

import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.Base64

/** Bounded chunks carried by the already authenticated Wi-Fi setup channel. */
internal object WatchSkillTransfer {
    const val CHUNK_BYTES = 16 * 1024
    fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes).joinToString("") { "%02x".format(it) }

    fun send(bytes: ByteArray, exchange: (JSONObject) -> JSONObject): JSONObject {
        DoorAccessSkillPackage.inspect(bytes)
        fun message(kind: String) = JSONObject().put("type", "configure").put("kind", kind)
        require(exchange(message("skill_begin").put("size", bytes.size).put("sha256", digest(bytes)))
            .getString("status") == "uploading")
        var index = 0
        var offset = 0
        while (offset < bytes.size) {
            val end = minOf(offset + CHUNK_BYTES, bytes.size)
            val result = exchange(message("skill_chunk").put("index", index)
                .put("data", Base64.getEncoder().encodeToString(bytes.copyOfRange(offset, end))))
            require(result.getString("status") == "uploading" && result.getInt("next_index") == index + 1)
            index++; offset = end
        }
        return exchange(message("skill_finish"))
    }
}

internal class WatchSkillTransferInbox {
    private var buffer: ByteArrayOutputStream? = null
    private var size = 0
    private var hash = ""
    private var index = 0

    fun clear() { buffer = null; size = 0; hash = ""; index = 0 }
    fun begin(payload: JSONObject): JSONObject {
        clear()
        val length = payload.getInt("size")
        val digest = payload.getString("sha256")
        require(length in 1..DoorAccessSkillPackage.MAX_PACKAGE_BYTES)
        require(digest.matches(Regex("[0-9a-f]{64}")))
        size = length; hash = digest; buffer = ByteArrayOutputStream(minOf(length, WatchSkillTransfer.CHUNK_BYTES))
        return acknowledgment()
    }
    fun append(payload: JSONObject): JSONObject = try {
        val output = requireNotNull(buffer)
        require(payload.getInt("index") == index)
        val encoded = payload.getString("data")
        require(encoded.length <= ((WatchSkillTransfer.CHUNK_BYTES + 2) / 3) * 4)
        val chunk = Base64.getDecoder().decode(encoded)
        require(chunk.size in 1..WatchSkillTransfer.CHUNK_BYTES && output.size() + chunk.size <= size)
        output.write(chunk); index++
        acknowledgment()
    } catch (error: Exception) { clear(); throw error }

    fun finish(): DoorAccessSkillPackage = try {
        val bytes = requireNotNull(buffer).toByteArray()
        require(bytes.size == size && WatchSkillTransfer.digest(bytes) == hash)
        DoorAccessSkillPackage.inspect(bytes)
    } finally { clear() }

    private fun acknowledgment() = JSONObject().put("status", "uploading").put("next_index", index)
}
