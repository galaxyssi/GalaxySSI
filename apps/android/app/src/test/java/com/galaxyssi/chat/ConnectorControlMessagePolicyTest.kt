package com.galaxyssi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectorControlMessagePolicyTest {
    @Test
    fun periodicConnectorStatusIsSilent() {
        assertTrue(ConnectorControlMessagePolicy.isSilentStatus("connector_status"))
    }

    @Test
    fun pairingAndSecurityEventsRemainVisible() {
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("pairing_confirmed"))
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("pairing_revoked"))
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("profile_update"))
    }
}
