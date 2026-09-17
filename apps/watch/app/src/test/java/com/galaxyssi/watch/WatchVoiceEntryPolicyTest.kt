package com.galaxyssi.watch

import org.junit.Assert.*
import org.junit.Test

class WatchVoiceEntryPolicyTest {
    @Test fun explicitVoiceEntryDoesNotRequireLauncherPreference() {
        assertTrue(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", true, false, false))
        assertTrue(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.VOICE_COMMAND", false, false, false))
    }
    @Test fun ordinaryLaunchRequiresOptInAndNeverHijacksNotificationLinks() {
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", false, false, false))
        assertTrue(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", false, true, false))
        assertFalse(WatchVoiceEntryPolicy.requestsVoice("android.intent.action.MAIN", false, true, true))
        assertFalse(WatchVoiceEntryPolicy.requestsVoice(null, false, true, false))
    }
}
