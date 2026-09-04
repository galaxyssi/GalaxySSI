package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DebugIntentExtrasTest {
    @Test
    fun consumesEveryOneShotExtraExactlyOnce() {
        val removed = mutableListOf<String>()

        DebugIntentExtras.consume(removed::add)

        assertEquals(DebugIntentExtras.oneShotKeys, removed)
        assertEquals(removed.size, removed.toSet().size)
    }

    @Test
    fun coversEveryDebugNavigationFamily() {
        val keys = DebugIntentExtras.oneShotKeys.toSet()

        assertTrue(
            keys.containsAll(
                setOf(
                    "galaxyssi_debug_open_protocol_quality",
                    "galaxyssi_debug_open_signal_link_protocol",
                    "galaxyssi_debug_open_advanced_options",
                    "galaxyssi_debug_open_security",
                    "galaxyssi_debug_open_contact_detail",
                    "galaxyssi_debug_open_cloud_provider",
                    "galaxyssi_debug_control_center_page",
                    "galaxyssi_debug_incoming_b64",
                    "galaxyssi_debug_chat_history_probe_b64"
                )
            )
        )
    }
}
