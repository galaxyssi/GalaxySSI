package com.galaxyssi.chat.voice.asr.local

import org.junit.Assert.assertEquals
import org.junit.Test

class LargeTurboQnnModelManagerTest {
    @Test
    fun lifecycleStatesExposeOneUnambiguousUserAction() {
        val expectations = mapOf(
            LargeTurboQnnModelStatus.CHECKING to LargeTurboQnnModelAction.WAIT,
            LargeTurboQnnModelStatus.NOT_INSTALLED to LargeTurboQnnModelAction.DOWNLOAD,
            LargeTurboQnnModelStatus.DOWNLOADING to LargeTurboQnnModelAction.PAUSE,
            LargeTurboQnnModelStatus.PAUSED to LargeTurboQnnModelAction.RESUME,
            LargeTurboQnnModelStatus.VERIFYING to LargeTurboQnnModelAction.WAIT,
            LargeTurboQnnModelStatus.INSTALLING to LargeTurboQnnModelAction.WAIT,
            LargeTurboQnnModelStatus.FAILED to LargeTurboQnnModelAction.RETRY
        )

        expectations.forEach { (status, expected) ->
            assertEquals(
                expected,
                largeTurboQnnModelAction(LargeTurboQnnModelState(status), selected = false, supported = true)
            )
        }
        assertEquals(
            LargeTurboQnnModelAction.USE,
            largeTurboQnnModelAction(
                LargeTurboQnnModelState(LargeTurboQnnModelStatus.READY),
                selected = false,
                supported = true
            )
        )
        assertEquals(
            LargeTurboQnnModelAction.CURRENT,
            largeTurboQnnModelAction(
                LargeTurboQnnModelState(LargeTurboQnnModelStatus.READY),
                selected = true,
                supported = true
            )
        )
    }

    @Test
    fun incompatibleDeviceNeverOffersDownloadOrUse() {
        LargeTurboQnnModelStatus.entries.forEach { status ->
            assertEquals(
                LargeTurboQnnModelAction.UNSUPPORTED,
                largeTurboQnnModelAction(
                    LargeTurboQnnModelState(status),
                    selected = status == LargeTurboQnnModelStatus.READY,
                    supported = false
                )
            )
        }
    }
}
