package com.galaxyssi.link;

import org.signal.libsignal.protocol.SessionBuilder;
import org.signal.libsignal.protocol.SessionCipher;
import org.signal.libsignal.protocol.SignalProtocolAddress;
import org.signal.libsignal.protocol.message.CiphertextMessage;
import org.signal.libsignal.protocol.message.PreKeySignalMessage;
import org.signal.libsignal.protocol.message.SignalMessage;
import org.signal.libsignal.protocol.state.impl.InMemorySignalProtocolStore;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/** Opt-in local stress probe. Uses fresh in-memory identities, never paired device state. */
public final class SignalConcurrencyProbe {
    public static void main(String[] args) throws Exception {
        var phone = SignalRoundTripProbe.newStore();
        var desktop = SignalRoundTripProbe.newStore();
        var phoneAddress = new SignalProtocolAddress("probe-phone", 1);
        var desktopAddress = new SignalProtocolAddress("probe-desktop", 1);
        new SessionBuilder(phone, desktopAddress).process(SignalRoundTripProbe.publishBundle(desktop));
        var phoneTransactions = new SignalSessionTransactions();
        var desktopTransactions = new SignalSessionTransactions();
        roundTrip(phone, desktop, phoneAddress, desktopAddress, phoneTransactions, desktopTransactions, "handshake");
        var workers = Executors.newFixedThreadPool(10);
        var ready = new CountDownLatch(10);
        var start = new CountDownLatch(1);
        var completed = new AtomicInteger();
        long startedAt = System.nanoTime();
        try {
            List<Future<?>> results = new ArrayList<>();
            for (int lane = 0; lane < 10; lane++) {
                final int index = lane;
                results.add(workers.submit(() -> {
                    ready.countDown();
                    if (!start.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Start barrier expired");
                    for (int turn = 0; turn < 100; turn++) {
                        roundTrip(phone, desktop, phoneAddress, desktopAddress, phoneTransactions,
                                desktopTransactions, "lane=" + index + ":turn=" + turn);
                        completed.incrementAndGet();
                    }
                    return null;
                }));
            }
            if (!ready.await(5, TimeUnit.SECONDS)) throw new IllegalStateException("Workers did not start");
            start.countDown();
            for (Future<?> result : results) result.get(120, TimeUnit.SECONDS);
        } finally {
            start.countDown();
            workers.shutdownNow();
            if (!workers.awaitTermination(10, TimeUnit.SECONDS)) throw new IllegalStateException("Workers did not stop");
        }
        if (completed.get() != 1000) throw new IllegalStateException("Missing responses");
        System.out.println("CONCURRENT_SIGNAL_OK workers=10 round_trips=" + completed.get()
                + " elapsed_ms=" + (System.nanoTime() - startedAt) / 1_000_000);
    }

    private static void roundTrip(InMemorySignalProtocolStore phone, InMemorySignalProtocolStore desktop,
            SignalProtocolAddress phoneAddress, SignalProtocolAddress desktopAddress,
            SignalSessionTransactions phoneTransactions, SignalSessionTransactions desktopTransactions,
            String marker) throws Exception {
        byte[] plain = marker.getBytes(StandardCharsets.UTF_8);
        CiphertextMessage request = phoneTransactions.withPeer(desktopAddress.getName(),
                () -> new SessionCipher(phone, desktopAddress).encrypt(plain));
        byte[] received = desktopTransactions.withPeer(phoneAddress.getName(),
                () -> decrypt(new SessionCipher(desktop, phoneAddress), request));
        if (!marker.equals(new String(received, StandardCharsets.UTF_8))) throw new IllegalStateException("Request crossed turns");
        CiphertextMessage reply = desktopTransactions.withPeer(phoneAddress.getName(),
                () -> new SessionCipher(desktop, phoneAddress).encrypt(("reply:" + marker).getBytes(StandardCharsets.UTF_8)));
        byte[] response = phoneTransactions.withPeer(desktopAddress.getName(),
                () -> decrypt(new SessionCipher(phone, desktopAddress), reply));
        if (!("reply:" + marker).equals(new String(response, StandardCharsets.UTF_8))) throw new IllegalStateException("Response crossed turns");
    }

    private static byte[] decrypt(SessionCipher cipher, CiphertextMessage message) throws Exception {
        return message.getType() == CiphertextMessage.PREKEY_TYPE
                ? cipher.decrypt(new PreKeySignalMessage(message.serialize()))
                : cipher.decrypt(new SignalMessage(message.serialize()));
    }
}
