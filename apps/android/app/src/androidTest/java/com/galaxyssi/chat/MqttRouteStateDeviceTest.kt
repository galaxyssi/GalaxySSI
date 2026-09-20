package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class MqttRouteStateDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val sender = "a".repeat(64)
    private val receiver = "b".repeat(64)

    private fun withStore(block: (MqttRouteState, AgentEncryptedDatabase, String) -> Unit) {
        val name = "mqtt_route_test_${UUID.randomUUID().toString().replace("-", "")}"
        val database = AgentEncryptedDatabase(context, name)
        try { block(MqttRouteState(database), database, name) }
        finally { database.close(); context.deleteDatabase("$name.db") }
    }

    private fun issue(store: MqttRouteState, peer: String = "peer", now: Long = 1000) =
        store.issueLocalResume(peer, sender, receiver, MqttBrokerCatalog.brokers.keys, now)

    @Test fun separateStoreInstancesSharePersistedEpochAndRemainPairScoped() = withStore { store, _, name ->
        assertEquals(1000L, issue(store).epoch)
        assertEquals(1000L, issue(store, "other").epoch)
        val reopened = AgentEncryptedDatabase(context, name)
        try { assertEquals(1001L, issue(MqttRouteState(reopened)).epoch) }
        finally { reopened.close() }
    }

    @Test fun tenWindowsAdvanceOneSharedEpochAtomically() = withStore { _, database, _ ->
        val executor = Executors.newFixedThreadPool(10)
        try {
            val results = (1..30).map { executor.submit<Long> { issue(MqttRouteState(database)).epoch } }
                .map { it.get(30, TimeUnit.SECONDS) }.sorted()
            assertEquals((1000L..1029L).toList(), results)
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun replayAndSameEpochMutationCannotReplacePersistedCapability() = withStore { store, _, _ ->
        val old = issue(store)
        val latest = issue(store)
        assertEquals(MqttRouteState.Result.NEW, store.recordVerifiedResume("peer", latest, 1000))
        assertEquals(MqttRouteState.Result.DUPLICATE, store.recordVerifiedResume("peer", latest, 2000))
        assertEquals(MqttRouteState.Result.STALE, store.recordVerifiedResume("peer", old, 2000))
        assertEquals(MqttRouteState.Result.CONFLICT, store.recordVerifiedResume("peer",
            latest.copy(receiveBrokers = setOf("emqx")), 2000))
        assertEquals(latest, store.loadVerifiedResume("peer", sender, receiver, 2000))
    }

    @Test fun expiredCapabilityKeepsAntiReplayWatermark() = withStore { store, _, _ ->
        val original = issue(store)
        store.recordVerifiedResume("peer", original, 1000)
        assertNull(store.loadVerifiedResume("peer", sender, receiver, 500_000))
        assertEquals(MqttRouteState.Result.CONFLICT, store.recordVerifiedResume("peer",
            original.copy(issuedAtMs = 500_000, expiresAtMs = 800_000), 500_000))
    }

    @Test fun revokingOnePairDoesNotDeleteOtherPairOrBusinessRecords() = withStore { store, database, _ ->
        store.recordVerifiedResume("peer", issue(store), 1000)
        store.recordVerifiedResume("other", issue(store, "other"), 1000)
        database.writeString("pending:unrelated-message", "retained")
        store.forgetRoute("peer")
        assertNull(store.loadVerifiedResume("peer", sender, receiver, 1000))
        assertNotNull(store.loadVerifiedResume("other", sender, receiver, 1000))
        assertEquals("retained", database.readString("pending:unrelated-message", ""))
    }

    @Test fun readdingSameIdentityDoesNotRollBackEpochOrForgetReplayProtection() = withStore { store, _, _ ->
        val previous = issue(store)
        assertEquals(MqttRouteState.Result.NEW, store.recordVerifiedResume("peer", previous, 1000))
        store.forgetRoute("peer")
        assertNull(store.loadVerifiedResume("peer", sender, receiver, 1000))
        val renewed = issue(store, now = 900) // Clock rollback must also preserve ordering.
        assertTrue(renewed.epoch > previous.epoch)
        assertEquals(MqttRouteState.Result.CONFLICT, store.recordVerifiedResume("peer",
            previous.copy(resumeId = "f".repeat(32)), 1000))
        assertEquals(MqttRouteState.Result.NEW, store.recordVerifiedResume("peer", renewed, 1000))
    }

    @Test fun upgradesPastLegacyCounterEvenIfOldReleaseErasedIt() = withStore { store, database, _ ->
        database.writeString("multipath:local:${MqttRouteAdvertisement.sha256("peer")}", "42")
        assertTrue(issue(store, now = 2000).epoch > 42)
    }

    @Test fun invalidCounterCannotResetAnExistingRouteEpoch() = withStore { store, database, _ ->
        issue(store)
        database.writeString("multipath:local:${MqttRouteAdvertisement.sha256("peer")}", "-1")
        assertThrows(IllegalStateException::class.java) { issue(store) }
    }
}
