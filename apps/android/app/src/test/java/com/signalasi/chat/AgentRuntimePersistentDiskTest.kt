package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

    @Test
    fun `quarantine isolates a damaged disk and lets provision create a clean replacement`() {
        val runtimeRoot = temporaryFolder.newFolder("runtime-recovery")
        val original = AgentRuntimePersistentDisk.provision(runtimeRoot) { _, _ -> }
        RandomAccessFile(original, "rw").use { image ->
            image.seek(4_096L)
            image.write(42)
        }

        val damaged = AgentRuntimePersistentDisk.quarantine(runtimeRoot)

        assertTrue(requireNotNull(damaged).isFile)
        assertFalse(original.exists())
        val replacement = AgentRuntimePersistentDisk.provision(runtimeRoot) { _, _ -> }
        assertTrue(replacement.isFile)
        assertEquals(AgentRuntimePersistentDisk.LOGICAL_BYTES, replacement.length())
        RandomAccessFile(replacement, "r").use { image ->
            image.seek(4_096L)
            assertEquals(0, image.read())
        }
    }

    @Test
    fun `persistent runtime failure policy only rebuilds a corrupted userspace`() {
        assertTrue(
            AgentPersistentRuntimeFailurePolicy.requiresSystemRebuild(
                AgentRuntimeExecutionResponse(
                    exitCode = 126,
                    stdout = "",
                    stderr = "chroot: can't execute '/bin/sh': Input/output error",
                    durationMillis = 10L
                )
            )
        )
        assertFalse(
            AgentPersistentRuntimeFailurePolicy.requiresSystemRebuild(
                AgentRuntimeExecutionResponse(
                    exitCode = 126,
                    stdout = "",
                    stderr = "permission denied",
                    durationMillis = 10L
                )
            )
        )
    }
}
