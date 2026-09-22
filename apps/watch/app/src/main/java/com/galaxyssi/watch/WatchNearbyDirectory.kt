package com.galaxyssi.watch

import java.security.MessageDigest

/** Discovery hints are not authentication; the signed invitation is verified before adding. */
internal object WatchNearbyIdentity {
    fun encode(id: String, name: String): ByteArray {
        val fingerprint = MessageDigest.getInstance("SHA-256").digest(id.toByteArray()).copyOf(6)
        val model = when {
            name.contains("Watch5 Pro", true) -> 1
            name.contains("Watch6", true) -> 2
            else -> 0
        }
        val suffix = name.substringAfterLast("·", "").trim().takeIf { it.matches(Regex("[A-Za-z0-9]{4}")) }
            ?: fingerprint.take(2).joinToString("") { "%02X".format(it.toInt() and 255) }
        // 2 AD header + 16 UUID + 12 data = 30 bytes, within a legacy scan response.
        return byteArrayOf(1, model.toByte()) + fingerprint + suffix.toByteArray(Charsets.US_ASCII)
    }
    fun decode(bytes: ByteArray?): Pair<String, String>? {
        if (bytes == null || bytes.size != 12 || bytes[0] != 1.toByte()) return null
        val suffix = bytes.copyOfRange(8, 12).toString(Charsets.US_ASCII)
        if (!suffix.matches(Regex("[A-Za-z0-9]{4}"))) return null
        val model = when (bytes[1].toInt()) { 1 -> "Galaxy Watch5 Pro"; 2 -> "Galaxy Watch6"; else -> "Galaxy Watch" }
        return bytes.copyOfRange(2, 8).joinToString("") { "%02x".format(it.toInt() and 255) } to "$model · $suffix"
    }
}

internal class WatchNearbyDirectory<T> {
    data class Entry<T>(val key: String, val address: String, val name: String, val device: T, val seen: Long)
    private val entries = linkedMapOf<String, Entry<T>>()
    fun update(id: String?, address: String, name: String, device: T, now: Long): Boolean {
        val identified = if (id == null) entries.values.firstOrNull { it.address == address && it.key.startsWith("id:") } else null
        if (identified != null) {
            entries[identified.key] = identified.copy(device = device, seen = now)
            return false
        }
        val uniqueLegacyName = name.takeIf { it.matches(Regex(".*(?:·\\s*|\\()[A-Za-z0-9]{4}\\)?$")) }
        val key = id?.let { "id:$it" } ?: uniqueLegacyName?.let { "name:$it" } ?: "address:$address"
        // A scan response may follow the first advertisement with its stable identity.
        val aliases = entries.values.filter { it.key != key && (it.address == address ||
            (id != null && !it.key.startsWith("id:") && uniqueLegacyName != null && it.name == name)) }.map { it.key }
        aliases.forEach(entries::remove)
        val old = entries[key]
        if (old == null && entries.size >= 20) return aliases.isNotEmpty()
        entries[key] = Entry(key, address, name, device, now)
        return old == null || old.name != name || aliases.isNotEmpty()
    }
    fun prune(now: Long): Boolean = entries.values.filter { now - it.seen > 20_000 }.map { it.key }
        .also { keys -> keys.forEach(entries::remove) }.isNotEmpty()
    fun values() = entries.values.toList()
    fun get(key: String) = entries[key]
    fun clear() = entries.clear()
}
