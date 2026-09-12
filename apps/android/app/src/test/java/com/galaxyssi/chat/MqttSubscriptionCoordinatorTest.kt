package com.galaxyssi.chat

import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class MqttSubscriptionCoordinatorTest {
    private val rig = MqttPoolTestRig()
    private val coordinator = GalaxySSILinkSubscriptionCoordinator(1) { _, _ -> }
    @After fun close() { rig.close() }

    @Test fun neverAcknowledgedRevokedTopicIsRemovedFromPoolIntent() {
        rig.autoSuback = false
        rig.start(setOf("old"))
        coordinator.reconcile(rig.transport, emptyList(), setOf("old"), emptySet(), 1)
        coordinator.reconcile(rig.transport, emptyList(), emptySet(), emptySet(), 2)
        rig.client("emqx").grant(setOf("old"))
        assertTrue(rig.transport.readyPathGenerations(setOf("old")).isEmpty())
        assertEquals(0, rig.transport.snapshot().getValue("emqx").activeSubscriptions)
    }

    @Test fun rotationDuringNetworkLossDoesNotResubscribeRevokedAlias() {
        rig.start(setOf("old"))
        coordinator.reconcile(rig.transport, emptyList(), setOf("old"), emptySet(), 1)
        rig.transport.networkUnavailable()
        coordinator.reconcile(rig.transport, emptyList(), setOf("new"), emptySet(), 2)
        rig.transport.networkAvailable()
        rig.await { rig.transport.readyPathGenerations(setOf("new")).size == 3 }
        assertTrue(rig.transport.readyPathGenerations(setOf("old")).isEmpty())
        assertTrue(rig.transport.snapshot().values.all { it.activeSubscriptions == 1 })
    }
}
