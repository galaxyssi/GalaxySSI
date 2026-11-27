package com.galaxyssi.chat

import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class VoiceRecipientCorrectionDeviceTest {
    @get:org.junit.Rule val permissions = ViewportNoPermissionPromptRule()
    @Test fun correctedRecipientAndOriginalBodyReachOnlyTheFakeSender() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val old = VoiceMessageDraft.Person("test-1000", "小林")
        val other = VoiceMessageDraft.Person("test-2000", "小琳")
        val intended = VoiceMessageDraft.Person("test-3000", "小琳")
        val posted = mutableListOf<Pair<String,String>>()
        val platform = AndroidAppControlPlatform(ctx, { name -> listOf(old, other, intended).filter { it.name == name } },
            { recipient, body, _ -> posted += recipient to body; mapOf("message_id" to 77L, "state" to "queued", "delivery_verified" to false) })
        val registry = AgentNativeToolRegistry().registerAll(AgentAppControlTools.definitions(platform))
        ActivityScenario.launch(MainActivity::class.java).use { window ->
            lateinit var chat: String
            window.onActivity { a ->
                chat = a.agentTranscriptStore.activeConversation().id
                requireNotNull(a.agentVoiceConversation).session.begin(chat)
            }
            fun utterance(text: String): String {
                val turn = UUID.randomUUID().toString()
                val trace = UUID.randomUUID().toString()
                window.onActivity { a ->
                    val session = requireNotNull(a.agentVoiceConversation).session
                    session.registerTrace(trace); assertTrue(session.claimInput(trace))
                    AppVoiceControlBridge.capture(a, trace, text)
                    session.registerTurn(trace, turn)
                    AppVoiceControlBridge.bindTurn(trace, chat, turn)
                }
                return turn
            }
            fun call(turn: String, op: String, vararg params: Pair<String, String>) =
                registry.invoke("galaxyssi.app.voice_message", mapOf("operation" to op, *params),
                    AgentNativeToolInvocationContext(conversationId = chat, turnId = turn, idempotencyKey = UUID.randomUUID().toString()))
            val body = "我十分钟后到"
            val t1 = utterance("给小林发消息，我十分钟后到")
            val first = call(t1, "prepare", "query" to old.name, "text" to body)
            assertTrue(first.toJson(), first.isSuccess)
            val t2 = utterance("不是小林，是小琳")
            val b = call(t2, "change_recipient", "revision" to first.output["revision"].toString(), "query" to intended.name)
            assertEquals("choose_recipient", b.output["state"]); assertEquals(body, b.output["text"])
            assertFalse(call(t1, "confirm", "revision" to first.output["revision"].toString()).isSuccess)
            val t3 = utterance("第二个")
            val c = call(t3, "choose", "revision" to b.output["revision"].toString(), "contact_id" to intended.id)
            assertEquals(intended.id, c.output["contact_id"]); assertTrue(posted.isEmpty())
            assertFalse(call(t3, "confirm", "revision" to c.output["revision"].toString()).isSuccess)
            val t4 = utterance("确认发送")
            val sent = call(t4, "confirm", "revision" to c.output["revision"].toString())
            assertEquals("queued", sent.output["state"])
            assertFalse(call(t4, "confirm", "revision" to c.output["revision"].toString()).isSuccess)
            val correction = call(utterance("不是这个人"), "change_recipient", "revision" to c.output["revision"].toString(), "query" to old.name)
            assertEquals("queued", correction.output["state"]); assertEquals(listOf(intended.id to body), posted)
            window.onActivity { a -> AppVoiceControlBridge.discardVoiceDraft(a); a.agentVoiceConversation?.session?.end() }
        }
    }
}
