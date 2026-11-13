package com.galaxyssi.chat

/** Public brokers can accept a large publication without promptly forwarding it. */
internal object MqttWireSizingPolicy {
    // Leave room for authenticated delivery metadata within the 64 KiB privacy bucket.
    const val DIRECT_BYTES = 60 * 1024
    const val CHUNK_BYTES = 44 * 1024

    fun encode(wire: String, persistedChunkBytes: Int? = null): List<String> =
        GalaxySSIMqttWireChunking.encode(
            wire,
            directLimitBytes = if (persistedChunkBytes == null) DIRECT_BYTES else 1,
            chunkDataBytes = persistedChunkBytes ?: CHUNK_BYTES
        )
}
