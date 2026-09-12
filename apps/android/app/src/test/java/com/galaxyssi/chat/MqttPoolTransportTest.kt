package com.galaxyssi.chat

import org.eclipse.paho.client.mqttv3.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class MqttPoolTransportTest {
    private val rig = MqttPoolTestRig()
    @After fun close() { rig.close() }

    @Test fun physicalConnectionCannotPublishBusinessBeforeAuthenticatedResume() {
        rig.start()
        assertThrows(MqttException::class.java) {
            rig.transport.publish("outbox", MqttMessage(byteArrayOf(1)).apply { qos = 1 })
        }
    }

    @Test fun subscriptionsRequireCompleteWindowOnOneBrokerNotUnionAcrossBrokers() {
        rig.autoSuback = false
        rig.start(setOf("first", "second"))
        rig.client("emqx").grant(setOf("first"))
        rig.client("hivemq").grant(setOf("second"))
        assertTrue(rig.subscriptionResults.isEmpty())
        assertTrue(rig.transport.readyPathGenerations(setOf("first", "second")).isEmpty())
        rig.client("mosquitto").grant(setOf("first", "second"))
        assertEquals(listOf(true), rig.subscriptionResults)
    }

    @Test fun noDefaultBrokerAndNoWaitingForAllThree() {
        rig.rejected = setOf("emqx", "hivemq")
        rig.start()
        assertEquals(setOf("mosquitto"), rig.transport.readyPathGenerations(setOf("inbox")).keys)
        assertTrue(rig.publish("mosquitto").isComplete)
    }

    @Test fun repeatedSubscriptionReplacesPendingWaiterAndLateSubackCompletesOnlyCurrentOne() {
        rig.autoSuback = false
        rig.start()
        repeat(1_100) { rig.subscribe(setOf("inbox")) }
        assertEquals(1_100, rig.subscriptionResults.count { !it })
        rig.client("hivemq").grant(setOf("inbox"))
        assertEquals(1, rig.subscriptionResults.count { it })
    }

    @Test fun bootstrapAcksDoNotLeakIntoBusinessDeliveryRegistration() {
        rig.start()
        val tokens = listOf("emqx", "hivemq", "mosquitto").map { rig.publish(it) }
        assertEquals(3, tokens.map { it.messageId }.toSet().size)
        assertTrue(tokens.all { it.isComplete })
        assertTrue(rig.completed.isEmpty())
        assertEquals(0, rig.transport.policy.diagnostics().inflightPackets)
    }

    @Test fun earlyFailureIsNotAnAcknowledgedToken() {
        rig.earlyFailure = true
        rig.start()
        val token = rig.publish("emqx")
        assertFalse(token.isComplete)
        assertNotNull(token.exception)
        assertEquals(0, rig.transport.policy.diagnostics().inflightPackets)
    }

    @Test fun failingOnePathDoesNotFailOtherPendingTokensOrAggregateConnection() {
        rig.earlyAck = false
        rig.start()
        val first = rig.publish("emqx")
        val second = rig.publish("hivemq")
        rig.client("emqx").lose()
        assertNotNull(first.exception)
        assertNull(second.exception)
        assertFalse(second.isComplete)
        rig.client("hivemq").sent.single().let { it.listener.onSuccess(it.token) }
        assertTrue(second.isComplete)
        assertEquals(listOf(true), rig.connectionStates)
    }

    @Test fun globalWindowReservesControlSlotsWithoutTriplingBudget() {
        rig.earlyAck = false
        rig.start()
        repeat(12) { rig.publish(listOf("emqx", "hivemq", "mosquitto")[it % 3]) }
        assertThrows(MqttException::class.java) { rig.publish("emqx") }
        assertEquals(12, rig.transport.policy.diagnostics().inflightPackets)
    }

    @Test fun stalledPathRepairRetainsOtherFreshPublication() {
        rig.earlyAck = false
        rig.start()
        val old = rig.publish("emqx")
        rig.clock.addAndGet(25_000)
        val fresh = rig.publish("hivemq")
        rig.clock.addAndGet(5_000)
        rig.transport.repair()
        assertNotNull(old.exception)
        assertNull(fresh.exception)
        assertTrue(rig.transport.isConnected)
    }

    @Test fun unsubscribeRevokesReadinessBeforeLateCallback() {
        rig.autoSuback = false
        rig.start()
        rig.transport.unsubscribe(arrayOf("inbox"), null, object : IMqttActionListener {
            override fun onSuccess(asyncActionToken: IMqttToken?) = Unit
            override fun onFailure(asyncActionToken: IMqttToken?, exception: Throwable?) = Unit
        })
        rig.client("emqx").grant(setOf("inbox"))
        assertTrue(rig.transport.readyPathGenerations(setOf("inbox")).isEmpty())
        assertEquals(listOf(false), rig.subscriptionResults)
    }

    @Test fun offlineStartupWaitsForNetworkBeforeCreatingClients() {
        rig.transport.networkUnavailable()
        rig.subscribe(setOf("inbox"))
        rig.transport.start()
        Thread.sleep(50)
        assertTrue(rig.clients.isEmpty())
        rig.transport.networkAvailable("wifi-test")
        rig.await { rig.transport.readyPathGenerations(setOf("inbox")).size == 3 }
    }

    @Test fun networkLossSuspendsAllRetriesAndNetworkReturnRestoresSamePool() {
        rig.start()
        rig.transport.networkUnavailable()
        assertFalse(rig.transport.isConnected)
        val clients = rig.clients.values.sumOf { it.size }
        Thread.sleep(50)
        assertEquals(clients, rig.clients.values.sumOf { it.size })
        rig.transport.networkAvailable("cellular-test")
        rig.await { rig.transport.readyPathGenerations(setOf("inbox")).values.toSet() == setOf(2L) }
        assertEquals(6, rig.clients.values.sumOf { it.size })
    }
}
