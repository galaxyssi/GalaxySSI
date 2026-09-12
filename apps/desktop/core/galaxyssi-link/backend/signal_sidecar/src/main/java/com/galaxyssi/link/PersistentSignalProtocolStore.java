package com.galaxyssi.link;

import org.json.JSONObject;
import org.signal.libsignal.protocol.IdentityKey;
import org.signal.libsignal.protocol.IdentityKeyPair;
import org.signal.libsignal.protocol.InvalidKeyIdException;
import org.signal.libsignal.protocol.NoSessionException;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.ecc.ECPublicKey;
import org.signal.libsignal.protocol.groups.state.SenderKeyRecord;
import org.signal.libsignal.protocol.state.IdentityKeyStore;
import org.signal.libsignal.protocol.state.KyberPreKeyRecord;
import org.signal.libsignal.protocol.state.PreKeyRecord;
import org.signal.libsignal.protocol.state.SessionRecord;
import org.signal.libsignal.protocol.state.SignalProtocolStore;
import org.signal.libsignal.protocol.state.SignedPreKeyRecord;
import org.signal.libsignal.protocol.util.KeyHelper;

import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;
import java.util.UUID;

final class PersistentSignalProtocolStore implements SignalProtocolStore, AutoCloseable {
    final SignalStateDatabase database;
    private final IdentityKeyPair identityKeyPair;
    private final int registrationId;

    PersistentSignalProtocolStore(Path path, byte[] storageKey) throws Exception {
        database = new SignalStateDatabase(path, storageKey);
        try {
            JSONObject identity = database.transaction(() -> {
                String saved = database.get("meta", "identity");
                if (saved != null) return new JSONObject(saved);
                if (!database.newlyCreated) throw new IllegalStateException("Signal identity missing; explicit installation reset required");
                JSONObject generated = new JSONObject().put("version", 3)
                        .put("identityKeyPair", encode(IdentityKeyPair.generate().serialize()))
                        .put("registrationId", KeyHelper.generateRegistrationId(false));
                database.put("meta", "identity", generated.toString());
                return generated;
            });
            if (identity.getInt("version") != 3) throw new IllegalStateException("Unsupported Signal storage version");
            identityKeyPair = new IdentityKeyPair(decode(identity.getString("identityKeyPair")));
            registrationId = identity.getInt("registrationId");
        } catch (Exception error) {
            database.close();
            throw error;
        }
    }

    <T> T transaction(SignalStateDatabase.Operation<T> operation) throws Exception { return database.transaction(operation); }
    @Override public IdentityKeyPair getIdentityKeyPair() { return identityKeyPair; }
    @Override public int getLocalRegistrationId() { return registrationId; }

    @Override public IdentityChange saveIdentity(SignalProtocolAddress address, IdentityKey identityKey) {
        return database.unchecked(() -> {
            String key = addressKey(address);
            String encoded = encode(identityKey.serialize());
            String existing = database.get("identities", key);
            database.put("identities", key, encoded);
            return existing != null && !existing.equals(encoded) ? IdentityChange.REPLACED_EXISTING : IdentityChange.NEW_OR_UNCHANGED;
        });
    }
    @Override public boolean isTrustedIdentity(SignalProtocolAddress address, IdentityKey key, IdentityKeyStore.Direction direction) {
        String existing = database.get("identities", addressKey(address));
        return existing == null || existing.equals(encode(key.serialize()));
    }
    @Override public IdentityKey getIdentity(SignalProtocolAddress address) {
        String encoded = database.get("identities", addressKey(address));
        try { return encoded == null ? null : new IdentityKey(decode(encoded)); }
        catch (Exception error) { throw corrupt(error); }
    }
    @Override public PreKeyRecord loadPreKey(int id) throws InvalidKeyIdException {
        try { return new PreKeyRecord(required("preKeys", id)); }
        catch (Exception error) { throw new InvalidKeyIdException(error); }
    }
    @Override public void storePreKey(int id, PreKeyRecord record) { put("preKeys", id, record.serialize()); }
    @Override public boolean containsPreKey(int id) { return contains("preKeys", id); }
    @Override public void removePreKey(int id) {
        // The advertised bundle requires this stable pre-key until bundle rotation is implemented.
    }
    @Override public SessionRecord loadSession(SignalProtocolAddress address) {
        String encoded = database.get("sessions", addressKey(address));
        try { return encoded == null ? new SessionRecord() : new SessionRecord(decode(encoded)); }
        catch (Exception error) { throw corrupt(error); }
    }
    @Override public List<SessionRecord> loadExistingSessions(List<SignalProtocolAddress> addresses) throws NoSessionException {
        List<SessionRecord> records = new ArrayList<>();
        for (SignalProtocolAddress address : addresses) {
            if (!containsSession(address)) throw new NoSessionException(address, "No session");
            records.add(loadSession(address));
        }
        return records;
    }
    @Override public List<Integer> getSubDeviceSessions(String name) {
        List<Integer> ids = new ArrayList<>();
        String prefix = name + "|";
        for (var entry : database.entries("sessions")) {
            if (entry.name().startsWith(prefix)) ids.add(Integer.parseInt(entry.name().substring(prefix.length())));
        }
        return ids;
    }
    @Override public void storeSession(SignalProtocolAddress address, SessionRecord record) {
        database.put("sessions", addressKey(address), encode(record.serialize()));
    }
    @Override public boolean containsSession(SignalProtocolAddress address) { return database.get("sessions", addressKey(address)) != null; }
    @Override public void deleteSession(SignalProtocolAddress address) { database.remove("sessions", addressKey(address)); }
    @Override public void deleteAllSessions(String name) { database.removePrefix("sessions", name + "|"); }
    void deleteIdentity(String name, int deviceId) { database.remove("identities", name + "|" + deviceId); }
    void deleteSenderKeys(String name) { database.removePrefix("senderKeys", name + "|"); }
    @Override public SignedPreKeyRecord loadSignedPreKey(int id) throws InvalidKeyIdException {
        try { return new SignedPreKeyRecord(required("signedPreKeys", id)); }
        catch (Exception error) { throw new InvalidKeyIdException(error); }
    }
    @Override public List<SignedPreKeyRecord> loadSignedPreKeys() {
        List<SignedPreKeyRecord> result = new ArrayList<>();
        try { for (var entry : database.entries("signedPreKeys")) result.add(new SignedPreKeyRecord(decode(entry.value()))); }
        catch (Exception error) { throw corrupt(error); }
        return result;
    }
    @Override public void storeSignedPreKey(int id, SignedPreKeyRecord record) { put("signedPreKeys", id, record.serialize()); }
    @Override public boolean containsSignedPreKey(int id) { return contains("signedPreKeys", id); }
    @Override public void removeSignedPreKey(int id) { database.remove("signedPreKeys", Integer.toString(id)); }
    @Override public void storeSenderKey(SignalProtocolAddress address, UUID distributionId, SenderKeyRecord record) {
        database.put("senderKeys", addressKey(address) + "|" + distributionId, encode(record.serialize()));
    }
    @Override public SenderKeyRecord loadSenderKey(SignalProtocolAddress address, UUID distributionId) {
        String encoded = database.get("senderKeys", addressKey(address) + "|" + distributionId);
        try { return encoded == null ? null : new SenderKeyRecord(decode(encoded)); }
        catch (Exception error) { throw corrupt(error); }
    }
    @Override public KyberPreKeyRecord loadKyberPreKey(int id) throws InvalidKeyIdException {
        try { return new KyberPreKeyRecord(required("kyberPreKeys", id)); }
        catch (Exception error) { throw new InvalidKeyIdException(error); }
    }
    @Override public List<KyberPreKeyRecord> loadKyberPreKeys() {
        List<KyberPreKeyRecord> result = new ArrayList<>();
        try { for (var entry : database.entries("kyberPreKeys")) result.add(new KyberPreKeyRecord(decode(entry.value()))); }
        catch (Exception error) { throw corrupt(error); }
        return result;
    }
    @Override public void storeKyberPreKey(int id, KyberPreKeyRecord record) { put("kyberPreKeys", id, record.serialize()); }
    @Override public boolean containsKyberPreKey(int id) { return contains("kyberPreKeys", id); }
    @Override public void markKyberPreKeyUsed(int id, int signedPreKeyId, ECPublicKey baseKey) { }

    private byte[] required(String collection, int id) throws InvalidKeyIdException {
        String value = database.get(collection, Integer.toString(id));
        if (value == null) throw new InvalidKeyIdException("Missing " + collection + ": " + id);
        return decode(value);
    }
    private void put(String collection, int id, byte[] value) { database.put(collection, Integer.toString(id), encode(value)); }
    private boolean contains(String collection, int id) { return database.get(collection, Integer.toString(id)) != null; }
    private static String addressKey(SignalProtocolAddress address) { return address.getName() + "|" + address.getDeviceId(); }
    private static String encode(byte[] value) { return Base64.getEncoder().encodeToString(value); }
    private static byte[] decode(String value) { return Base64.getDecoder().decode(value); }
    private static IllegalStateException corrupt(Exception cause) { return new IllegalStateException("Corrupt Signal record", cause); }
    @Override public void close() throws Exception { database.close(); }
}
