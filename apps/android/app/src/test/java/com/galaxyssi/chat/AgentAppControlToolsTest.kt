package com.galaxyssi.chat

import com.galaxyssi.chat.voice.VoiceConversationSession
import org.junit.Assert.*
import org.junit.Test

class AgentAppControlToolsTest {
    @Test fun allProvidersReceivePhoneToolsNotDesktopExecution() {
        val definitions = AgentAppControlTools.definitions { _, _, _ -> emptyMap() }
        assertEquals(AgentAppControlTools.toolIds, definitions.map { it.descriptor.id }.toSet())
        definitions.forEach {
            assertEquals(AgentNativeToolLocation.PHONE, it.descriptor.location)
            assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(it.descriptor.id))
        }
    }

    @Test fun repeatInvocationDoesNotSendTwice() {
        var calls = 0
        val registry = AgentNativeToolRegistry().registerAll(AgentAppControlTools.definitions { _, _, _ ->
            calls++; mapOf("message_id" to 42, "state" to "queued", "delivery_verified" to false)
        })
        val args = mapOf("contact_id" to "peer-s20", "text" to "我十分钟后到。")
        val context = AgentNativeToolInvocationContext(conversationId = "agent-a", turnId = "turn-a", idempotencyKey = "speech-1")
        val first = registry.invoke("galaxyssi.app.send_message", args, context)
        val replay = registry.invoke("galaxyssi.app.send_message", args, context.copy(invocationId = "duplicate"))
        assertTrue(first.toJson(), first.isSuccess)
        assertTrue(replay.toJson(), replay.receipt.replayed)
        assertEquals(1, calls)
        assertEquals(false, replay.output["delivery_verified"])
    }

    @Test fun invalidCommandsCannotFallThroughToClicksOrDesktop() {
        var calls = 0
        val registry = AgentNativeToolRegistry().registerAll(AgentAppControlTools.definitions { _, _, _ -> calls++; emptyMap() })
        val cases = listOf(
            "navigate" to mapOf("destination" to "desktop"),
            "navigate" to mapOf("destination" to "contact", "javascript" to "unsafe"),
            "send_message" to mapOf("text" to "发给她"),
            "playback" to mapOf("operation" to "cancel_agent_task"),
            "news" to mapOf("limit" to 21),
            "news" to mapOf("since_epoch_ms" to -1),
            "contacts" to mapOf("limit" to 0))
        cases.forEach { (tool, args) ->
            assertFalse(registry.invoke(AgentAppControlTools.PREFIX + tool, args).isSuccess)
        }
        assertEquals(0, calls)
    }

    @Test fun concreteFailuresReachModelWithoutFakeSuccess() {
        val registry = AgentNativeToolRegistry().registerAll(AgentAppControlTools.definitions { _, _, _ ->
            throw AppControlFailure("article_not_ready", "正文尚未下载")
        })
        val result = registry.invoke("galaxyssi.app.read_article", mapOf("article_id" to "missing"))
        assertFalse(result.isSuccess)
        assertEquals("article_not_ready", result.error?.code)
    }

    @Test fun repeatedAsrFinalCanOnlyBeClaimedOnce() {
        val session = VoiceConversationSession()
        session.begin("session-a")
        session.registerTrace("utterance-a")
        assertTrue(session.claimInput("utterance-a"))
        assertFalse(session.claimInput("utterance-a"))
        session.registerTrace("utterance-b")
        assertFalse(session.claimInput("utterance-a"))
        assertTrue(session.claimInput("utterance-b"))
    }

    @Test fun endingVoiceDoesNotAcceptLateAsrOrCrossConversationResult() {
        val session = VoiceConversationSession()
        session.begin("session-a")
        session.registerTrace("a")
        session.registerTurn("a", "turn-a")
        assertFalse(session.acceptsTurn("session-b", "turn-a"))
        session.end()
        assertFalse(session.claimInput("a"))
        assertFalse(session.acceptsTurn("session-a", "turn-a"))
        session.begin("session-b")
        assertFalse(session.claimInput("a"))
    }

    @Test fun pausingMediaInvalidatesLateSpeechButKeepsConversation() {
        val session = VoiceConversationSession()
        session.begin("session-a")
        session.registerTrace("a")
        val media = requireNotNull(session.beginMediaPlayback())
        assertFalse(session.claimInput("a"))
        assertTrue(session.finishMediaPlayback(media))
        assertEquals("session-a", session.conversationId)
    }

    @Test fun passiveCaptureAfterNavigationDoesNotInvalidateTheExecutingAppTurn() {
        val session = VoiceConversationSession()
        session.begin("session-a")
        session.registerTrace("open-news")
        assertTrue(session.claimInput("open-news"))
        session.registerTurn("open-news", "news-turn")
        session.cancelPendingInput()
        session.registerTrace("passive-capture-on-news")
        assertTrue(session.acceptsAppControlTurn("news-turn"))
        assertFalse(session.acceptsAppControlTurn("another-turn"))
        assertTrue(session.claimInput("passive-capture-on-news"))
        assertFalse(session.acceptsAppControlTurn("news-turn"))
        session.registerTurn("passive-capture-on-news", "new-command")
        assertTrue(session.acceptsAppControlTurn("new-command"))
        session.end()
        assertFalse(session.acceptsAppControlTurn("new-command"))
    }

    @Test fun duplicateFinalDoesNotInvalidateAnAlreadyBoundAppTurn() {
        val session = VoiceConversationSession()
        session.begin("session-a")
        session.registerTrace("utterance")
        assertTrue(session.claimInput("utterance"))
        session.registerTurn("utterance", "turn-a")
        assertFalse(session.claimInput("utterance"))
        assertTrue(session.acceptsAppControlTurn("turn-a"))
    }
}
