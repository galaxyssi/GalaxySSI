package com.galaxyssi.chat

import android.content.Context
import android.util.Base64
import org.json.JSONObject
import org.signal.libsignal.protocol.IdentityKey
import org.signal.libsignal.protocol.IdentityKeyPair
import org.signal.libsignal.protocol.InvalidKeyIdException
import org.signal.libsignal.protocol.NoSessionException
import org.signal.libsignal.protocol.SignalProtocolAddress
import org.signal.libsignal.protocol.ecc.ECKeyPair
import org.signal.libsignal.protocol.ecc.ECPublicKey
import org.signal.libsignal.protocol.kem.KEMKeyPair
import org.signal.libsignal.protocol.kem.KEMKeyType
import org.signal.libsignal.protocol.groups.state.SenderKeyRecord
import org.signal.libsignal.protocol.state.IdentityKeyStore
import org.signal.libsignal.protocol.state.KyberPreKeyRecord
import org.signal.libsignal.protocol.state.PreKeyRecord
import org.signal.libsignal.protocol.state.SessionRecord
import org.signal.libsignal.protocol.state.SignalProtocolStore
import org.signal.libsignal.protocol.state.SignedPreKeyRecord
import org.signal.libsignal.protocol.util.KeyHelper
import java.util.UUID

class AndroidPersistentSignalStore(
    context: Context,
    private val prefs: AgentEncryptedDatabase = database(context)
) : SignalProtocolStore {
    private val identityKeyPair: IdentityKeyPair
    private val registrationId: Int

    init {
        val material = transaction {
            val identityRaw = prefs.readString(KEY_IDENTITY, "")
            if (identityRaw.isBlank()) {
                check(!prefs.contains(KEY_IDENTITY)) { "Encrypted Signal identity is unreadable" }
                val identity = IdentityKeyPair.generate()
                val registration = KeyHelper.generateRegistrationId(false)
                prefs.writeString(KEY_IDENTITY, b64e(identity.serialize()))
                prefs.writeString(KEY_REGISTRATION_ID, registration.toString())
                Triple(identity, registration, true)
            } else {
                Triple(IdentityKeyPair(b64d(identityRaw)),
                    prefs.readString(KEY_REGISTRATION_ID, "").toIntOrNull()
                        ?: error("Encrypted Signal registration ID is missing"), false)
            }
        }
        identityKeyPair = material.first
        registrationId = material.second
        transaction { ensurePreKeyMaterial(newIdentity = material.third) }
    }

    internal fun <T> transaction(block: () -> T): T = prefs.indexedTransaction { block() }

    override fun getIdentityKeyPair(): IdentityKeyPair = identityKeyPair

    override fun getLocalRegistrationId(): Int = registrationId

    override fun saveIdentity(address: SignalProtocolAddress, identityKey: IdentityKey): IdentityKeyStore.IdentityChange {
        val key = addressKey(address)
        val encoded = b64e(identityKey.serialize())
        val existing = readRecord(KEY_IDENTITIES, key)
        prefs.writeString(recordKey(KEY_IDENTITIES, key), encoded)
        return if (existing.isNotBlank() && existing != encoded) {
            IdentityKeyStore.IdentityChange.REPLACED_EXISTING
        } else {
            IdentityKeyStore.IdentityChange.NEW_OR_UNCHANGED
        }
    }

    override fun isTrustedIdentity(
        address: SignalProtocolAddress,
        identityKey: IdentityKey,
        direction: IdentityKeyStore.Direction
    ): Boolean {
        val existing = readRecord(KEY_IDENTITIES, addressKey(address))
        return existing.isBlank() || existing == b64e(identityKey.serialize())
    }

    override fun getIdentity(address: SignalProtocolAddress): IdentityKey? {
        val encoded = readRecord(KEY_IDENTITIES, addressKey(address))
        return if (encoded.isBlank()) null else runCatching { IdentityKey(b64d(encoded)) }.getOrNull()
    }

    override fun loadPreKey(preKeyId: Int): PreKeyRecord {
        val encoded = readRecord(KEY_PRE_KEYS, preKeyId.toString())
        if (encoded.isBlank()) throw InvalidKeyIdException("No pre-key: $preKeyId")
        return PreKeyRecord(b64d(encoded))
    }

    override fun storePreKey(preKeyId: Int, record: PreKeyRecord) {
        putRecord(KEY_PRE_KEYS, preKeyId.toString(), record.serialize())
    }

    override fun containsPreKey(preKeyId: Int): Boolean =
        prefs.contains(recordKey(KEY_PRE_KEYS, preKeyId.toString()))

    override fun removePreKey(preKeyId: Int) {
        removeRecord(KEY_PRE_KEYS, preKeyId.toString())
    }

    override fun loadSession(address: SignalProtocolAddress): SessionRecord {
        val encoded = readRecord(KEY_SESSIONS, addressKey(address))
        return if (encoded.isBlank()) SessionRecord() else SessionRecord(b64d(encoded))
    }

    override fun loadExistingSessions(addresses: MutableList<SignalProtocolAddress>): MutableList<SessionRecord> {
        val result = mutableListOf<SessionRecord>()
        addresses.forEach { address ->
            if (!containsSession(address)) throw NoSessionException(address, "No session")
            result.add(loadSession(address))
        }
        return result
    }

    override fun getSubDeviceSessions(name: String): MutableList<Int> {
        val prefix = "$name|"
        return recordNames(KEY_SESSIONS).asSequence()
            .filter { it.startsWith(prefix) }
            .mapNotNull { it.removePrefix(prefix).toIntOrNull() }
            .toMutableList()
    }

    override fun storeSession(address: SignalProtocolAddress, record: SessionRecord) {
        putRecord(KEY_SESSIONS, addressKey(address), record.serialize())
    }

    override fun containsSession(address: SignalProtocolAddress): Boolean =
        prefs.contains(recordKey(KEY_SESSIONS, addressKey(address)))

    override fun deleteSession(address: SignalProtocolAddress) {
        removeRecord(KEY_SESSIONS, addressKey(address))
    }

    override fun deleteAllSessions(name: String) {
        val prefix = "$name|"
        prefs.removeAll(recordNames(KEY_SESSIONS).filter { it.startsWith(prefix) }.map { recordKey(KEY_SESSIONS, it) })
    }

    fun deleteIdentity(address: SignalProtocolAddress) {
        removeRecord(KEY_IDENTITIES, addressKey(address))
    }

    fun deleteSenderKeys(name: String) {
        val prefix = "$name|"
        prefs.removeAll(recordNames(KEY_SENDER_KEYS).filter { it.startsWith(prefix) }.map { recordKey(KEY_SENDER_KEYS, it) })
    }

    fun currentBundleJson(name: String, deviceId: Int): JSONObject = transaction {
        val preKeyId = ensurePreKeyMaterial()
        val preKey = loadPreKey(preKeyId)
        val signedPreKey = loadSignedPreKey(DEFAULT_SIGNED_PRE_KEY_ID)
        val kyberPreKey = loadKyberPreKey(DEFAULT_KYBER_PRE_KEY_ID)
        JSONObject()
            .put("version", 1)
            .put("scheme", "signal")
            .put("name", name)
            .put("deviceId", deviceId)
            .put("registrationId", registrationId)
            .put("identityKey", b64e(identityKeyPair.publicKey.serialize()))
            .put("preKeyId", preKeyId)
            .put("preKey", b64e(preKey.keyPair.publicKey.serialize()))
            .put("signedPreKeyId", DEFAULT_SIGNED_PRE_KEY_ID)
            .put("signedPreKey", b64e(signedPreKey.keyPair.publicKey.serialize()))
            .put("signedPreKeySignature", b64e(signedPreKey.signature))
            .put("kyberPreKeyId", DEFAULT_KYBER_PRE_KEY_ID)
            .put("kyberPreKey", b64e(kyberPreKey.keyPair.publicKey.serialize()))
            .put("kyberPreKeySignature", b64e(kyberPreKey.signature))
    }

    override fun loadSignedPreKey(signedPreKeyId: Int): SignedPreKeyRecord {
        val encoded = readRecord(KEY_SIGNED_PRE_KEYS, signedPreKeyId.toString())
        if (encoded.isBlank()) throw InvalidKeyIdException("No signed pre-key: $signedPreKeyId")
        return SignedPreKeyRecord(b64d(encoded))
    }

    override fun loadSignedPreKeys(): MutableList<SignedPreKeyRecord> {
        val records = readJson(KEY_SIGNED_PRE_KEYS)
        return records.keys().asSequence()
            .mapNotNull { runCatching { SignedPreKeyRecord(b64d(records.getString(it))) }.getOrNull() }
            .toMutableList()
    }

    override fun storeSignedPreKey(signedPreKeyId: Int, record: SignedPreKeyRecord) {
        putRecord(KEY_SIGNED_PRE_KEYS, signedPreKeyId.toString(), record.serialize())
    }

    override fun containsSignedPreKey(signedPreKeyId: Int): Boolean =
        prefs.contains(recordKey(KEY_SIGNED_PRE_KEYS, signedPreKeyId.toString()))

    override fun removeSignedPreKey(signedPreKeyId: Int) {
        removeRecord(KEY_SIGNED_PRE_KEYS, signedPreKeyId.toString())
    }

    override fun storeSenderKey(address: SignalProtocolAddress, distributionId: UUID, record: SenderKeyRecord) {
        putRecord(KEY_SENDER_KEYS, "${addressKey(address)}|$distributionId", record.serialize())
    }

    override fun loadSenderKey(address: SignalProtocolAddress, distributionId: UUID): SenderKeyRecord? {
        val encoded = readRecord(KEY_SENDER_KEYS, "${addressKey(address)}|$distributionId")
        return if (encoded.isBlank()) null else runCatching { SenderKeyRecord(b64d(encoded)) }.getOrNull()
    }

    override fun loadKyberPreKey(kyberPreKeyId: Int): KyberPreKeyRecord {
        val encoded = readRecord(KEY_KYBER_PRE_KEYS, kyberPreKeyId.toString())
        if (encoded.isBlank()) throw InvalidKeyIdException("No kyber pre-key: $kyberPreKeyId")
        return KyberPreKeyRecord(b64d(encoded))
    }

    override fun loadKyberPreKeys(): MutableList<KyberPreKeyRecord> {
        val records = readJson(KEY_KYBER_PRE_KEYS)
        return records.keys().asSequence()
            .mapNotNull { runCatching { KyberPreKeyRecord(b64d(records.getString(it))) }.getOrNull() }
            .toMutableList()
    }

    override fun storeKyberPreKey(kyberPreKeyId: Int, record: KyberPreKeyRecord) {
        putRecord(KEY_KYBER_PRE_KEYS, kyberPreKeyId.toString(), record.serialize())
    }

    override fun containsKyberPreKey(kyberPreKeyId: Int): Boolean =
        prefs.contains(recordKey(KEY_KYBER_PRE_KEYS, kyberPreKeyId.toString()))

    override fun markKyberPreKeyUsed(kyberPreKeyId: Int, signedPreKeyId: Int, baseKey: ECPublicKey) = Unit

    private fun ensurePreKeyMaterial(newIdentity: Boolean = false): Int {
        val storedActiveId = prefs.readString(KEY_ACTIVE_PRE_KEY_ID, "")
            .toIntOrNull()
            ?.takeIf(::validPreKeyId)
        val reusableId = storedActiveId
            ?.takeIf(::hasValidPreKey)
            ?: if (storedActiveId == null) existingValidPreKeyId() else null
        val activeId = reusableId ?: nextAvailablePreKeyId(
            when {
                storedActiveId != null -> storedActiveId
                newIdentity -> 0
                else -> DEFAULT_PRE_KEY_ID
            }
        ).also { preKeyId ->
            storePreKey(preKeyId, PreKeyRecord(preKeyId, ECKeyPair.generate()))
        }
        if (storedActiveId != activeId) {
            prefs.writeString(KEY_ACTIVE_PRE_KEY_ID, activeId.toString())
        }

        if (!hasValidSignedPreKey(DEFAULT_SIGNED_PRE_KEY_ID)) {
            val signedPreKeyPair = ECKeyPair.generate()
            val signature = identityKeyPair.privateKey.calculateSignature(signedPreKeyPair.publicKey.serialize())
            storeSignedPreKey(
                DEFAULT_SIGNED_PRE_KEY_ID,
                SignedPreKeyRecord(DEFAULT_SIGNED_PRE_KEY_ID, System.currentTimeMillis(), signedPreKeyPair, signature)
            )
        }
        if (!hasValidKyberPreKey(DEFAULT_KYBER_PRE_KEY_ID)) {
            val kyberPair = KEMKeyPair.generate(KEMKeyType.KYBER_1024)
            val signature = identityKeyPair.privateKey.calculateSignature(kyberPair.publicKey.serialize())
            storeKyberPreKey(
                DEFAULT_KYBER_PRE_KEY_ID,
                KyberPreKeyRecord(DEFAULT_KYBER_PRE_KEY_ID, System.currentTimeMillis(), kyberPair, signature)
            )
        }
        return activeId
    }

    private fun existingValidPreKeyId(): Int? {
        val records = readJson(KEY_PRE_KEYS)
        return records.keys().asSequence()
            .mapNotNull(String::toIntOrNull)
            .filter(::validPreKeyId)
            .sorted()
            .firstOrNull(::hasValidPreKey)
    }

    private fun nextAvailablePreKeyId(afterId: Int): Int {
        val occupied = readJson(KEY_PRE_KEYS).keys().asSequence()
            .mapNotNull(String::toIntOrNull)
            .filter(::validPreKeyId)
            .toSet()
        var candidate = nextPreKeyId(afterId)
        repeat(occupied.size + 1) {
            if (candidate !in occupied) return candidate
            candidate = nextPreKeyId(candidate)
        }
        error("No Signal pre-key ID is available")
    }

    private fun hasValidPreKey(preKeyId: Int): Boolean =
        containsPreKey(preKeyId) && runCatching { loadPreKey(preKeyId) }.isSuccess

    private fun hasValidSignedPreKey(preKeyId: Int): Boolean =
        containsSignedPreKey(preKeyId) && runCatching { loadSignedPreKey(preKeyId) }.isSuccess

    private fun hasValidKyberPreKey(preKeyId: Int): Boolean =
        containsKyberPreKey(preKeyId) && runCatching { loadKyberPreKey(preKeyId) }.isSuccess

    private fun validPreKeyId(preKeyId: Int): Boolean = preKeyId in 1..MAX_PRE_KEY_ID

    private fun nextPreKeyId(preKeyId: Int): Int =
        if (preKeyId in 1 until MAX_PRE_KEY_ID) preKeyId + 1 else DEFAULT_PRE_KEY_ID

    private fun putRecord(prefKey: String, recordId: String, bytes: ByteArray) {
        prefs.writeString(recordKey(prefKey, recordId), b64e(bytes))
    }

    private fun removeRecord(prefKey: String, recordId: String) {
        prefs.remove(recordKey(prefKey, recordId))
    }

    private fun readRecord(prefKey: String, key: String): String {
        val storageKey = recordKey(prefKey, key)
        val value = prefs.readString(storageKey, "")
        check(value.isNotBlank() || !prefs.contains(storageKey)) { "Encrypted Signal record is unreadable" }
        return value
    }

    private fun recordNames(prefKey: String): List<String> = prefs.keys(recordPrefix(prefKey)).map { it.removePrefix(recordPrefix(prefKey)) }

    private fun readJson(prefKey: String): JSONObject = JSONObject().also { result ->
        recordNames(prefKey).forEach { result.put(it, readRecord(prefKey, it)) }
    }

    fun exportJson(): JSONObject = transaction {
        val root = JSONObject()
        STORED_KEYS.forEach { key ->
            val value = if (key in RECORD_COLLECTIONS) readJson(key).toString() else prefs.readString(key, "")
            value.takeIf(String::isNotBlank)?.let { root.put(key, it) }
        }
        root
    }

    companion object {
        internal const val DATABASE = "galaxyssi_link_state_v3"
        private const val KEY_IDENTITY = "identity_key_pair"
        private const val KEY_REGISTRATION_ID = "registration_id"
        private const val KEY_IDENTITIES = "identities"
        private const val KEY_PRE_KEYS = "pre_keys"
        private const val KEY_ACTIVE_PRE_KEY_ID = "active_pre_key_id"
        private const val KEY_SIGNED_PRE_KEYS = "signed_pre_keys"
        private const val KEY_KYBER_PRE_KEYS = "kyber_pre_keys"
        private const val KEY_SESSIONS = "sessions"
        private const val KEY_SENDER_KEYS = "sender_keys"
        private const val DEFAULT_PRE_KEY_ID = 1
        private const val MAX_PRE_KEY_ID = 0xFFFFFF
        private const val DEFAULT_SIGNED_PRE_KEY_ID = 1
        private const val DEFAULT_KYBER_PRE_KEY_ID = 1
        private val STORED_KEYS = listOf(
            KEY_IDENTITY,
            KEY_REGISTRATION_ID,
            KEY_IDENTITIES,
            KEY_PRE_KEYS,
            KEY_ACTIVE_PRE_KEY_ID,
            KEY_SIGNED_PRE_KEYS,
            KEY_KYBER_PRE_KEYS,
            KEY_SESSIONS,
            KEY_SENDER_KEYS
        )
        private val RECORD_COLLECTIONS = setOf(KEY_IDENTITIES, KEY_PRE_KEYS, KEY_SIGNED_PRE_KEYS,
            KEY_KYBER_PRE_KEYS, KEY_SESSIONS, KEY_SENDER_KEYS)

        internal fun database(context: Context): AgentEncryptedDatabase =
            AgentEncryptedDatabase(context.applicationContext, DATABASE)

        private fun recordPrefix(collection: String): String = "signal:record:$collection:"
        private fun recordKey(collection: String, id: String): String = recordPrefix(collection) + id

        fun clear(context: Context) {
            val db = database(context)
            db.removeAll(STORED_KEYS + db.keys("signal:record:"))
        }

        fun importJson(context: Context, value: JSONObject) {
            val preferences = database(context)
            preferences.indexedTransaction {
                clear(context)
                STORED_KEYS.forEach { key ->
                    value.optString(key).takeIf(String::isNotBlank)?.let { raw ->
                        if (key in RECORD_COLLECTIONS) {
                            val records = JSONObject(raw)
                            records.keys().forEach { name -> preferences.writeString(recordKey(key, name), records.getString(name)) }
                        } else preferences.writeString(key, raw)
                    }
                }
            }
        }

        private fun addressKey(address: SignalProtocolAddress): String =
            "${address.name}|${address.deviceId}"

        private fun b64e(value: ByteArray): String =
            Base64.encodeToString(value, Base64.NO_WRAP)

        private fun b64d(value: String): ByteArray =
            Base64.decode(value, Base64.DEFAULT)
    }
}
