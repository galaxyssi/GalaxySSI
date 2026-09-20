package com.galaxyssi.watch

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchDeviceNameTest {
    @Test fun usesFriendlyNameInsteadOfRawModel() {
        assertEquals("Galaxy Watch5 Pro \u00b7 EV1W", name("SM-R920", "Galaxy Watch5 Pro (EV1W)"))
    }

    @Test fun doesNotHardcodeWatchModelOrSuffix() {
        assertEquals("Galaxy Watch6 \u00b7 JQKL", name("SM-R940", "Galaxy Watch6 (JQKL)", model = "SM-R940"))
    }

    @Test fun preservesUserConfiguredName() {
        val actual = name("Training watch", "Galaxy Watch5 Pro (EV1W)")
        assertTrue(actual.startsWith("Training watch \u00b7 "))
        assertEquals(actual, name("Training watch", "Galaxy Watch5 Pro (EV1W)"))
    }

    @Test fun existingSuffixIsNotDuplicated() {
        assertEquals("Galaxy Watch5 Pro \u00b7 EV1W", name("Galaxy Watch5 Pro \u00b7 EV1W", null))
    }

    @Test fun missingSettingsFallBackWithoutAppBrand() {
        assertTrue(name(null, null).startsWith("SM-R920 \u00b7 "))
        assertEquals("Watch", WatchDeviceName.resolve(null, null, null, "", ""))
        assertTrue(name("GalaxySSI Watch", null).startsWith("SM-R920 \u00b7 "))
    }

    @Test fun secureNameIsUsedWhenOtherSettingsAreUnavailable() {
        assertEquals("My watch \u00b7 AB12", WatchDeviceName.resolve(null, null, "My watch (AB12)", "SM-R920", "id"))
    }

    @Test fun shortDiscriminatorIsStableAndDeviceSpecific() {
        assertNotEquals(name("Watch", null), WatchDeviceName.resolve("Watch", null, null, "SM-R920", "other-id"))
    }

    @Test fun boundsUtf8LengthAndRetainsSuffixWithoutSplittingCharacters() {
        val actual = name("\u8868\uD83D\uDE80".repeat(30) + " (EV1W)", null)
        assertTrue(actual.toByteArray(Charsets.UTF_8).size <= 63)
        assertEquals(actual, actual.toByteArray(Charsets.UTF_8).toString(Charsets.UTF_8))
        assertTrue(actual.endsWith(" \u00b7 EV1W"))
    }

    @Test fun stripsControlCharacters() {
        assertEquals("My watch \u00b7 EV1W", name(" My\n\u0000watch (EV1W) ", null))
    }

    @Test fun pairingUsesSameNameAsDiscoveryAndDoesNotChangeIdentity() {
        val discovered = name("SM-R920", "Galaxy Watch5 Pro (EV1W)")
        val payload = JSONObject().put("client_device_id", "unchanged").put("device_model", "SM-R920")
        WatchDeviceName.addPairingFields(payload, discovered)
        assertEquals(discovered, payload.getString("client_name"))
        assertEquals(discovered, payload.getString("device_name"))
        assertEquals("unchanged", payload.getString("client_device_id"))
        assertEquals("SM-R920", payload.getString("device_model"))
    }

    private fun name(global: String?, bluetooth: String?, model: String = "SM-R920") =
        WatchDeviceName.resolve(global, bluetooth, null, model, "stable-install-id")
}
