package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentFileReceiptTest {
    private val third = AgentFileKey("chat", "turn", "third")
    private val id = "a".repeat(64)

    @Test fun recognitionDoesNotAcknowledgeDeliveryAndWireCannotEraseReading() {
        val r = JSONObject()
        assertTrue(AgentFileReceipt.reading(r, third, third.turn, false))
        assertFalse(AgentFileReceipt.item(r, third)!!.has("wire"))
        assertTrue(AgentFileReceipt.fold(r, third, id, "uploading", "peer"))
        assertTrue(AgentFileReceipt.fold(r, third, id, "stored"))
        assertFalse(AgentFileReceipt.fold(r, third, id, "failed"))
        assertEquals("unreadable", AgentFileReceipt.item(r, third)!!.getString("reading"))
    }

    @Test fun oneFileRetryCannotChangeSiblingsOrReviveClosedTransfers() {
        val row = JSONObject()
        val keys = (1..5).map { third.copy(item = "f$it") }
        keys.forEach { AgentFileReceipt.fold(row, it, id, "uploading", "peer") }
        keys.filterIndexed { index, _ -> index != 2 }.forEach { AgentFileReceipt.fold(row, it, id, "stored") }
        val f = keys[2]
        assertFalse(AgentFileReceipt.fold(row, f, "0".repeat(64), "stored"))
        assertTrue(AgentFileReceipt.fold(row, f, id, "failed"))
        assertTrue(AgentFileReceipt.fold(row, f, id, "retrying"))
        assertFalse(AgentFileReceipt.fold(row, f, id, "retrying"))
        assertTrue(AgentFileReceipt.fold(row, f, id, "closed"))
        assertFalse(AgentFileReceipt.fold(row, f, id, "failed"))
        assertEquals(4, keys.count { AgentFileReceipt.item(row, it)?.optString("wire") == "stored" })
    }

    @Test fun onlyCurrentChildCanReportAndLateEventsCannotManufactureAFile() {
        val row = JSONObject()
        assertFalse(AgentFileReceipt.fold(row, third, id, "stored"))
        assertEquals(0, row.length())
        AgentFileReceipt.startRead(row, third, "old-child")
        AgentFileReceipt.startRead(row, third, "new-child")
        assertFalse(AgentFileReceipt.reading(row, third, "old-child", true))
        assertFalse(AgentFileReceipt.reading(row, third, third.turn, true))
        assertTrue(AgentFileReceipt.reading(row, third, "new-child", false))
    }
}
