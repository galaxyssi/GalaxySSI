package com.galaxyssi.link;

import org.signal.libsignal.protocol.SessionBuilder;
import org.signal.libsignal.protocol.SessionCipher;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.message.CiphertextMessage;
import org.signal.libsignal.protocol.message.PreKeySignalMessage;
import org.signal.libsignal.protocol.message.SignalMessage;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** Real Signal regression for a task waiting behind a bidirectional attachment transfer. */
public final class SignalDeferredSendProbe {
    public static void main(String[] args) throws Exception {
        var phone = SignalRoundTripProbe.newStore();
        var desktop = SignalRoundTripProbe.newStore();
        var p = new SignalProtocolAddress("phone", 1);
        var d = new SignalProtocolAddress("desktop", 1);
        new SessionBuilder(phone, d).process(SignalRoundTripProbe.publishBundle(desktop));
        var sender = new SessionCipher(phone, d);
        var receiver = new SessionCipher(desktop, p);
        exchange(sender, receiver, "manifest");
        exchange(receiver, sender, "missing");
        byte[] task = "summarize-all-pages".getBytes(StandardCharsets.UTF_8);
        var premature = sender.encrypt(task);
        for (int i = 0; i < 20; i++) {
            exchange(sender, receiver, "chunk-" + i);
            exchange(receiver, sender, "receipt-" + i);
        }
        boolean staleRejected = false;
        try { decrypt(receiver, premature); }
        catch (org.signal.libsignal.protocol.InvalidMessageException expected) { staleRejected = true; }
        if (!staleRejected) throw new IllegalStateException("Expected old receiving chain to expire");
        var fresh = sender.encrypt(task);
        if (!Arrays.equals(task, decrypt(receiver, fresh))) throw new IllegalStateException("Deferred task failed");
        System.out.println("DEFERRED_SIGNAL_OK stale_ciphertext_rejected=true encrypt_after_upload=true");
    }

    private static void exchange(SessionCipher from, SessionCipher to, String text) throws Exception {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        if (!Arrays.equals(bytes, decrypt(to, from.encrypt(bytes)))) throw new IllegalStateException("Exchange failed");
    }

    private static byte[] decrypt(SessionCipher cipher, CiphertextMessage message) throws Exception {
        return message.getType() == CiphertextMessage.PREKEY_TYPE
                ? cipher.decrypt(new PreKeySignalMessage(message.serialize()))
                : cipher.decrypt(new SignalMessage(message.serialize()));
    }
}
