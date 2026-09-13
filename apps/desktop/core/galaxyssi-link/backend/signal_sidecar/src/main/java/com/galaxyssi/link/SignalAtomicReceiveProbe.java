package com.galaxyssi.link;

import org.json.JSONObject;
import org.signal.libsignal.protocol.SessionBuilder;
import org.signal.libsignal.protocol.IdentityKey;
import org.signal.libsignal.protocol.SessionCipher;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.message.CiphertextMessage;
import org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore;
import org.signal.libsignal.protocol.state.PreKeyBundle;
import org.signal.libsignal.protocol.ecc.ECPublicKey;
import org.signal.libsignal.protocol.kem.KEMPublicKey;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.DriverManager;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.Comparator;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Isolated real-libsignal, real-SQLite and abrupt JVM-death acceptance. */
public final class SignalAtomicReceiveProbe {
    private static final byte[] KEY = new byte[32];
    private static final SignalProtocolAddress PHONE = new SignalProtocolAddress("probe-phone", 1);
    private static final SignalProtocolAddress DESKTOP = new SignalProtocolAddress("probe-desktop", 1);
    private static int passed;
    private record Fixture(Path path, InMemorySignalProtocolStore phone, byte[] first) { }

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].equals("wire")) { createHttpFixture(Path.of(args[1])); return; }
        if (args.length > 0) { crashChild(Path.of(args[1]), args[0].equals("commit")); return; }
        Path root = Files.createTempDirectory("galaxyssi-atomic-signal-").toAbsolutePath();
        try {
            replayAndConcurrency(root);
            failuresRollback(root);
            invalidUtf8(root);
            corruptStorage(root);
            processDeath(root, false);
            processDeath(root, true);
            System.out.println("ATOMIC_SIGNAL_OK checks=" + passed + " real_process_death_cases=2");
        } finally {
            try (var files = Files.walk(root)) {
                for (Path path : files.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
    }

    private static void createHttpFixture(Path bundlePath) throws Exception {
        JSONObject bundle = new JSONObject(Files.readString(bundlePath));
        Base64.Decoder b64 = Base64.getDecoder();
        PreKeyBundle remote = new PreKeyBundle(bundle.getInt("registrationId"), 1,
                bundle.getInt("preKeyId"), new ECPublicKey(b64.decode(bundle.getString("preKey"))),
                bundle.getInt("signedPreKeyId"), new ECPublicKey(b64.decode(bundle.getString("signedPreKey"))),
                b64.decode(bundle.getString("signedPreKeySignature")), new IdentityKey(b64.decode(bundle.getString("identityKey"))),
                bundle.getInt("kyberPreKeyId"), new KEMPublicKey(b64.decode(bundle.getString("kyberPreKey"))),
                b64.decode(bundle.getString("kyberPreKeySignature")));
        var phone = SignalRoundTripProbe.newStore();
        new SessionBuilder(phone, DESKTOP).process(remote);
        String target = "desktop_" + bundle.getString("identityKeySha256").substring(0, 16);
        System.out.println(new JSONObject().put("body", Base64.getEncoder().encodeToString(encrypt(phone, target)))
                .put("signal_type", "prekey").put("message_type", 3).put("from", PHONE.getName())
                .put("to", target).put("_client_route_id", "isolated-http-pair"));
    }

    private static Fixture fixture(Path root, String name) throws Exception {
        Path path = root.resolve(name + ".db");
        var phone = SignalRoundTripProbe.newStore();
        try (var store = new PersistentSignalProtocolStore(path, KEY)) {
            new SessionBuilder(phone, DESKTOP).process(SignalRoundTripProbe.publishBundle(store));
        }
        return new Fixture(path, phone, encrypt(phone, "probe-desktop"));
    }

    private static byte[] encrypt(InMemorySignalProtocolStore phone, String target) throws Exception {
        long now = System.currentTimeMillis();
        String envelope = new JSONObject().put("protocol", "galaxyssi-link").put("version", 2)
                .put("source_id", PHONE.getName()).put("target_id", target).put("message_id", UUID.randomUUID().toString())
                .put("sent_at", now).put("expires_at", now + 60_000).put("payload", new JSONObject().put("type", "text")
                        .put("content", "private-atomic-receive-marker")).toString();
        CiphertextMessage message = new SessionCipher(phone, DESKTOP).encrypt(envelope.getBytes(StandardCharsets.UTF_8));
        return message.serialize();
    }

    private static SignalReceiveJournal.Receipt receive(SignalReceiveJournal journal, byte[] body) throws Exception {
        return journal.decrypt("pair-one", PHONE, true, body, DESKTOP.getName());
    }

    private static void replayAndConcurrency(Path root) throws Exception {
        Fixture f = fixture(root, "replay");
        SignalReceiveJournal.Receipt original;
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            var journal = new SignalReceiveJournal(store);
            var workers = Executors.newFixedThreadPool(10);
            var fresh = new AtomicInteger();
            var duplicates = new AtomicInteger();
            try {
                List<java.util.concurrent.Future<?>> pending = new ArrayList<>();
                for (int i = 0; i < 30; i++) pending.add(workers.submit(() -> {
                    var receipt = receive(journal, f.first());
                    if (receipt.replay()) duplicates.incrementAndGet(); else fresh.incrementAndGet();
                    return null;
                }));
                for (var task : pending) task.get(30, TimeUnit.SECONDS);
            } finally {
                workers.shutdownNow();
                if (!workers.awaitTermination(10, TimeUnit.SECONDS)) throw new IllegalStateException("Workers still active");
            }
            check(fresh.get() == 1 && duplicates.get() == 29, "30 copies decrypt once");
            original = receive(journal, f.first());
            check(original.plaintext().contains("private-atomic-receive-marker"), "complete body retained");
            expectFailure(() -> journal.release("pair-one", PHONE, original.digest(), "0".repeat(64)), "wrong handoff digest rejected");
            check(receive(journal, f.first()).replay(), "wrong release preserves body");
            expectFailure(() -> journal.decrypt("different-pair", PHONE, true, f.first(), DESKTOP.getName()), "ciphertext cannot cross pair scopes");
        }
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            var journal = new SignalReceiveJournal(store);
            check(receive(journal, f.first()).plaintext().equals(original.plaintext()), "reopen returns original body");
            check(journal.release("pair-one", PHONE, original.digest(), original.contentHash()), "durable handoff releases journal");
            check(!journal.release("pair-one", PHONE, original.digest(), original.contentHash()), "release is idempotent");
            check(store.database.entries("receiveUsage").isEmpty(), "quota released");
        }
        String raw = new String(Files.readAllBytes(f.path()), StandardCharsets.ISO_8859_1);
        check(!raw.contains("private-atomic-receive-marker") && !raw.contains(PHONE.getName()), "disk contains no plaintext body or peer");
    }

    private static void failuresRollback(Path root) throws Exception {
        Fixture f = fixture(root, "rollback");
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            var journal = new SignalReceiveJournal(store, new SignalReceiveJournal.Limits(4096, 4096, 10, 1));
            byte[] damaged = f.first().clone(); damaged[damaged.length - 1] ^= 1;
            expectFailure(() -> receive(journal, damaged), "damaged ciphertext rejected");
            check(!store.containsSession(PHONE), "failed decrypt leaves no ratchet");
            expectFailure(() -> store.transaction(() -> { receive(journal, f.first()); throw new IllegalStateException("injected failure"); }), "post-decrypt rollback");
            check(!store.containsSession(PHONE) && store.database.entries("receive").isEmpty(), "ratchet and body rolled back together");
            var first = receive(journal, f.first());
            byte[] before = store.loadSession(PHONE).serialize();
            byte[] second = encrypt(f.phone(), DESKTOP.getName());
            expectFailure(() -> receive(journal, second), "peer quota rejects new receive");
            check(Arrays.equals(before, store.loadSession(PHONE).serialize()), "quota failure rolls back ratchet");
            journal.release("pair-one", PHONE, first.digest(), first.contentHash());
            check(!receive(journal, second).replay(), "same wire succeeds after quota released");
            byte[] wrongTarget = encrypt(f.phone(), "wrong-desktop");
            before = store.loadSession(PHONE).serialize();
            expectFailure(() -> receive(journal, wrongTarget), "wrong endpoint rejected");
            check(Arrays.equals(before, store.loadSession(PHONE).serialize()), "endpoint rejection rolls back ratchet");
            expectFailure(() -> store.transaction(() -> {
                try { store.transaction(() -> { store.database.put("probe", "nested", "bad"); throw new IllegalStateException("nested"); }); }
                catch (IllegalStateException ignored) { }
                return null;
            }), "caught nested failure still aborts transaction");
            check(store.database.get("probe", "nested") == null, "nested write rolled back");
        }
    }

    private static void corruptStorage(Path root) throws Exception {
        Fixture f = fixture(root, "corrupt");
        byte[] wrongKey = KEY.clone(); wrongKey[0] = 7;
        expectFailure(() -> { try (var ignored = new PersistentSignalProtocolStore(f.path(), wrongKey)) { return null; } }, "wrong storage key fails closed");
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            receive(new SignalReceiveJournal(store), f.first());
            try (var db = DriverManager.getConnection("jdbc:sqlite:" + f.path()); var update = db.createStatement()) {
                update.execute("UPDATE records SET body=zeroblob(length(body)) WHERE collection='sessions'");
            }
            expectFailure(() -> store.loadSession(PHONE), "corrupt session is not silently reset");
        }
        Path old = root.resolve("legacy.json");
        Files.writeString(old, "{\"identityKeyPair\":\"not-a-real-key\"}");
        expectFailure(() -> { try (var ignored = new PersistentSignalProtocolStore(old, KEY)) { return null; } }, "legacy JSON is not imported");
    }

    private static void invalidUtf8(Path root) throws Exception {
        Fixture f = fixture(root, "invalid-utf8");
        byte[] invalid = new SessionCipher(f.phone(), DESKTOP).encrypt(new byte[] { (byte) 0xFF }).serialize();
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            var journal = new SignalReceiveJournal(store);
            expectFailure(() -> receive(journal, invalid), "invalid UTF-8 rejected without replacement characters");
            check(!store.containsSession(PHONE), "invalid UTF-8 does not advance ratchet");
            check(!receive(journal, f.first()).replay(), "valid earlier wire still decrypts after malformed content");
            journal.forgetPeer("unrelated-peer");
            check(receive(journal, f.first()).replay(), "revoking a different peer preserves receive body");
            journal.forgetPeer(PHONE.getName());
            check(store.database.entries("receive").isEmpty() && store.database.entries("receiveUsage").isEmpty(),
                    "explicit peer revocation clears journal and quota");
        }
    }

    private static void processDeath(Path root, boolean commit) throws Exception {
        Fixture f = fixture(root, commit ? "committed-death" : "uncommitted-death");
        Files.writeString(f.path().resolveSibling(f.path().getFileName() + ".wire"), Base64.getEncoder().encodeToString(f.first()));
        String java = Path.of(System.getProperty("java.home"), "bin", System.getProperty("os.name").startsWith("Windows") ? "java.exe" : "java").toString();
        Process child = new ProcessBuilder(java, "-cp", System.getProperty("java.class.path"),
                SignalAtomicReceiveProbe.class.getName(), commit ? "commit" : "rollback", f.path().toString()).inheritIO().start();
        if (!child.waitFor(30, TimeUnit.SECONDS)) { child.destroyForcibly().waitFor(); throw new IllegalStateException("Crash child timed out"); }
        check(child.exitValue() == 37, "JVM terminated without closing database");
        try (var store = new PersistentSignalProtocolStore(f.path(), KEY)) {
            var receipt = receive(new SignalReceiveJournal(store), f.first());
            check(receipt.replay() == commit, commit ? "committed receive survives abrupt JVM death" : "uncommitted ratchet rolls back after abrupt JVM death");
        }
    }

    private static void crashChild(Path path, boolean commit) throws Exception {
        var store = new PersistentSignalProtocolStore(path, KEY);
        byte[] wire = Base64.getDecoder().decode(Files.readString(path.resolveSibling(path.getFileName() + ".wire")));
        if (commit) receive(new SignalReceiveJournal(store), wire);
        else store.transaction(() -> { receive(new SignalReceiveJournal(store), wire); Runtime.getRuntime().halt(37); return null; });
        Runtime.getRuntime().halt(37);
    }

    private static void check(boolean condition, String label) {
        if (!condition) throw new IllegalStateException(label);
        passed++;
        System.out.println("PASS " + label);
    }
    private static void expectFailure(SignalStateDatabase.Operation<?> operation, String label) throws Exception {
        boolean failed = false;
        try { operation.run(); } catch (Exception expected) { failed = true; }
        check(failed, label);
    }
}
