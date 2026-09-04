package com.galaxyssi.chat.voice.correction

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.galaxyssi.chat.voice.TranscriptHypothesis
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AndroidVoiceCorrectionStoreInstrumentedTest {
    private lateinit var context: Context
    private lateinit var executionStore: AndroidVoiceExecutionRecordStore
    private lateinit var correctionJournal: VoiceCorrectionJournal

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        executionStore = AndroidVoiceExecutionRecordStore(context)
        correctionJournal = VoiceCorrectionJournal(context)
        executionStore.clear()
        correctionJournal.clear()
    }

    @After
    fun tearDown() {
        executionStore.clear()
        correctionJournal.clear()
    }

    @Test
    fun executionClaimsAndCorrectionsSurviveRecreationWithoutPlaintextPreferences() {
        val transcript = "private voice command"
        val ledger = VoiceExecutionLedger(
            initialRecords = executionStore.read(),
            persistence = executionStore
        )
        ledger.begin(
            sessionId = "voice-session",
            idempotencyKey = "voice-session:dispatch",
            fast = TranscriptHypothesis(transcript, 1, "whisper.cpp", "tiny_q5_1"),
            risk = VoiceCommandRisk.HIGH
        )
        assertTrue(ledger.claimPrimaryDispatch("voice-session"))
        assertFalse(ledger.claimPrimaryDispatch("voice-session"))

        val restored = VoiceExecutionLedger(executionStore.read(), executionStore)
        assertTrue(restored.snapshot("voice-session")?.primaryDispatchClaimed == true)
        assertFalse(restored.claimPrimaryDispatch("voice-session"))

        assertTrue(
            correctionJournal.append(
                VoiceCorrectionContextRecord(
                    sessionId = "voice-session",
                    conversationId = "conversation",
                    turnId = "turn",
                    fastText = transcript,
                    accurateText = "private corrected command",
                    diffSummary = "wording changed",
                    risk = VoiceCommandRisk.HIGH,
                    revision = 2,
                    modelProfileId = "medium_q5_0",
                    modelSha256 = "a".repeat(64),
                    executionMode = "SECOND_PASS",
                    userEdited = false,
                    completedAtMillis = 10L
                )
            )
        )
        assertEquals(1, correctionJournal.forConversation("conversation").size)
        assertTrue(correctionJournal.contextBlock("conversation").contains("private corrected command"))

        val rawExecution = context.getSharedPreferences(
            "galaxyssi_voice_execution_v1",
            Context.MODE_PRIVATE
        ).all.values.joinToString()
        val rawCorrections = context.getSharedPreferences(
            "galaxyssi_voice_corrections_v1",
            Context.MODE_PRIVATE
        ).all.values.joinToString()
        assertFalse(rawExecution.contains(transcript))
        assertFalse(rawCorrections.contains(transcript))
        assertTrue(rawExecution.startsWith("enc:v1:"))
        assertTrue(rawCorrections.startsWith("enc:v1:"))
    }
}
