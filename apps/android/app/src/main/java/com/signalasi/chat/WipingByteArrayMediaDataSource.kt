package com.signalasi.chat

import android.media.MediaDataSource
import kotlin.math.min

internal class WipingByteArrayMediaDataSource(bytes: ByteArray) : MediaDataSource() {
    private var content: ByteArray? = bytes

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        val current = content ?: return -1
        if (position < 0L || position >= current.size) return -1
        val count = min(size, current.size - position.toInt())
        current.copyInto(buffer, offset, position.toInt(), position.toInt() + count)
        return count
    }

    override fun getSize(): Long = content?.size?.toLong() ?: 0L

    override fun close() {
        content?.fill(0)
        content = null
    }
}
