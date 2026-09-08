package com.galaxyssi.chat.voice

import org.junit.Assert.*
import org.junit.Test

class VoiceConversationSessionTest {
    @Test fun callContainsMultipleUtterancesInOneConversation() {
        val session = VoiceConversationSession()
        val token = session.begin("conversation-a")
        session.registerTrace("utterance-1")
        session.registerTurn("utterance-1", "turn-1")
        session.registerTrace("utterance-2")
        session.registerTurn("utterance-2", "turn-2")
        assertTrue(session.isCurrent(token))
        assertTrue(session.acceptsTurn("conversation-a", "turn-1"))
        assertTrue(session.acceptsTurn("conversation-a", "turn-2"))
        assertFalse(session.acceptsTurn("conversation-b", "turn-2"))
    }

    @Test fun hangupRejectsLateAsrButStillRecognizesItsOwnership() {
        val session = VoiceConversationSession()
        val token = session.begin("a")
        session.registerTrace("old")
        session.end()
        assertFalse(session.isCurrent(token))
        assertTrue(session.ownsTrace("old"))
        assertFalse(session.acceptsTrace("old"))
        session.begin("b")
        assertFalse(session.acceptsTrace("old"))
        session.registerTurn("old", "stale-turn")
        assertFalse(session.acceptsTurn("b", "stale-turn"))
    }

    @Test fun microphonePauseInvalidatesPendingInputEvenAfterResume() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("old")
        session.mute(true)
        session.cancelPendingInput()
        session.mute(false)
        assertFalse(session.acceptsTrace("old"))
        session.registerTrace("new")
        assertTrue(session.acceptsTrace("new"))
    }

    @Test fun collapseDoesNotEndListeningOrChangeConversation() {
        val session = VoiceConversationSession()
        val token = session.begin("a")
        session.expand(false)
        assertFalse(session.expanded)
        assertTrue(session.active)
        assertTrue(session.isCurrent(token, "a"))
        session.expand(true)
        assertTrue(session.expanded)
    }

    @Test fun repeatedFinalRenderingSpeaksOnlyOncePerTurn() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("voice")
        session.registerTurn("voice", "turn")
        assertFalse(session.claimSpeech("b", "turn"))
        assertTrue(session.claimSpeech("a", "turn"))
        repeat(100) { assertFalse(session.claimSpeech("a", "turn")) }
    }

    @Test fun staleTasksFromAnEarlierCallCannotSpeakInANewCall() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("first")
        session.registerTurn("first", "old-task")
        session.end()
        session.begin("a")
        assertFalse(session.claimSpeech("a", "old-task"))
    }

    @Test fun answerToAnOlderUtteranceCannotTalkOverTheLatestRequest() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("first")
        session.registerTurn("first", "first-turn")
        session.registerTrace("second")
        session.registerTurn("second", "second-turn")
        assertFalse(session.claimSpeech("a", "first-turn"))
        assertTrue(session.claimSpeech("a", "second-turn"))
    }

    @Test fun emptyIdentifiersNeverMatch() {
        val session = VoiceConversationSession()
        assertFalse(session.acceptsTrace(""))
        assertFalse(session.acceptsTurn("", ""))
        session.begin("a")
        session.registerTrace("")
        session.registerTurn("", "")
        assertFalse(session.ownsTrace(""))
    }

    @Test fun newInputSuppressesAnOldAnswerBeforeItsAsrFinishes() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("first")
        session.registerTurn("first", "old-turn")
        session.registerTrace("second")
        assertEquals("", session.latestTurnId)
        assertFalse(session.claimSpeech("a", "old-turn"))
        assertTrue(session.ownsTrace("first"))
        assertFalse(session.acceptsTrace("first"))
        session.registerTurn("first", "late-old-turn")
        assertEquals("", session.latestTurnId)
        session.registerTurn("second", "new-turn")
        assertEquals("second", session.traceForTurn("new-turn"))
        assertTrue(session.claimSpeech("a", "new-turn"))
    }

    @Test fun mutedCallDoesNotClaimPlaybackAndTraceOwnershipExpiresWithCall() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.registerTrace("voice")
        session.registerTurn("voice", "turn")
        session.mute(true)
        assertFalse(session.claimSpeech("a", "turn"))
        session.mute(false)
        assertTrue(session.claimSpeech("a", "turn"))
        session.end()
        assertEquals("", session.traceForTurn("turn"))
    }

    @Test fun repeatedCallsDoNotResurrectCallbacks() {
        val session = VoiceConversationSession()
        repeat(1000) { index ->
            val token = session.begin("conversation-$index")
            val trace = "trace-$index"
            session.registerTrace(trace)
            session.registerTurn(trace, "turn-$index")
            assertTrue(session.acceptsTrace(trace))
            session.end()
            assertFalse(session.isCurrent(token))
            assertFalse(session.claimSpeech("conversation-$index", "turn-$index"))
        }
    }

    @Test fun mediaCompletionCanResumeAnOriginallyListeningCallOnlyOnce() {
        val session = VoiceConversationSession()
        val generation = session.begin("a")
        session.registerTrace("before-video")
        val media = requireNotNull(session.beginMediaPlayback())
        assertTrue(session.muted)
        assertFalse(session.acceptsTrace("before-video"))
        assertTrue(session.finishMediaPlayback(media))
        assertFalse(session.finishMediaPlayback(media))
        assertTrue("Only the visible controller may reopen the microphone", session.muted)
        session.mute(false)
        assertTrue(session.isCurrent(generation))
        assertFalse(session.acceptsTrace("before-video"))
    }

    @Test fun mediaCannotUnmuteAnExplicitlyMutedCall() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.mute(true)
        val media = requireNotNull(session.beginMediaPlayback())
        assertFalse(session.finishMediaPlayback(media))
        assertTrue(session.muted)
    }

    @Test fun theLatestMediaInheritsTheOriginalResumeIntent() {
        val session = VoiceConversationSession()
        session.begin("a")
        val first = requireNotNull(session.beginMediaPlayback())
        val second = requireNotNull(session.beginMediaPlayback())
        assertNotEquals(first, second)
        session.cancelMediaPlayback(first)
        assertFalse(session.finishMediaPlayback(first))
        assertTrue(session.finishMediaPlayback(second))
    }

    @Test fun mediaReplacementAlsoPreservesAnOriginalUserMute() {
        val session = VoiceConversationSession()
        session.begin("a")
        session.mute(true)
        val first = requireNotNull(session.beginMediaPlayback())
        val second = requireNotNull(session.beginMediaPlayback())
        assertFalse(session.finishMediaPlayback(first))
        assertFalse(session.finishMediaPlayback(second))
    }

    @Test fun explicitMicrophoneChangesCancelPendingMediaResume() {
        listOf(true, false).forEach { muted ->
            val session = VoiceConversationSession()
            session.begin("a")
            val media = requireNotNull(session.beginMediaPlayback())
            session.mute(muted)
            assertFalse(session.finishMediaPlayback(media))
            assertEquals(muted, session.muted)
        }
    }

    @Test fun backgroundOrAbandonedMediaCannotResume() {
        val session = VoiceConversationSession()
        session.begin("a")
        val backgroundMedia = requireNotNull(session.beginMediaPlayback())
        session.mute(true)
        assertFalse(session.finishMediaPlayback(backgroundMedia))
        session.mute(false)
        val detachedMedia = requireNotNull(session.beginMediaPlayback())
        session.cancelMediaPlayback(detachedMedia)
        assertFalse(session.finishMediaPlayback(detachedMedia))
    }

    @Test fun oldMediaCannotResumeANewerCallEvenInTheSameConversation() {
        val session = VoiceConversationSession()
        assertNull(session.beginMediaPlayback())
        session.begin("a")
        val old = requireNotNull(session.beginMediaPlayback())
        session.end()
        assertFalse(session.finishMediaPlayback(old))
        session.begin("a")
        val current = requireNotNull(session.beginMediaPlayback())
        assertNotEquals(old, current)
        assertFalse(session.finishMediaPlayback(old))
        assertTrue(session.finishMediaPlayback(current))
    }
}
