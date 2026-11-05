package com.galaxyssi.chat

import java.io.File
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.file.StandardOpenOption

/** A pending batch is identified only by its UUID. Its open lock survives preview and commit. */
internal class HealthRestoreLeases(private val root: File) {
    class Lease internal constructor(internal val marker: File, internal val channel: FileChannel, internal val lock: FileLock)

    fun pending(): List<String> = root.list().orEmpty().filter(HealthProfilePolicy::uuid)

    fun tryAcquire(id: String): Lease? = registry {
        require(HealthProfilePolicy.uuid(id))
        val marker = child(id)
        // Do not open a second descriptor to a file this process already locks.
        if (marker in active) return@registry null
        val channel = open(marker)
        try {
            val lock = channel.tryLock()
            if (lock == null) { channel.close(); null } else Lease(marker, channel, lock).also { active.add(marker) }
        } catch (failure: Throwable) {
            channel.close()
            throw failure
        }
    }

    fun release(lease: Lease, clean: Boolean) {
        try {
            if (clean) registry {
                check(lease.lock.isValid)
                lease.channel.close()
                lease.marker.delete()
            }
        } finally {
            synchronized(registryMutex) {
                try { lease.channel.close() } finally { active.remove(lease.marker) }
            }
        }
    }

    private fun child(name: String) = File(root.canonicalFile, name).also { check(it.canonicalFile == it) }

    private fun open(file: File) = FileChannel.open(file.toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE)

    private fun <T> registry(block: () -> T): T = synchronized(registryMutex) {
        check(root.isDirectory || root.mkdirs() || root.isDirectory)
        open(child(".registry")).use { channel -> channel.lock().use { block() } }
    }

    private companion object {
        val registryMutex = Any()
        val active = hashSetOf<File>()
    }
}
