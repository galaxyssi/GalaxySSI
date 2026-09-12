package com.galaxyssi.link;

import org.json.JSONObject;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.List;

/** One lock and one SQLite transaction domain for the ratchet and receive handoff. */
final class SignalStateDatabase implements AutoCloseable {
    @FunctionalInterface interface Operation<T> { T run() throws Exception; }
    record Entry(String name, String value) { }

    private static final SecureRandom RANDOM = new SecureRandom();
    private final Connection connection;
    private final SecretKeySpec encryptionKey;
    private final SecretKeySpec indexKey;
    final boolean newlyCreated;
    private int depth;
    private boolean rollbackOnly;

    SignalStateDatabase(Path path, byte[] key) throws Exception {
        if (key == null || key.length != 32) throw new IllegalArgumentException("Expected a 32-byte storage key");
        path = path.toAbsolutePath();
        Files.createDirectories(path.getParent());
        newlyCreated = !Files.exists(path);
        encryptionKey = new SecretKeySpec(key.clone(), "AES");
        Mac kdf = Mac.getInstance("HmacSHA256");
        kdf.init(new SecretKeySpec(key.clone(), "HmacSHA256"));
        indexKey = new SecretKeySpec(kdf.doFinal("galaxyssi.signal-state/3/index".getBytes(StandardCharsets.US_ASCII)), "HmacSHA256");
        connection = DriverManager.getConnection("jdbc:sqlite:" + path);
        try {
            try (var statement = connection.createStatement()) {
                statement.execute("PRAGMA busy_timeout=10000");
                statement.execute("PRAGMA journal_mode=WAL");
                statement.execute("PRAGMA synchronous=FULL");
                statement.execute("CREATE TABLE IF NOT EXISTS records (collection TEXT NOT NULL, record_id TEXT NOT NULL, body BLOB NOT NULL, PRIMARY KEY(collection, record_id))");
            }
        } catch (Exception error) {
            connection.close();
            throw error;
        }
    }

    synchronized <T> T transaction(Operation<T> operation) throws Exception {
        boolean outer = depth == 0;
        if (outer) {
            execute("BEGIN IMMEDIATE");
            rollbackOnly = false;
        }
        depth++;
        try {
            T value = operation.run();
            if (outer) {
                if (rollbackOnly) throw new IllegalStateException("Nested Signal transaction failed");
                execute("COMMIT");
            }
            return value;
        } catch (Exception | Error error) {
            rollbackOnly = true;
            if (outer) {
                try { execute("ROLLBACK"); } catch (Exception rollback) { error.addSuppressed(rollback); }
            }
            throw error;
        } finally {
            depth--;
        }
    }

    <T> T unchecked(Operation<T> operation) {
        try { return transaction(operation); }
        catch (RuntimeException error) { throw error; }
        catch (Exception error) { throw new IllegalStateException("Signal state transaction failed", error); }
    }

    synchronized String get(String collection, String name) {
        String id = id(collection, name);
        try (var query = connection.prepareStatement("SELECT body FROM records WHERE collection=? AND record_id=?")) {
            query.setString(1, collection);
            query.setString(2, id);
            try (var rows = query.executeQuery()) {
                if (!rows.next()) return null;
                JSONObject record = new JSONObject(decrypt(collection, id, rows.getBytes(1)));
                if (!name.equals(record.getString("name"))) throw new IllegalStateException("Signal record binding mismatch");
                return record.getString("value");
            }
        } catch (Exception error) { throw storageFailure(error); }
    }

    synchronized void put(String collection, String name, String value) {
        String id = id(collection, name);
        try (var update = connection.prepareStatement("INSERT INTO records(collection,record_id,body) VALUES(?,?,?) ON CONFLICT(collection,record_id) DO UPDATE SET body=excluded.body")) {
            update.setString(1, collection);
            update.setString(2, id);
            update.setBytes(3, encrypt(collection, id, new JSONObject().put("name", name).put("value", value).toString()));
            update.executeUpdate();
        } catch (Exception error) { throw storageFailure(error); }
    }

    synchronized void remove(String collection, String name) {
        try (var update = connection.prepareStatement("DELETE FROM records WHERE collection=? AND record_id=?")) {
            update.setString(1, collection);
            update.setString(2, id(collection, name));
            update.executeUpdate();
        } catch (Exception error) { throw storageFailure(error); }
    }

    synchronized List<Entry> entries(String collection) {
        List<Entry> result = new ArrayList<>();
        try (var query = connection.prepareStatement("SELECT record_id,body FROM records WHERE collection=?")) {
            query.setString(1, collection);
            try (var rows = query.executeQuery()) {
                while (rows.next()) {
                    JSONObject item = new JSONObject(decrypt(collection, rows.getString(1), rows.getBytes(2)));
                    if (!id(collection, item.getString("name")).equals(rows.getString(1))) throw new IllegalStateException("Signal index binding mismatch");
                    result.add(new Entry(item.getString("name"), item.getString("value")));
                }
            }
        } catch (Exception error) { throw storageFailure(error); }
        return result;
    }

    synchronized void removePrefix(String collection, String prefix) {
        unchecked(() -> {
            for (Entry entry : entries(collection)) if (entry.name().startsWith(prefix)) remove(collection, entry.name());
            return null;
        });
    }

    private String id(String collection, String name) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(indexKey);
            return HexFormat.of().formatHex(mac.doFinal((collection + "\0" + name).getBytes(StandardCharsets.UTF_8)));
        } catch (Exception error) { throw storageFailure(error); }
    }

    private byte[] encrypt(String collection, String id, String value) throws Exception {
        byte[] nonce = new byte[12];
        RANDOM.nextBytes(nonce);
        Cipher cipher = cipher(Cipher.ENCRYPT_MODE, collection, id, nonce);
        byte[] encrypted = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
        byte[] record = Arrays.copyOf(nonce, nonce.length + encrypted.length);
        System.arraycopy(encrypted, 0, record, nonce.length, encrypted.length);
        return record;
    }

    private String decrypt(String collection, String id, byte[] record) throws Exception {
        if (record.length < 28) throw new IllegalStateException("Truncated Signal state");
        Cipher cipher = cipher(Cipher.DECRYPT_MODE, collection, id, Arrays.copyOf(record, 12));
        return new String(cipher.doFinal(record, 12, record.length - 12), StandardCharsets.UTF_8);
    }

    private Cipher cipher(int mode, String collection, String id, byte[] nonce) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(mode, encryptionKey, new GCMParameterSpec(128, nonce));
        cipher.updateAAD(("galaxyssi.signal-state/3\0" + collection + "\0" + id).getBytes(StandardCharsets.UTF_8));
        return cipher;
    }

    private void execute(String sql) throws Exception {
        try (var statement = connection.createStatement()) { statement.execute(sql); }
    }

    private static IllegalStateException storageFailure(Exception error) {
        return new IllegalStateException("Signal state is unavailable or failed authentication", error);
    }

    @Override public synchronized void close() throws Exception { connection.close(); }
}
