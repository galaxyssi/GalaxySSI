package com.signalasi.chat

import android.system.Os
import java.io.File
import java.io.RandomAccessFile

internal object AgentRuntimePersistentDisk {
    const val SERIAL = "sa-system"
    const val LOGICAL_BYTES = 30L * 1024L * 1024L * 1024L

    fun provision(
        runtimeRoot: File,
        chmod: (String, Int) -> Unit = { path, mode -> Os.chmod(path, mode) }
    ): File {
        val directory = File(runtimeRoot, DIRECTORY)
        check(directory.mkdirs() || directory.isDirectory) {
            "Persistent Linux storage is unavailable"
        }
        val disk = File(directory, FILE_NAME)
        RandomAccessFile(disk, "rw").use { image ->
            check(image.length() <= LOGICAL_BYTES) {
                "Persistent Linux disk is larger than the supported logical size"
            }
            if (image.length() < LOGICAL_BYTES) {
                image.setLength(LOGICAL_BYTES)
                image.fd.sync()
            }
        }
        chmod(disk.absolutePath, PRIVATE_FILE_MODE)
        return disk
    }

    @Synchronized
    fun quarantine(runtimeRoot: File): File? {
        val directory = File(runtimeRoot, DIRECTORY)
        val disk = File(directory, FILE_NAME)
        if (!disk.isFile) return null
        val quarantine = File(directory, QUARANTINE_FILE_NAME)
        if (quarantine.exists()) {
            check(quarantine.delete()) { "The previous damaged Linux system disk cannot be removed" }
        }
        check(disk.renameTo(quarantine)) { "The damaged Linux system disk cannot be isolated" }
        return quarantine
    }

    private const val DIRECTORY = "system"
    private const val FILE_NAME = "signalasi-system.raw"
    private const val QUARANTINE_FILE_NAME = "signalasi-system.damaged.raw"
    private const val PRIVATE_FILE_MODE = 384
}
