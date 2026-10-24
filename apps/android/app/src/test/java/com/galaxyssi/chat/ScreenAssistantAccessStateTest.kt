package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class ScreenAssistantAccessStateTest {
    @Test fun offRemainsOffRegardlessOfTheSystemService() {
        for (authorized in listOf(false, true)) for (connected in listOf(false, true)) {
            assertEquals(ScreenAssistantAccessState.DISABLED,
                ScreenAssistantAccessState.resolve(false, authorized, connected))
        }
    }

    @Test fun authorizationIsNotAConnection() {
        assertEquals(ScreenAssistantAccessState.DISCONNECTED,
            ScreenAssistantAccessState.resolve(true, true, false))
    }

    @Test fun missingAuthorizationDoesNotPretendTheUserTurnedTheAssistantOff() {
        assertEquals(ScreenAssistantAccessState.PERMISSION_REQUIRED,
            ScreenAssistantAccessState.resolve(true, false, false))
    }

    @Test fun actualConnectionWinsOverSettingsPropagationDelay() {
        for (authorized in listOf(false, true)) {
            assertEquals(ScreenAssistantAccessState.CONNECTED,
                ScreenAssistantAccessState.resolve(true, authorized, true))
        }
    }

    @Test fun disconnectAndReconnectNeverReuseAnOldReadyState() {
        assertEquals(listOf(ScreenAssistantAccessState.CONNECTED, ScreenAssistantAccessState.DISCONNECTED,
            ScreenAssistantAccessState.CONNECTED), listOf(true, false, true).map {
            ScreenAssistantAccessState.resolve(true, true, it)
        })
    }
}
