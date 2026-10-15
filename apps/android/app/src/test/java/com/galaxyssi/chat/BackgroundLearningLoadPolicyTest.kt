package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class BackgroundLearningLoadPolicyTest {
    @Test fun coolDeviceRunsNormally() {
        assertEquals(BackgroundLearningLoad(), evaluate())
    }
    @Test fun mildHeatSpacesWorkWithoutStoppingIt() {
        assertEquals(BackgroundLearningLoad(0, 30_000), evaluate(thermal = 1))
        assertEquals(BackgroundLearningLoad(0, 30_000), evaluate(temperature = 388))
    }
    @Test fun moderateHeatDefersAndCoolSignalAutomaticallyResumes() {
        assertEquals(120_000L, evaluate(thermal = 2).deferMillis)
        assertEquals(120_000L, evaluate(temperature = 400).deferMillis)
        assertEquals(0L, evaluate().deferMillis)
    }
    @Test fun severeHeatWinsOverCharging() {
        assertEquals(300_000L, evaluate(thermal = 3, powered = true).deferMillis)
        assertEquals(300_000L, evaluate(temperature = 430, powered = true).deferMillis)
    }
    @Test fun lowBatteryDefersOnlyDiscretionaryWork() {
        assertEquals(300_000L, evaluate(percent = 8).deferMillis)
        assertEquals(0L, evaluate(percent = 8, powered = true).deferMillis)
        assertEquals(300_000L, evaluate(percent = 5, powered = true).deferMillis)
    }
    @Test fun powerSavingDefersWork() {
        assertEquals(300_000L, evaluate(powerSave = true).deferMillis)
    }
    @Test fun unavailableBatterySignalDoesNotBlockWork() {
        assertEquals(0L, evaluate(percent = -1).deferMillis)
    }
    private fun evaluate(thermal: Int = 0, temperature: Int = 350, percent: Int = 60,
        powered: Boolean = false, powerSave: Boolean = false) =
        BackgroundLearningLoadPolicy.evaluate(thermal, temperature, percent, powered, powerSave)
}
