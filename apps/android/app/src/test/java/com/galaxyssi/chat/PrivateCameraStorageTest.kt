package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDate

class PrivateCameraStorageTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun `captures are partitioned by year and zero padded month`() {
        val file = PrivateCameraStorage.createFile(temporary.root, LocalDate.of(2026, 1, 2))
        assertEquals("composer-attachments-v1/camera/2026/01", file.parentFile!!.relativeTo(temporary.root).invariantSeparatorsPath)
        assertTrue(file.isFile)
        assertEquals("jpg", file.extension)
    }

    @Test fun `year and month rollover do not overwrite prior captures`() {
        val first = PrivateCameraStorage.createFile(temporary.root, LocalDate.of(2026, 12, 31))
        first.writeBytes(byteArrayOf(1, 2, 3))
        val next = PrivateCameraStorage.createFile(temporary.root, LocalDate.of(2027, 1, 1))
        assertNotEquals(first.parent, next.parent)
        assertArrayEquals(byteArrayOf(1, 2, 3), first.readBytes())
    }

    @Test fun `rapid captures have unique names`() {
        val files = (1..100).map { PrivateCameraStorage.createFile(temporary.root, LocalDate.of(2026, 10, 10)) }
        assertEquals(100, files.map { it.name }.toSet().size)
        assertTrue(files.all { it.length() == 0L })
    }

    @Test fun `storage failures are reported without falling back to public pictures`() {
        val invalid = temporary.newFile("not-a-directory")
        assertTrue(runCatching { PrivateCameraStorage.createFile(invalid) }.isFailure)
    }
}
