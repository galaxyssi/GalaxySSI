package com.galaxyssi.link;

import org.json.JSONArray;
import org.json.JSONObject;
import org.signal.libsignal.protocol.SessionCipher;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.message.PreKeySignalMessage;
import org.signal.libsignal.protocol.message.SignalMessage;

import java.nio.charset.StandardCharsets;
import java.nio.charset.CodingErrorAction;
import java.nio.ByteBuffer;
import java.security.MessageDigest;
import java.util.HexFormat;

/** Durable handoff, not a task ledger. Python must persist the body before releasing it. */
final class SignalReceiveJournal {
    record Receipt(String plaintext, String digest, String contentHash, boolean replay) { }
    record Limits(long totalBytes, long peerBytes, long totalRecords, long peerRecords) {
        static Limits defaults() { return new Limits(64L << 20, 16L << 20, 100_000, 20_000); }
    }
    private final PersistentSignalProtocolStore store;
    private final Limits limits;

    SignalReceiveJournal(PersistentSignalProtocolStore store) { this(store, Limits.defaults()); }
    SignalReceiveJournal(PersistentSignalProtocolStore store, Limits limits) { this.store = store; this.limits = limits; }

    Receipt decrypt(String scope, SignalProtocolAddress address, boolean prekey, byte[] ciphertext,
                    String expectedTarget) throws Exception {
        if (scope.isBlank() || scope.length() > 512 || address.getName().length() > 512 || ciphertext.length > 2 * 1024 * 1024) {
            throw new IllegalArgumentException("Invalid receive scope or ciphertext size");
        }
        String peer = peerKey(scope, address);
        String digest = hash(new byte[] { (byte) (prekey ? 1 : 2) }, ciphertext);
        String key = peer + ":" + digest;
        return store.transaction(() -> {
            String saved = store.database.get("receive", key);
            if (saved != null) {
                JSONObject record = new JSONObject(saved);
                String plaintext = record.getString("plaintext");
                String contentHash = hash(plaintext.getBytes(StandardCharsets.UTF_8));
                if (!record.getString("contentHash").equals(contentHash)) throw new IllegalStateException("Receive body digest mismatch");
                return new Receipt(plaintext, digest, contentHash, true);
            }
            SessionCipher cipher = new SessionCipher(store, address);
            byte[] plaintext = prekey ? cipher.decrypt(new PreKeySignalMessage(ciphertext)) : cipher.decrypt(new SignalMessage(ciphertext));
            String decoded = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(plaintext)).toString();
            validate(decoded, address.getName(), expectedTarget);
            String contentHash = hash(plaintext);
            JSONObject record = new JSONObject().put("plaintext", decoded).put("contentHash", contentHash)
                    .put("createdAt", System.currentTimeMillis()).put("peer", peer).put("remoteName", address.getName());
            // Account for the encrypted KV JSON wrapper as well as the envelope itself.
            long bytes = new JSONObject().put("value", record.toString()).toString().getBytes(StandardCharsets.UTF_8).length + 512L;
            adjustUsage(peer, bytes, 1);
            record.put("bytes", bytes);
            store.database.put("receive", key, record.toString());
            return new Receipt(decoded, digest, contentHash, false);
        });
    }

    void forgetPeer(String remoteName) throws Exception {
        store.transaction(() -> {
            for (var entry : store.database.entries("receive")) {
                JSONObject record = new JSONObject(entry.value());
                if (!remoteName.equals(record.getString("remoteName"))) continue;
                adjustUsage(record.getString("peer"), -record.getLong("bytes"), -1);
                store.database.remove("receive", entry.name());
            }
            return null;
        });
    }

    boolean release(String scope, SignalProtocolAddress address, String digest, String contentHash) throws Exception {
        if (!digest.matches("[a-f0-9]{64}") || !contentHash.matches("[a-f0-9]{64}")) throw new IllegalArgumentException("Invalid receive digest");
        String peer = peerKey(scope, address);
        return store.transaction(() -> {
            String key = peer + ":" + digest;
            String saved = store.database.get("receive", key);
            if (saved == null) return false;
            JSONObject record = new JSONObject(saved);
            if (!contentHash.equals(record.getString("contentHash"))) throw new IllegalArgumentException("Receive handoff digest mismatch");
            adjustUsage(peer, -record.getLong("bytes"), -1);
            store.database.remove("receive", key);
            return true;
        });
    }

    private void adjustUsage(String peer, long bytes, long records) {
        changeCounter("total", bytes, records, limits.totalBytes(), limits.totalRecords());
        changeCounter(peer, bytes, records, limits.peerBytes(), limits.peerRecords());
    }

    private void changeCounter(String key, long bytes, long records, long maxBytes, long maxRecords) {
        String saved = store.database.get("receiveUsage", key);
        JSONObject usage = saved == null ? new JSONObject().put("bytes", 0).put("records", 0) : new JSONObject(saved);
        long nextBytes = Math.addExact(usage.getLong("bytes"), bytes);
        long nextRecords = Math.addExact(usage.getLong("records"), records);
        if (nextBytes < 0 || nextRecords < 0) throw new IllegalStateException("Receive quota counter underflow");
        if (nextBytes > maxBytes || nextRecords > maxRecords) throw new IllegalStateException("Receive journal is full; wait for durable handoff");
        if (nextRecords == 0) store.database.remove("receiveUsage", key);
        else store.database.put("receiveUsage", key, usage.put("bytes", nextBytes).put("records", nextRecords).toString());
    }

    private static String peerKey(String scope, SignalProtocolAddress address) throws Exception {
        return hash(new JSONArray().put(scope).put(address.getName()).put(address.getDeviceId()).toString().getBytes(StandardCharsets.UTF_8));
    }

    private static void validate(String plaintext, String source, String target) {
        if (plaintext.getBytes(StandardCharsets.UTF_8).length > 2 * 1024 * 1024) throw new IllegalArgumentException("Receive body exceeds limit");
        JSONObject envelope = new JSONObject(plaintext);
        if (!"galaxyssi-link".equals(envelope.optString("protocol")) || !Integer.valueOf(2).equals(envelope.opt("version"))
                || !source.equals(envelope.optString("source_id")) || !target.equals(envelope.optString("target_id"))
                || !envelope.optString("message_id").matches("[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}")
                || !(envelope.opt("payload") instanceof JSONObject)) throw new IllegalArgumentException("Invalid authenticated receive envelope");
        if (envelope.toString().getBytes(StandardCharsets.UTF_8).length > 512 * 1024) throw new IllegalArgumentException("Envelope exceeds limit");
        Object content = envelope.getJSONObject("payload").opt("content");
        if (content instanceof String text && text.getBytes(StandardCharsets.UTF_8).length > 128 * 1024) throw new IllegalArgumentException("Text exceeds limit");
        long now = System.currentTimeMillis();
        long sent = envelope.optLong("sent_at", 0);
        long expires = envelope.optLong("expires_at", 0);
        if (sent <= 0 || sent > now + 300_000 || expires <= sent || now > expires) throw new IllegalArgumentException("Receive timestamp is invalid or expired");
    }

    private static String hash(byte[]... values) throws Exception {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        for (byte[] value : values) digest.update(value);
        return HexFormat.of().formatHex(digest.digest());
    }
}
