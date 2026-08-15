package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.RandomAccessFile

class AgentRuntimePersistentDiskTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `provision creates and preserves a thirty gigabyte logical disk`() {
        val runtimeRoot = temporaryFolder.newFolder("runtime")
        val disk = AgentRuntimePersistentDisk.provision(runtimeRoot) { _, _ -> }

        assertTrue(disk.isFile)
        assertEquals(AgentRuntimePersistentDisk.LOGICAL_BYTES, disk.length())
        RandomAccessFile(disk, "rw").use { image ->
            image.seek(4_096L)
            image.write(byteArrayOf(1, 2, 3, 4))
        }

        val reprovisioned = AgentRuntimePersistentDisk.provision(runtimeRoot) { _, _ -> }
        assertEquals(AgentRuntimePersistentDisk.LOGICAL_BYTES, reprovisioned.length())
        RandomAccessFile(reprovisioned, "r").use { image ->
            image.seek(4_096L)
            assertEquals(1, image.read())
        }
    }
}
