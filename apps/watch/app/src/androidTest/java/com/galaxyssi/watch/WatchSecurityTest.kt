package com.galaxyssi.watch

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.AgentEncryptedPreferences
import com.galaxyssi.chat.AndroidPersistentSignalStore
import com.galaxyssi.chat.GalaxySSILinkProtocol as Link
import com.galaxyssi.chat.GalaxySSILinkDeliveryStore
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class WatchSecurityTest {
    // Instrumentation package contexts have no Application. Use a wrapper with
    // separate preference/database names so tests cannot touch user identities.
    private class TestContext(base: Context, private val scope: String) : ContextWrapper(base) {
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String, mode: Int) = super.getSharedPreferences("watch-test-$scope-$name", mode)
        override fun getDatabasePath(name: String) = super.getDatabasePath("watch-test-$scope-$name")
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?) =
            baseContext.openOrCreateDatabase("watch-test-$scope-$name", mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?) =
            baseContext.openOrCreateDatabase("watch-test-$scope-$name", mode, factory, handler)
    }
    private val context get() = TestContext(InstrumentationRegistry.getInstrumentation().targetContext, "storage")

    @Test fun encryptedStorageSurvivesReopenAndIsNotPlaintext() {
        val namespace = "test-${UUID.randomUUID()}"
        val encrypted = AgentEncryptedPreferences(context, namespace)
        encrypted.writeString("draft", "Confidential watch draft")
        assertEquals("Confidential watch draft", AgentEncryptedPreferences(context, namespace).readString("draft", ""))
        val raw = context.getSharedPreferences(namespace, 0).getString("draft", "")!!
        assertFalse(raw.contains("Confidential"))
        encrypted.clear()
    }

    @Test(expected = UnsupportedOperationException::class)
    fun phonePersonalMemoryCannotBeOpenedByWatchStorage() {
        com.galaxyssi.chat.AgentEncryptedDatabase(context, "galaxyssi_agent_memory_v2").writeString("test", "value")
    }

    @Test fun unreadStatePersistsAndNewReplyBecomesUnread() {
        val store = WatchStore(context)
        val task = WatchTask.create("test", "route", "agent", "Prompt")
            .copy(state = TaskState.COMPLETED, reply = "First reply")
        assertTrue(store.unread(task))
        store.markRead(listOf(task))
        assertFalse(WatchStore(context).unread(task))
        assertTrue(store.unread(task.copy(reply = "Updated reply")))
    }

    @Test fun phoneSignalIdentityLoadsOnWatchAndPersists() {
        val first = AndroidPersistentSignalStore(context)
        val second = AndroidPersistentSignalStore(context)
        assertArrayEquals(first.identityKeyPair.publicKey.serialize(), second.identityKeyPair.publicKey.serialize())
        val bundle = first.currentBundleJson("test-watch", 1)
        assertTrue(bundle.getString("identityKey").isNotBlank())
        assertTrue(bundle.getString("kyberPreKey").isNotBlank())
    }

    @Test fun legacySignalUpgradePreservesRecordsAndNeverOverwritesCurrentIdentity() {
        val isolated = TestContext(InstrumentationRegistry.getInstrumentation().targetContext, UUID.randomUUID().toString())
        val original = AndroidPersistentSignalStore(isolated).exportJson()
        val legacy = AgentEncryptedPreferences(isolated, "galaxyssi_signal_store")
        original.keys().forEach { legacy.writeString(it, original.getString(it)) }
        AndroidPersistentSignalStore.clear(isolated)
        com.galaxyssi.chat.WatchSignalUpgrade.prepare(isolated)
        val restored = AndroidPersistentSignalStore(isolated).exportJson()
        original.keys().forEach { assertEquals(original.getString(it), restored.getString(it)) }
        legacy.writeString("identity_key_pair", "invalid legacy value")
        com.galaxyssi.chat.WatchSignalUpgrade.prepare(isolated)
        assertEquals(original.getString("identity_key_pair"), AndroidPersistentSignalStore(isolated).exportJson().getString("identity_key_pair"))
        legacy.clear()
        AndroidPersistentSignalStore.clear(isolated)
    }

    @Test fun revocationRemovesOnlyTheMatchingOutboxRoute() {
        val store = WatchStore(context)
        val first = Link.Routes(Link.newRouteId(), Link.newLinkSecret(), "watch-a", "desktop-a")
        val second = Link.Routes(Link.newRouteId(), Link.newLinkSecret(), "watch-b", "desktop-b")
        val firstId = UUID.randomUUID().toString(); val secondId = UUID.randomUUID().toString()
        store.outbox.writeString(firstId, JSONObject().put("client_route_id", first.clientRouteId).toString())
        store.outbox.writeString(secondId, JSONObject().put("client_route_id", second.clientRouteId).toString())
        GalaxySSILinkDeliveryStore.discardRoutes(context, first)
        assertFalse(store.outbox.contains(firstId))
        assertTrue(store.outbox.contains(secondId))
        store.outbox.remove(secondId)
    }

    @Test fun nativeSignalSessionEncryptsAndDecryptsAcrossIdentities() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val scope = UUID.randomUUID().toString()
        val local = AndroidPersistentSignalStore(TestContext(base, "$scope-sender"))
        val remote = AndroidPersistentSignalStore(TestContext(base, "$scope-receiver"))
        val bundle = remote.currentBundleJson("receiver", 1)
        fun decode(field: String) = android.util.Base64.decode(bundle.getString(field), android.util.Base64.NO_WRAP)
        val remoteAddress = org.signal.libsignal.protocol.SignalProtocolAddress("receiver", 1)
        org.signal.libsignal.protocol.SessionBuilder(local, remoteAddress).process(
            org.signal.libsignal.protocol.state.PreKeyBundle(bundle.getInt("registrationId"), 1,
                bundle.getInt("preKeyId"), org.signal.libsignal.protocol.ecc.ECPublicKey(decode("preKey")),
                bundle.getInt("signedPreKeyId"), org.signal.libsignal.protocol.ecc.ECPublicKey(decode("signedPreKey")),
                decode("signedPreKeySignature"), org.signal.libsignal.protocol.IdentityKey(decode("identityKey")),
                bundle.getInt("kyberPreKeyId"), org.signal.libsignal.protocol.kem.KEMPublicKey(decode("kyberPreKey")), decode("kyberPreKeySignature")))
        val payload = Link.makeEnvelope(JSONObject().put("type", "text").put("content", "watch-test"), "sender", "receiver")
        val encrypted = org.signal.libsignal.protocol.SessionCipher(local, remoteAddress).encrypt(payload.toString().toByteArray())
        val cipher = org.signal.libsignal.protocol.SessionCipher(remote, org.signal.libsignal.protocol.SignalProtocolAddress("sender", 1))
        val bytes = encrypted.serialize()
        val decoded = if (encrypted.type == org.signal.libsignal.protocol.message.CiphertextMessage.PREKEY_TYPE) {
            cipher.decrypt(org.signal.libsignal.protocol.message.PreKeySignalMessage(bytes))
        } else cipher.decrypt(org.signal.libsignal.protocol.message.SignalMessage(bytes))
        assertEquals("watch-test", JSONObject(String(decoded)).getJSONObject("payload").getString("content"))
    }
}
