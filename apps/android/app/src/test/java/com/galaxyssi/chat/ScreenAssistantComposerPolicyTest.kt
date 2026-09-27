package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenAssistantComposerPolicyTest {
    @Test fun emptyInputCannotBeSubmitted() {
        listOf("", " ", "\n\t").forEach {
            assertFalse(ScreenAssistantComposerPolicy.canSubmit(it, ScreenAssistantDictationState.IDLE))
        }
    }

    @Test fun typedAndMultilineQuestionsCanBeSubmitted() {
        listOf("Question", "First paragraph\nSecond paragraph").forEach {
            assertTrue(ScreenAssistantComposerPolicy.canSubmit(it, ScreenAssistantDictationState.IDLE))
        }
    }

    @Test fun recordingAndRecognitionCannotDispatchPartialDrafts() {
        assertFalse(ScreenAssistantComposerPolicy.canSubmit("Question", ScreenAssistantDictationState.RECORDING))
        assertFalse(ScreenAssistantComposerPolicy.canSubmit("Question", ScreenAssistantDictationState.RECOGNIZING))
    }

    @Test fun dictationIsDraftOnlyAndDoesNotChangeHomeVoiceRouting() {
        assertTrue(ScreenAssistantComposerPolicy.returnsDraftOnly(SCREEN_ASSISTANT_DICTATION_PURPOSE))
        assertFalse(ScreenAssistantComposerPolicy.returnsDraftOnly("agent_input"))
        assertFalse(ScreenAssistantComposerPolicy.returnsDraftOnly("voice_wakeup"))
    }
}
