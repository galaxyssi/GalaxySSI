package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchVoiceEntryPolicyTest {
    @Test fun explicitVoiceEntryStartsRecognition() {
        assertTrue(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", true, false))
        assertTrue(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.VOICE_COMMAND", false, false))
    }
    @Test fun ordinaryLauncherAndRestoredTasksNeverRequestVoice() {
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", false, false))
        assertFalse(WatchVoiceEntryPolicy.requestsVoice(null, false, false))
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.VIEW", false, false))
    }
    @Test fun notificationsNeverRequestVoice() {
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.VOICE_COMMAND", false, true))
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", true, true))
    }
}
