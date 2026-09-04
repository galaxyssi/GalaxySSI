package com.galaxyssi.chat.voice.model

import android.os.StatFs
import java.io.File

object WhisperStorageCapacity {
    fun availableBytes(directory: File): Long {
        val capacityRoot = prepareDirectory(directory) ?: return -1L
        return runCatching {
            StatFs(capacityRoot.absolutePath).availableBytes
        }.getOrDefault(-1L)
    }

    internal fun prepareDirectory(directory: File): File? {
        val target = directory.absoluteFile
        if (target.isDirectory) return target
        if (target.exists()) return target.parentFile?.takeIf(File::isDirectory)
        if (target.mkdirs()) return target
        return generateSequence(target.parentFile) { it.parentFile }
            .firstOrNull(File::isDirectory)
    }
}
