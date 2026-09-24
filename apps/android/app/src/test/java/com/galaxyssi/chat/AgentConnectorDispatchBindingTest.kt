package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentConnectorDispatchBindingTest {
    private val delivery = AgentPendingDelivery(7L, "conversation", "turn", "task", "contact")

    @Test fun replyBindingIsDurableBeforeRemoteRequestIsQueued() {
        val events = mutableListOf<String>()
        val accepted = AgentConnectorDispatchBinding.publish(delivery,
            register = { events += "registered" },
            retire = { events += "retired" },
            send = { events += "sent"; true })
        assertTrue(accepted)
        assertEquals(listOf("registered", "sent"), events)
    }

    @Test fun rejectedRequestRetiresItsBinding() {
        val events = mutableListOf<String>()
        val accepted = AgentConnectorDispatchBinding.publish(delivery,
            register = { events += "registered" },
            retire = { events += "retired" },
            send = { events += "rejected"; false })
        assertFalse(accepted)
        assertEquals(listOf("registered", "rejected", "retired"), events)
    }

    @Test fun thrownPublishRetiresItsBinding() {
        val events = mutableListOf<String>()
        assertTrue(runCatching {
            AgentConnectorDispatchBinding.publish(delivery,
                register = { events += "registered" },
                retire = { events += "retired" },
                send = { error("transport failed") })
        }.isFailure)
        assertEquals(listOf("registered", "retired"), events)
    }

    @Test fun managedRequestDoesNotCreateAStandaloneReplyBinding() {
        val events = mutableListOf<String>()
        val accepted = AgentConnectorDispatchBinding.publish(null,
            register = { events += "registered" },
            retire = { events += "retired" },
            send = { events += "sent"; true })
        assertTrue(accepted)
        assertEquals(listOf("sent"), events)
    }
}
