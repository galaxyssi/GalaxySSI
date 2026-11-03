package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class DesktopInputSessionTest {
    @Test fun commandsWaitForTheirOwnReceipt() {
        val queue = DesktopInputQueue()
        val first = DesktopInputCommand("click", JSONObject(), "first")
        val second = DesktopInputCommand("text", JSONObject(), "second")
        assertTrue(queue.add(first)); assertTrue(queue.add(second))
        assertEquals(first, queue.next()); assertNull(queue.next())
        assertFalse(queue.complete(DesktopInputResult("screenshot", true, null, "")))
        assertTrue(queue.complete(DesktopInputResult("first", true, null, "")))
        assertEquals(second, queue.next())
    }
    @Test fun failedInputIsNotReplayed() {
        val queue = DesktopInputQueue()
        queue.add(DesktopInputCommand("text", JSONObject(), "first"))
        queue.add(DesktopInputCommand("text", JSONObject(), "second"))
        queue.next()
        queue.complete(DesktopInputResult("first", false, null, "focus changed"))
        assertNull(queue.next())
    }
    @Test fun receiptsSurviveScreenshotsAndOtherDevices() {
        val mailbox = DesktopInputMailbox()
        mailbox.register("pc", "type")
        val result = DesktopInputResult("type", true, null, "")
        mailbox.record("other", result)
        assertNull(mailbox.consume("type"))
        mailbox.record("pc", result)
        repeat(30) { mailbox.record("pc", DesktopInputResult("screen-$it", true, null, "")) }
        assertEquals(result, mailbox.consume("type"))
        assertNull(mailbox.consume("type"))
    }
    @Test fun closingSessionDropsLateResults() {
        val mailbox = DesktopInputMailbox()
        mailbox.register("pc", "type"); mailbox.clear("pc")
        mailbox.record("pc", DesktopInputResult("type", true, null, ""))
        assertNull(mailbox.consume("type"))
    }
    @Test fun focusReadsMetadataOnly() {
        val result = DesktopInputResult.fromReceipt(JSONObject("""{"action_id":"a","status":"succeeded",
            "output":{"input_focus":{"available":true,"editable":true,"password":true,
            "target_id":"field","bounds":{"left":-10,"top":2,"width":50,"height":20}}}}"""))
        assertTrue(result.succeeded); assertTrue(result.focus!!.password)
        assertEquals(-10, result.focus.left); assertEquals("field", result.focus.targetId)
    }
    @Test fun queueIsBoundedAndCanBeCleared() {
        val queue = DesktopInputQueue()
        repeat(128) { assertTrue(queue.add(DesktopInputCommand("text", JSONObject()))) }
        assertFalse(queue.add(DesktopInputCommand("text", JSONObject())))
        queue.next(); queue.clear(); assertNull(queue.next()); assertNull(queue.active)
    }
}
