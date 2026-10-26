package com.galaxyssi.chat

import android.media.MediaDataSource

/** Takes ownership of one synthesized segment; no plaintext audio file is created. */
internal class SpeechAudioDataSource(private var bytes: ByteArray?) : MediaDataSource() {
    @Synchronized override fun getSize(): Long = bytes?.size?.toLong() ?: 0L

    @Synchronized override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        require(offset >= 0 && size >= 0 && offset <= buffer.size - size)
        if (size == 0) return 0
        val source = bytes ?: return -1
        if (position < 0 || position >= source.size.toLong()) return -1
        val count = minOf(size, source.size - position.toInt())
        source.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }

    @Synchronized override fun close() { bytes?.fill(0); bytes = null }
}
