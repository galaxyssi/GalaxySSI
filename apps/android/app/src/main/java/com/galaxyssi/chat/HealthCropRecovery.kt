package com.galaxyssi.chat

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

internal data class HealthCropFiles(val staging: File, val destination: File, val relativePath: String) {
    fun publish() {
        Files.move(staging.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
        syncCropDirectory(requireNotNull(destination.parentFile))
    }
}

/** Pending entries contain only a random operation ID. The committed original row is the authority. */
internal class HealthCropRecovery(private val root: File) {
    private val crops get() = child(root.canonicalFile, "crops")
    private val markers get() = child(crops, "pending")
    private val data get() = child(crops, "data")

    internal fun files(id: String): HealthCropFiles {
        require(HealthProfilePolicy.uuid(id))
        return HealthCropFiles(child(data, "$id.partial"), child(data, "$id.ghealth"), "crops/data/$id.ghealth")
    }

    internal fun marker(id: String): File {
        require(HealthProfilePolicy.uuid(id))
        return child(markers, id)
    }

    fun <T> write(id: String, referenced: (String, String) -> Boolean, save: (HealthCropFiles) -> T): T = locked {
        val files = files(id)
        val entry = marker(id)
        ensureDirectory(data)
        ensureDirectory(markers)
        check(!files.staging.exists() && !files.destination.exists() && entry.createNewFile())
        syncCropDirectory(markers)
        try { save(files) }
        finally { runCatching { reconcile(id, referenced) } }
    }

    fun recover(referenced: (String, String) -> Boolean) {
        if (!markers.isDirectory) return
        locked {
            for (id in markers.list().orEmpty()) {
                if (HealthProfilePolicy.uuid(id)) runCatching { reconcile(id, referenced) }
            }
        }
    }

    private fun reconcile(id: String, referenced: (String, String) -> Boolean) {
        val files = files(id)
        val keep = !files.destination.exists() || referenced(id, files.relativePath)
        var changed = Files.deleteIfExists(files.staging.toPath())
        if (!keep) changed = Files.deleteIfExists(files.destination.toPath()) || changed
        if (changed) syncCropDirectory(data)
        if (Files.deleteIfExists(marker(id).toPath())) syncCropDirectory(markers)
    }

    private fun <T> locked(block: () -> T): T = processLock.withLock {
        ensureDirectory(root.canonicalFile)
        ensureDirectory(crops)
        FileChannel.open(child(crops, ".lock").toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE).use { channel ->
            channel.lock().use { block() }
        }
    }

    private fun ensureDirectory(dir: File) {
        if (dir.isDirectory) return
        check(dir.mkdirs() || dir.isDirectory)
        syncCropDirectory(requireNotNull(dir.parentFile))
    }

    private fun child(parent: File, name: String): File = File(parent, name).also {
        check(it.canonicalFile == it) { "Invalid health crop path" }
    }

    private companion object {
        val processLock = ReentrantLock()
    }
}

private fun syncCropDirectory(directory: File) {
    check(directory.isDirectory)
    val descriptor = Os.open(directory.path, OsConstants.O_RDONLY, 0)
    try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
}
