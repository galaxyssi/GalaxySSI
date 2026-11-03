package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class AgentAudioStateControlTest {
    @Test fun volumeInspectsBeforeMutationAndReportsActualReadback() {
        val port = Port()
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(listOf("read", "volume:8", "read"), port.calls)
        assertEquals(50, output["requested_percent"])
        assertEquals(8, output["target_volume"])
        assertEquals(8, output["volume"])
        assertEquals(true, output["state_verified"])
        assertValid(output, volume = true)
    }

    @Test fun ignoredSetKeepsTheObservedValueAndDoesNotRetry() {
        val port = Port(applyChanges = false)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(3, output["volume"])
        assertEquals(true, output["request_accepted"])
        assertEquals(false, output["state_verified"])
        assertEquals(3, port.calls.size)
        assertValid(output, volume = true)
    }

    @Test fun alreadySatisfiedRequestDoesNotRepeatTheEffect() {
        val port = Port(volume = 8)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(listOf("read"), port.calls)
        assertEquals(false, output["dispatch_attempted"])
        assertEquals(true, output["state_verified"])
    }

    @Test fun lostReadbackDoesNotInventVolumeFromTheRequestedValue() {
        val port = Port(failReadback = true)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(false, output["state_verified"])
        assertFalse(output.containsKey("volume"))
        assertFalse(output.containsKey("observed_at_epoch_millis"))
        assertEquals("IllegalStateException", output["observation_error"])
        assertValid(output, volume = true)
    }

    @Test fun exceptionAfterApplyingEffectStillUsesReadbackWithoutReplay() {
        val port = Port(throwAfterSet = true)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(false, output["request_accepted"])
        assertEquals(true, output["state_verified"])
        assertEquals(8, output["volume"])
        assertEquals(listOf("read", "volume:8", "read"), port.calls)
    }

    @Test fun deniedSetDoesNotBecomeAConfirmedChange() {
        val port = Port(applyChanges = false, throwAfterSet = true)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(false, output["state_verified"])
        assertEquals(3, output["volume"])
        assertEquals(false, output["request_accepted"])
    }

    @Test fun changedRangeIsNotVerifiedAgainstAnObsoleteTarget() {
        val port = Port(changeRange = true)
        val output = AgentAudioStateControl.volume("music", 50, port)
        assertEquals(8, output["volume"])
        assertEquals(30, output["max"])
        assertEquals(false, output["state_verified"])
    }

    @Test fun muteAndUnmuteCompareObservedStateAndAvoidDuplicateEffects() {
        val port = Port()
        val muted = AgentAudioStateControl.mute("music", true, port)
        assertEquals(true, muted["state_verified"])
        assertEquals(true, muted["muted"])
        assertValid(muted, volume = false)
        port.calls.clear()
        AgentAudioStateControl.mute("music", true, port)
        assertEquals(listOf("read"), port.calls)
        port.calls.clear()
        val unmuted = AgentAudioStateControl.mute("music", false, port)
        assertEquals(false, unmuted["muted"])
        assertEquals(true, unmuted["state_verified"])
        assertEquals(listOf("read", "mute:false", "read"), port.calls)
        val ignored = AgentAudioStateControl.mute("music", true, Port(applyChanges = false))
        assertEquals(false, ignored["state_verified"])
        assertEquals(false, ignored["muted"])
    }

    @Test fun invalidStreamOrPercentNeverReachesTheDevice() {
        val port = Port()
        assertThrows(IllegalArgumentException::class.java) { AgentAudioStateControl.volume("speaker", 50, port) }
        assertThrows(IllegalArgumentException::class.java) { AgentAudioStateControl.volume("music", 101, port) }
        assertThrows(IllegalArgumentException::class.java) { AgentAudioStateControl.mute("unknown", true, port) }
        assertTrue(port.calls.isEmpty())
    }

    @Test fun unsupportedMinimumDoesNotSilentlyChangeTheRequestedGoal() {
        val port = Port(minimum = 1)
        val output = AgentAudioStateControl.volume("voice_call", 0, port)
        assertEquals(0, output["requested_percent"])
        assertEquals(0, output["target_volume"])
        assertEquals(3, output["volume"])
        assertEquals(1, output["min"])
        assertEquals(false, output["state_verified"])
        assertEquals(false, output["dispatch_attempted"])
        assertEquals("requested_step_below_minimum", output["state_constraint"])
        assertEquals(listOf("read"), port.calls)
        assertValid(output, volume = true)
    }

    @Test fun initialObservationFailureCannotMutate() {
        val port = object : AgentAudioControlPort {
            override fun read(): AgentAudioState = error("unavailable")
            override fun setVolume(value: Int) = fail("must not execute")
            override fun setMuted(value: Boolean) = fail("must not execute")
        }
        assertThrows(IllegalStateException::class.java) { AgentAudioStateControl.volume("music", 50, port) }
    }

    private fun assertValid(output: AgentNativeJsonObject, volume: Boolean) {
        assertTrue(AgentNativeJsonSchemaValidator.validate(AgentAudioStateControl.outputSchema(volume), output).isValid)
    }

    private class Port(volume: Int = 3, val minimum: Int = 0, val applyChanges: Boolean = true,
        val failReadback: Boolean = false, val throwAfterSet: Boolean = false, val changeRange: Boolean = false
    ) : AgentAudioControlPort {
        var maximum = 15
        var currentVolume = volume
        var currentMuted = false
        var writes = 0
        val calls = mutableListOf<String>()
        override fun read(): AgentAudioState {
            calls += "read"
            if (failReadback && writes > 0) error("readback unavailable")
            return AgentAudioState(currentVolume, maximum, minimum, currentMuted, 1000L + calls.size)
        }
        override fun setVolume(value: Int) {
            calls += "volume:$value"
            writes++
            if (applyChanges) currentVolume = value
            if (changeRange) maximum = 30
            if (throwAfterSet) error("API exception")
        }
        override fun setMuted(value: Boolean) {
            calls += "mute:$value"
            writes++
            if (applyChanges) currentMuted = value
            if (throwAfterSet) error("API exception")
        }
    }
}
