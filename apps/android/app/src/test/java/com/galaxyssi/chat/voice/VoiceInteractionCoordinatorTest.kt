package com.galaxyssi.chat.voice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceInteractionCoordinatorTest {
    private var elapsedNs = 1_000L

    private fun coordinator() = VoiceInteractionCoordinator(
        elapsedClock = VoiceElapsedClock { ++elapsedNs },
        sessionIdFactory = { "generated-session" }
    )

    private fun begin(coordinator: VoiceInteractionCoordinator, id: String = "voice-1"): String {
        val transition = coordinator.begin(
            VoiceSessionConfig(
                requestedSessionId = id,
                source = "chat_hold_to_talk",
                language = "zh-CN"
            )
        )
        assertTrue(transition.accepted)
        return transition.current.sessionId
    }

    private fun reachFinal(
        coordinator: VoiceInteractionCoordinator,
        sessionId: String,
        text: String = "hello"
    ): VoiceInteractionTransition {
        coordinator.dispatch(VoiceInteractionEvent.CapturePrepared(sessionId))
        coordinator.dispatch(VoiceInteractionEvent.SpeechStarted(sessionId, ++elapsedNs))
        coordinator.dispatch(VoiceInteractionEvent.SpeechEnded(sessionId, ++elapsedNs))
        coordinator.dispatch(VoiceInteractionEvent.FinalizationStarted(sessionId))
        return coordinator.dispatch(
            VoiceInteractionEvent.TranscriptFinal(
                sessionId,
                TranscriptHypothesis(text, revision = 1, provider = "whisper.cpp", modelProfileId = "tiny")
            )
        )
    }

    @Test
    fun localActionFollowsCanonicalStatePath() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        val final = reachFinal(coordinator, sessionId)

        assertEquals(VoiceInteractionPhase.ROUTING, final.current.phase)
        assertEquals(1, final.commands.filterIsInstance<VoiceInteractionCommand.RouteFinalTranscript>().size)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                sessionId,
                VoiceRouteDecision(VoiceRouteKind.LOCAL_ACTION, "timer")
            )
        )
        val completed = coordinator.dispatch(VoiceInteractionEvent.LocalActionCompleted(sessionId))

        assertEquals(VoiceInteractionPhase.COMPLETED, completed.current.phase)
        assertFalse(completed.current.canInterrupt)
        assertTrue(coordinator.result()?.completed == true)
    }

    @Test
    fun duplicateFinalNeverCreatesASecondRoutingCommand() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        val first = reachFinal(coordinator, sessionId)
        val duplicate = coordinator.dispatch(
            VoiceInteractionEvent.TranscriptFinal(
                sessionId,
                TranscriptHypothesis("hello", revision = 1)
            )
        )

        assertEquals(1, first.commands.size)
        assertTrue(duplicate.commands.isEmpty())
        assertFalse(duplicate.accepted)
        assertEquals("hello", coordinator.snapshot().finalText)
    }

    @Test
    fun correctionUpdatesTranscriptWithoutReenteringRouting() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        reachFinal(coordinator, sessionId)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                sessionId,
                VoiceRouteDecision(VoiceRouteKind.CLOUD_MODEL, "provider")
            )
        )
        coordinator.dispatch(VoiceInteractionEvent.ModelDelta(sessionId, "answer"))
        coordinator.dispatch(VoiceInteractionEvent.Completed(sessionId))

        val correction = coordinator.dispatch(
            VoiceInteractionEvent.TranscriptCorrected(
                sessionId,
                TranscriptHypothesis("hello", 1),
                TranscriptHypothesis("hello world", 2)
            )
        )

        assertTrue(correction.accepted)
        assertEquals(VoiceInteractionPhase.COMPLETED, correction.current.phase)
        assertEquals("hello world", correction.current.correctedText)
        assertTrue(correction.commands.isEmpty())
    }

    @Test
    fun remoteAgentProgressUsesRealAcceptedAndProgressEvents() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        reachFinal(coordinator, sessionId)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                sessionId,
                VoiceRouteDecision(VoiceRouteKind.REMOTE_AGENT, "codex")
            )
        )

        assertEquals(VoiceInteractionPhase.STARTING_AGENT, coordinator.snapshot().phase)
        coordinator.dispatch(VoiceInteractionEvent.AgentAccepted(sessionId, "run-1"))
        val progress = coordinator.dispatch(VoiceInteractionEvent.AgentProgress(sessionId, "run-1"))

        assertEquals(VoiceInteractionPhase.AGENT_RUNNING, progress.current.phase)
        assertEquals("run-1", progress.current.agentRunId)
    }

    @Test
    fun remoteRunCreationReleasesVoiceSessionForTheNextCommand() {
        val coordinator = coordinator()
        val firstSession = begin(coordinator, "voice-1")
        reachFinal(coordinator, firstSession)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                firstSession,
                VoiceRouteDecision(VoiceRouteKind.REMOTE_AGENT, "codex")
            )
        )

        val handedOff = coordinator.dispatch(
            VoiceInteractionEvent.AgentRunCreated(firstSession, "run-1")
        )
        val second = coordinator.begin(
            VoiceSessionConfig(requestedSessionId = "voice-2", source = "voice_page")
        )

        assertEquals(VoiceInteractionPhase.COMPLETED, handedOff.current.phase)
        assertEquals("run-1", handedOff.current.agentRunId)
        assertTrue(second.accepted)
        assertEquals("voice-2", second.current.sessionId)
    }

    @Test
    fun remoteAgentCancellationUsesCancelledTerminalState() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        reachFinal(coordinator, sessionId)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                sessionId,
                VoiceRouteDecision(VoiceRouteKind.REMOTE_AGENT, "codex")
            )
        )
        coordinator.dispatch(VoiceInteractionEvent.AgentAccepted(sessionId, "run-1"))

        val cancelled = coordinator.dispatch(
            VoiceInteractionEvent.Cancelled(sessionId, "remote_agent_cancelled")
        )

        assertEquals(VoiceInteractionPhase.CANCELLED, cancelled.current.phase)
        assertTrue(coordinator.result()?.cancelled == true)
    }

    @Test
    fun cancellationIsTerminalAndEmitsOneLegacyCancelCommand() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        coordinator.dispatch(VoiceInteractionEvent.CapturePrepared(sessionId))

        val cancelled = coordinator.cancel("activity_destroyed")
        val duplicate = coordinator.cancel("activity_destroyed")

        assertEquals(VoiceInteractionPhase.CANCELLED, cancelled.current.phase)
        assertEquals(1, cancelled.commands.filterIsInstance<VoiceInteractionCommand.CancelLegacyWork>().size)
        assertFalse(duplicate.accepted)
        assertTrue(duplicate.commands.isEmpty())
        assertTrue(coordinator.result()?.cancelled == true)
    }

    @Test
    fun activeSessionCannotBeRestartedByUiRecreation() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        coordinator.dispatch(VoiceInteractionEvent.CapturePrepared(sessionId))
        val before = coordinator.snapshot()

        val duplicateBegin = coordinator.begin(
            VoiceSessionConfig(requestedSessionId = "voice-2", source = "activity_recreation")
        )

        assertFalse(duplicateBegin.accepted)
        assertEquals(before, coordinator.snapshot())
    }

    @Test
    fun observersReattachToCurrentStateWithoutReplayingCommands() {
        val coordinator = coordinator()
        val sessionId = begin(coordinator)
        reachFinal(coordinator, sessionId)
        val observed = mutableListOf<VoiceInteractionState>()

        val observerId = coordinator.observe { observed += it }

        assertEquals(VoiceInteractionPhase.ROUTING, observed.single().phase)
        assertNotNull(coordinator.snapshot().finalText)
        coordinator.removeObserver(observerId)
        coordinator.dispatch(
            VoiceInteractionEvent.RouteSelected(
                sessionId,
                VoiceRouteDecision(VoiceRouteKind.CLOUD_MODEL)
            )
        )
        assertEquals(1, observed.size)
    }

    @Test
    fun failingObserverCannotBreakSessionLifecycle() {
        val coordinator = coordinator()
        coordinator.observe { error("observer failure") }

        val sessionId = begin(coordinator)
        val transition = coordinator.dispatch(VoiceInteractionEvent.CapturePrepared(sessionId))

        assertTrue(transition.accepted)
        assertEquals(VoiceInteractionPhase.LISTENING, coordinator.snapshot().phase)
    }

    @Test
    fun lateEventFromCompletedSessionCannotMutateNextSession() {
        val coordinator = coordinator()
        val firstSession = begin(coordinator, "voice-1")
        reachFinal(coordinator, firstSession)
        coordinator.dispatch(VoiceInteractionEvent.Completed(firstSession))
        val secondSession = begin(coordinator, "voice-2")

        val lateEvent = coordinator.dispatch(
            VoiceInteractionEvent.Failed(
                firstSession,
                VoiceFailure("late_failure", true, VoiceInteractionPhase.ROUTING)
            )
        )

        assertFalse(lateEvent.accepted)
        assertEquals(secondSession, coordinator.snapshot().sessionId)
        assertEquals(VoiceInteractionPhase.PREPARING, coordinator.snapshot().phase)
    }

    @Test
    fun eventFromAnotherSessionIsRejected() {
        val coordinator = coordinator()
        begin(coordinator)

        val transition = coordinator.dispatch(
            VoiceInteractionEvent.Failed(
                "another-session",
                VoiceFailure("wrong_session", false, VoiceInteractionPhase.PREPARING)
            )
        )

        assertFalse(transition.accepted)
        assertEquals(VoiceInteractionPhase.PREPARING, coordinator.snapshot().phase)
    }
}
