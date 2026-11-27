package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class VoiceMessageDraftTest {
    private val first = VoiceMessageDraft.Speaker("session", "chat", "1")
    private val second = first.copy(turn = "2")
    private val third = first.copy(turn = "3")
    private val lin = VoiceMessageDraft.Person("person-a", "小林")
    private val ling = VoiceMessageDraft.Person("person-b", "小琳")
    private val body = "我十分钟后到"
    private fun AgentNativeJsonObject.rev() = getValue("revision") as String

    @Test fun changeOnlyRecipientAndRequireANewExplicitConfirmation() {
        val d = VoiceMessageDraft()
        val a = d.begin(first, body, listOf(lin))
        val b = d.change(second, a.rev(), listOf(ling))
        assertEquals(body, b["text"])
        assertThrows(AppControlFailure::class.java) { d.claim(third, a.rev(), true) }
        assertThrows(AppControlFailure::class.java) { d.claim(second, b.rev(), true) }
        assertThrows(AppControlFailure::class.java) { d.claim(third, b.rev(), false) }
        val claim = d.claim(third, b.rev(), true)
        assertEquals(ling, claim.recipient); assertEquals(body, claim.text)
        assertThrows(AppControlFailure::class.java) { d.claim(third, b.rev(), true) }
        assertEquals("queued", d.finish(claim, "queued", 31)["state"])
        val after = d.change(third.copy(turn = "4"), b.rev(), listOf(lin))
        assertEquals("queued", after["state"]); assertEquals(31L, after["message_id"]); assertFalse(after.containsKey("text"))
        assertEquals("queued", d.cancel(third, b.rev())["state"])
    }
    @Test fun unknownAndAmbiguousRecipientNeverLeaveOriginalRecipientArmed() {
        val d = VoiceMessageDraft()
        val a = d.begin(first, body, listOf(lin))
        val b = d.change(second, a.rev(), emptyList())
        assertEquals("choose_recipient", b["state"]); assertNull(b["contact_id"])
        assertThrows(AppControlFailure::class.java) { d.claim(third, a.rev(), true) }
        val c = d.change(second, b.rev(), listOf(ling, ling.copy(id = "other")))
        assertThrows(AppControlFailure::class.java) { d.choose(second, c.rev(), ling.id, 1) }
        assertThrows(AppControlFailure::class.java) { d.choose(third, c.rev(), lin.id, 1) }
        assertThrows(AppControlFailure::class.java) { d.choose(third, c.rev(), ling.id, 2) }
        val chosen = d.choose(third, c.rev(), ling.id, VoiceMessageDraft.explicitChoice("第一个"))
        assertEquals(body, chosen["text"]); assertEquals(ling.id, chosen["contact_id"])
    }
    @Test fun expiresAndCannotMoveAcrossSessionsOrConversations() {
        var time = 1L
        val d = VoiceMessageDraft { time }
        val a = d.begin(first, body, listOf(lin))
        for (s in listOf(second.copy(session = "new"), second.copy(conversation = "new"))) {
            assertTrue(d.status(s).isEmpty())
            assertThrows(AppControlFailure::class.java) { d.claim(s, a.rev(), true) }
        }
        time += 180_001
        assertTrue(d.status(second).isEmpty())
        assertThrows(AppControlFailure::class.java) { d.claim(second, a.rev(), true) }
    }
    @Test fun compoundAndNegativePhrasesAreNeverSendAuthorization() {
        for (s in listOf("确认发送。", "SEND IT!", "发吧")) assertTrue(VoiceMessageDraft.explicitConfirmation(s))
        for (s in listOf("不要确认发送", "确认发送吗？", "不是小林，是小琳", "send it to someone else", ""))
            assertFalse(VoiceMessageDraft.explicitConfirmation(s))
    }
}
