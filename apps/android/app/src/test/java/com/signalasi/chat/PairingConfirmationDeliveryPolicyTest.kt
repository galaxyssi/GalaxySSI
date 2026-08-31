package com.signalasi.chat

import org.junit.Assert.assertEquals
import org.junit.Test

class PairingConfirmationDeliveryPolicyTest {
    @Test
    fun `replayed confirmation keeps one stable message identity`() {
        val first = PairingConfirmationDeliveryPolicy.messageId("", "desktop-a", "route-phone-a")
        val replay = PairingConfirmationDeliveryPolicy.messageId("", "desktop-a", "route-phone-a")

        assertEquals("pairing-confirmed:desktop-a:route-phone-a", first)
        assertEquals(first, replay)
    }

    @Test
    fun `desktop supplied message identity wins`() {
        assertEquals(
            "pairing-event-42",
            PairingConfirmationDeliveryPolicy.messageId(
                "pairing-event-42",
                "desktop-a",
                "route-phone-a"
            )
        )
    }
}
