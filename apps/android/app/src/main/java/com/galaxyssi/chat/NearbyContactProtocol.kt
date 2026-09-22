package com.galaxyssi.chat

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

/** Transport only: invitations still require PhoneContactCard validation and user approval. */
object NearbyContactProtocol {
    val SERVICE: UUID = UUID.fromString("4d15cb22-5501-46c5-9bca-f14b8dbe99a1")
    val INVITE: UUID = UUID.fromString("4d15cb22-5502-46c5-9bca-f14b8dbe99a1")
    const val MAX_BYTES = 8192
    val SELECT = byteArrayOf(0x00, 0xa4.toByte(), 0x04, 0x00, 0x07, 0xf0.toByte(), 0x47, 0x53, 0x53, 0x49, 0x01, 0x01)
    val OK = byteArrayOf(0x90.toByte(), 0x00)
    fun offset(value: Int): ByteArray = ByteBuffer.allocate(4).putInt(value).array()
    fun code(value: String): String = (ByteBuffer.wrap(MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8))).int.toLong().and(0xffffffffL) % 1_000_000).toString().padStart(6, '0')
    fun chunk(value: ByteArray, offset: Int, size: Int = 160): ByteArray {
        require(value.size in 1..MAX_BYTES && offset in 0 until value.size && size in 1..240)
        return ByteBuffer.allocate(8).putInt(value.size).putInt(offset).array() + value.copyOfRange(offset, minOf(value.size, offset + size))
    }
    class Reader {
        private var bytes = byteArrayOf()
        private var total = -1
        val offset get() = bytes.size
        fun accept(packet: ByteArray): String? {
            require(packet.size > 8)
            val header = ByteBuffer.wrap(packet)
            val length = header.int; val position = header.int
            require(length in 1..MAX_BYTES && (total == -1 || total == length) && position == bytes.size)
            total = length
            require(bytes.size + packet.size - 8 <= total)
            bytes += packet.copyOfRange(8, packet.size)
            return if (bytes.size == total) bytes.toString(Charsets.UTF_8) else null
        }
    }
}
