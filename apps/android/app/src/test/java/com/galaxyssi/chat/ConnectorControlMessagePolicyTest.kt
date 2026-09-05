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
    fun internalDesktopControlStateIsSilent() {
        assertTrue(ConnectorControlMessagePolicy.isSilentStatus("desktop_control_authorizations"))
        assertTrue(ConnectorControlMessagePolicy.isSilentStatus("desktop_control_authorization_changed"))
        assertTrue(ConnectorControlMessagePolicy.isSilentStatus("desktop_executor_event"))
        assertTrue(ConnectorControlMessagePolicy.isSilentStatus("desktop_action_receipt"))
    }

    @Test
    fun pairingAndSecurityEventsRemainVisible() {
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("pairing_confirmed"))
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("pairing_revoked"))
        assertFalse(ConnectorControlMessagePolicy.isSilentStatus("profile_update"))
    }
}
