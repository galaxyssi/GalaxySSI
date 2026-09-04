package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class GlobalSuperAgentRollbackTest {
    @Test
    fun `rollback truncates only records appended by the failed event`() {
        val records = mutableListOf("existing", "first-new", "second-new")

        records.truncateTailTo(1)

        assertEquals(listOf("existing"), records)
    }

    @Test
    fun `rollback accepts an already restored list`() {
        val records = mutableListOf("existing")

        records.truncateTailTo(1)

        assertEquals(listOf("existing"), records)
    }

    @Test
    fun `rollback rejects an invalid target size`() {
        assertThrows(IllegalArgumentException::class.java) {
            mutableListOf("existing").truncateTailTo(-1)
        }
    }
}
