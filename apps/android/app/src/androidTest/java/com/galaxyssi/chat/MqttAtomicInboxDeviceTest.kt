package com.galaxyssi.chat

import android.database.sqlite.SQLiteDatabase
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.SessionBuilder
import org.signal.libsignal.protocol.SessionCipher
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.kem.KEMPublicKey
import org.signal.libsignal.protocol.message.PreKeySignalMessage
import org.signal.libsignal.protocol.state.PreKeyBundle
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Uses isolated databases only; never resets the user's Signal identity or contacts. */
@RunWith(AndroidJUnit4::class)
class MqttAtomicInboxDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val databases = mutableListOf<AgentEncryptedDatabase>()
    private val peer = GalaxySSILinkInbox.Peer("pair-one", "sender", false)
    private val digest = "d".repeat(64)

    private fun database(): AgentEncryptedDatabase = AgentEncryptedDatabase(context,
        "test_link_atomic_${UUID.randomUUID().toString().replace("-", "")}").also { databases += it }

    private fun payload(id: String = "message", text: String = "value") =
        JSONObject().put("message_id", id).put("type", "text").put("content", text)

    private fun accept(store: GalaxySSILinkInbox, id: String = "message", text: String = "value",
                       scope: GalaxySSILinkInbox.Peer = peer, cipher: String = digest): GalaxySSILinkInbox.Accepted {
        val value = payload(id, text)
        return store.accept(scope, id, MqttImmutableContent.hash(value), value, cipher, true)
    }

    @After fun clearIsolatedData() {
        databases.forEach { GalaxySSILinkInbox(it).clear(); it.clear() }
    }

    @Test fun fullSynchronousWalIsEnabledForAtomicLinkStorage() {
        val db = database()
        db.indexedTransaction {
            it.rawQuery("PRAGMA synchronous", null).use { c -> assertTrue(c.moveToFirst()); assertEquals(2, c.getInt(0)) }
            it.rawQuery("PRAGMA journal_mode", null).use { c -> assertTrue(c.moveToFirst()); assertEquals("wal", c.getString(0)) }
        }
    }

    @Test fun wireReceiptProofSurvivesBodyCompactionAndReopen() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        val value = payload()
        val saved = inbox.accept(peer, "message", MqttImmutableContent.hash(value), value, digest, true, "e".repeat(64))
        assertEquals("e".repeat(64), inbox.storedReceipt(peer.scope, "message")?.wireHash)
        assertNull(inbox.storedReceipt("other-pair", "message"))
        assertTrue(inbox.complete(saved.payload))
        val reopened = GalaxySSILinkInbox(db)
        assertEquals("e".repeat(64), reopened.storedReceipt(peer.scope, "message")?.wireHash)
        assertTrue(reopened.storedReceipt(peer.scope, "message")!!.completed)
    }

    @Test fun rolledBackInboxCannotProduceStoredReceipt() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        assertThrows(IllegalStateException::class.java) {
            db.indexedTransaction {
                val value = payload()
                inbox.accept(peer, "message", MqttImmutableContent.hash(value), value, digest, true, "e".repeat(64))
                error("injected commit failure")
            }
        }
        assertNull(inbox.storedReceipt(peer.scope, "message"))
        assertNull(inbox.replay(peer.scope, digest))
    }

    @Test fun receiptMessagesDoNotRequestReceiptsEvenWithStoredWireProof() {
        val inbox = GalaxySSILinkInbox(database())
        val value = payload().put("type", "delivery_ack")
        inbox.accept(peer, "message", MqttImmutableContent.hash(value), value, digest, false, "e".repeat(64))
        assertNull(inbox.storedReceipt(peer.scope, "message"))
    }

    @Test fun oneCiphertextCannotAcquireAnotherReceiptDigest() {
        val inbox = GalaxySSILinkInbox(database())
        val value = payload()
        val hash = MqttImmutableContent.hash(value)
        inbox.accept(peer, "message", hash, value, digest, true, "e".repeat(64))
        assertThrows(IllegalStateException::class.java) {
            inbox.accept(peer, "message", hash, value, digest, true, "f".repeat(64))
        }
        assertEquals("e".repeat(64), inbox.storedReceipt(peer.scope, "message")?.wireHash)
    }

    @Test fun successfulAcceptancePersistsBodyAndBindingBeforeReplay() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        val stored = accept(inbox)
        assertEquals(GalaxySSILinkInbox.Stage.STORED, stored.stage)
        assertEquals(stored.recordKey, inbox.replay(peer.scope, digest)?.recordKey)
        assertEquals("value", JSONObject(inbox.pending().single().payload).getString("content"))
        SQLiteDatabase.openDatabase(db.storageIdentity, null, SQLiteDatabase.OPEN_READONLY).use { reader ->
            reader.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key LIKE 'rx:payload:%'", null).use {
                assertTrue(it.moveToFirst()); assertTrue(AgentStorageCipher.isEncrypted(it.getString(0)))
                assertFalse(it.getString(0).contains("\"content\":\"value\""))
            }
            reader.rawQuery("SELECT COUNT(*) FROM link_inbox_records", null).use {
                assertTrue(it.moveToFirst()); assertEquals(1, it.getInt(0))
            }
        }
    }

    @Test fun failureAfterInboxInsertionRollsBackEveryRowAndReplayBinding() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        assertThrows(IllegalStateException::class.java) {
            db.indexedTransaction {
                db.writeString("signal:record:sessions:test", "ratchet-update")
                accept(inbox)
                error("Injected failure before commit")
            }
        }
        assertFalse(db.contains("signal:record:sessions:test"))
        assertTrue(inbox.pending().isEmpty())
        assertNull(inbox.replay(peer.scope, digest))
        assertTrue(db.keys("rx:payload:").isEmpty())
        assertEquals(GalaxySSILinkInbox.Stage.STORED, accept(inbox).stage)
    }

    @Test fun sameIdDifferentContentCannotReplaceAcceptedBody() {
        val inbox = GalaxySSILinkInbox(database())
        accept(inbox)
        assertThrows(GalaxySSILinkInbox.ContentConflict::class.java) { accept(inbox, text = "changed", cipher = "e".repeat(64)) }
        assertNull(inbox.replay(peer.scope, "e".repeat(64)))
        assertEquals("value", JSONObject(inbox.pending().single().payload).getString("content"))
    }

    @Test fun sameMessageAndCipherIdsAreIndependentAcrossPairs() {
        val inbox = GalaxySSILinkInbox(database())
        val first = accept(inbox)
        val second = accept(inbox, text = "other", scope = peer.copy(scope = "pair-two", endpoint = "other"))
        assertNotEquals(first.recordKey, second.recordKey)
        assertEquals(2, inbox.pending().size)
        inbox.complete(first.payload)
        assertFalse(inbox.isPending(first.payload)); assertTrue(inbox.isPending(second.payload))
    }

    @Test fun concurrentBrokerCopiesCreateOneDurableRecord() {
        val inbox = GalaxySSILinkInbox(database())
        val executor = Executors.newFixedThreadPool(3)
        try {
            val results = (1..30).map { executor.submit<GalaxySSILinkInbox.Stage> { accept(inbox).stage } }
                .map { it.get(30, TimeUnit.SECONDS) }
            assertEquals(1, results.count { it == GalaxySSILinkInbox.Stage.STORED })
            assertEquals(29, results.count { it == GalaxySSILinkInbox.Stage.PENDING })
            assertEquals(1, inbox.pending().size)
        } finally { executor.shutdownNow(); assertTrue(executor.awaitTermination(5, TimeUnit.SECONDS)) }
    }

    @Test fun completionRetainsReplayTombstoneButNotPlaintextBody() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        val stored = accept(inbox)
        assertTrue(inbox.complete(stored.payload))
        assertTrue(inbox.pending().isEmpty()); assertTrue(db.keys("rx:payload:").isEmpty())
        assertTrue(inbox.replay(peer.scope, digest)!!.completed)
        assertEquals(GalaxySSILinkInbox.Stage.COMPLETED, accept(inbox).stage)
    }

    @Test fun idOnlyCompletionCannotAcknowledgeAnotherPair() {
        val inbox = GalaxySSILinkInbox(database())
        val stored = accept(inbox)
        assertFalse(inbox.complete(payload()))
        val changed = JSONObject(stored.payload.toString()).put("message_id", "other")
        assertThrows(IllegalStateException::class.java) { inbox.complete(changed) }
        assertTrue(inbox.isPending(stored.payload))
    }

    @Test fun unreadableBodyCannotProduceStoredReplayReceipt() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db)
        val stored = accept(inbox)
        db.remove("rx:payload:${stored.recordKey}")
        assertThrows(Exception::class.java) { inbox.replay(peer.scope, digest) }
        assertThrows(Exception::class.java) { accept(inbox) }
    }

    @Test fun quotaRejectsNewWorkWithoutEvictingPreviouslyAcceptedWork() {
        val inbox = GalaxySSILinkInbox(database(), maxRecords = 1)
        val first = accept(inbox)
        assertThrows(GalaxySSILinkInbox.CapacityExceeded::class.java) { accept(inbox, id = "second", cipher = "e".repeat(64)) }
        assertEquals(first.recordKey, inbox.pending().single().recordKey)
        assertNull(inbox.replay(peer.scope, "e".repeat(64)))
    }

    @Test fun onePairCannotConsumeOtherPairsQuota() {
        val inbox = GalaxySSILinkInbox(database(), maxPeerRecords = 1)
        accept(inbox)
        assertThrows(GalaxySSILinkInbox.CapacityExceeded::class.java) { accept(inbox, id = "second", cipher = "e".repeat(64)) }
        assertEquals(GalaxySSILinkInbox.Stage.STORED,
            accept(inbox, scope = peer.copy(scope = "other", endpoint = "other")).stage)
    }

    @Test fun completionAndRollbackUpdateByteQuotasAtomically() {
        val db = database()
        val inbox = GalaxySSILinkInbox(db, maxPendingBytes = 1000, maxPeerPendingBytes = 1000)
        val first = accept(inbox, text = "x".repeat(400))
        assertThrows(GalaxySSILinkInbox.CapacityExceeded::class.java) {
            accept(inbox, id = "second", text = "x".repeat(400), cipher = "e".repeat(64))
        }
        assertThrows(IllegalStateException::class.java) {
            db.indexedTransaction { inbox.complete(first.payload); error("rollback completion") }
        }
        assertTrue(inbox.isPending(first.payload))
        inbox.complete(first.payload)
        assertEquals(GalaxySSILinkInbox.Stage.STORED,
            accept(inbox, id = "second", text = "x".repeat(400), cipher = "e".repeat(64)).stage)
        db.indexedTransaction { sql ->
            sql.rawQuery("SELECT record_count FROM link_inbox_usage WHERE scope_digest=''", null).use {
                assertTrue(it.moveToFirst()); assertEquals(2, it.getInt(0))
            }
        }
    }

    @Test fun alternateCiphertextsForSameMessageAreBounded() {
        val inbox = GalaxySSILinkInbox(database())
        repeat(8) { accept(inbox, cipher = MqttImmutableContent.sha256(it.toString())) }
        assertThrows(GalaxySSILinkInbox.CapacityExceeded::class.java) { accept(inbox, cipher = MqttImmutableContent.sha256("9")) }
        assertNotNull(inbox.replay(peer.scope, MqttImmutableContent.sha256("0")))
    }

    @Test fun pruningNeverDropsPendingAcceptedWork() {
        var now = 1000L
        val inbox = GalaxySSILinkInbox(database(), now = { now })
        val completed = accept(inbox)
        accept(inbox, id = "pending", cipher = "e".repeat(64))
        inbox.complete(completed.payload)
        now += GalaxySSILinkInbox.RETENTION_MILLIS + 1
        assertEquals(1, inbox.pruneCompleted())
        assertEquals("pending", inbox.pending().single().messageId)
        assertNull(inbox.replay(peer.scope, digest))
        assertNotNull(inbox.replay(peer.scope, "e".repeat(64)))
    }

    @Test fun pendingReplayIsPagedAndPairRevocationIsScoped() {
        val inbox = GalaxySSILinkInbox(database())
        repeat(20) { accept(inbox, id = "m$it", cipher = MqttImmutableContent.sha256("c$it")) }
        accept(inbox, scope = peer.copy(scope = "other", endpoint = "other"))
        val first = inbox.pending(limit = 16)
        val second = inbox.pending(afterKey = first.last().recordKey)
        assertEquals(16, first.size); assertEquals(5, second.size)
        assertEquals(21, (first + second).map { it.recordKey }.toSet().size)
        assertEquals(20, inbox.forget(peer.scope))
        assertEquals("other", inbox.pending().single().peer.scope)
    }

    @Test fun recreatedRepositoriesObserveDurableCompletedState() {
        val db = database()
        val first = GalaxySSILinkInbox(db)
        val value = accept(first)
        val second = GalaxySSILinkInbox(db)
        assertEquals(GalaxySSILinkInbox.Stage.PENDING, accept(second).stage)
        second.complete(value.payload)
        assertTrue(first.replay(peer.scope, digest)!!.completed)
    }

    @Test fun realSignalRatchetAndPreKeyConsumptionRollBackWithInboxFailure() {
        val alice = AndroidPersistentSignalStore(context, database())
        val bobDatabase = database()
        val bob = AndroidPersistentSignalStore(context, bobDatabase)
        val inbox = GalaxySSILinkInbox(bobDatabase)
        val aliceAddress = SignalProtocolAddress("alice", 1)
        val bobAddress = SignalProtocolAddress("bob", 1)
        val bundle = bob.currentBundleJson("bob", 1)
        fun bytes(name: String) = Base64.decode(bundle.getString(name), Base64.DEFAULT)
        SessionBuilder(alice, bobAddress).process(PreKeyBundle(bundle.getInt("registrationId"), 1,
            bundle.getInt("preKeyId"), ECPublicKey(bytes("preKey")), bundle.getInt("signedPreKeyId"),
            ECPublicKey(bytes("signedPreKey")), bytes("signedPreKeySignature"), IdentityKey(bytes("identityKey")),
            bundle.getInt("kyberPreKeyId"), KEMPublicKey(bytes("kyberPreKey")), bytes("kyberPreKeySignature")))
        val plain = payload()
        val wire = SessionCipher(alice, bobAddress).encrypt(plain.toString().toByteArray()).serialize()
        val receiptHash = MqttDeliveryEnvelope.contentHash(JSONObject().put("scheme", "signal").put("from", "alice")
            .put("to", "bob").put("signal_type", "prekey").put("message_type", 3)
            .put("body", Base64.encodeToString(wire, Base64.NO_WRAP)))
        val before = MqttImmutableContent.hash(bob.exportJson())
        fun receive() = bob.transaction {
            val decrypted = SessionCipher(bob, aliceAddress).decrypt(PreKeySignalMessage(wire))
            val decoded = JSONObject(String(decrypted, Charsets.UTF_8))
            inbox.accept(peer, "message", MqttImmutableContent.hash(decoded), decoded, digest, true, receiptHash)
        }
        assertThrows(IllegalStateException::class.java) {
            bob.transaction { receive(); error("Injected post-decrypt persistence failure") }
        }
        assertEquals(before, MqttImmutableContent.hash(bob.exportJson()))
        assertFalse(bob.containsSession(aliceAddress)); assertTrue(bob.containsPreKey(bundle.getInt("preKeyId")))
        assertNull(inbox.replay(peer.scope, digest)); assertTrue(inbox.pending().isEmpty())
        assertNull(inbox.storedReceipt(peer.scope, "message"))
        assertEquals(GalaxySSILinkInbox.Stage.STORED, receive().stage)
        assertTrue(bob.containsSession(aliceAddress)); assertFalse(bob.containsPreKey(bundle.getInt("preKeyId")))
        assertNotNull(inbox.replay(peer.scope, digest))
        assertEquals(receiptHash, inbox.storedReceipt(peer.scope, "message")?.wireHash)
    }
}
