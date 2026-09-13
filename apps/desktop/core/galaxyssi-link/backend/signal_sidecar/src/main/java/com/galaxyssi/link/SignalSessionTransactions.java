package com.galaxyssi.link;

import java.util.concurrent.locks.ReentrantLock;

/** Serializes the complete ratchet read/modify/write operation, not individual store calls. */
final class SignalSessionTransactions {
    private final ReentrantLock[] stripes = new ReentrantLock[256];

    SignalSessionTransactions() {
        for (int i = 0; i < stripes.length; i++) stripes[i] = new ReentrantLock(true);
    }

    @FunctionalInterface
    interface Operation<T> {
        T run() throws Exception;
    }

    <T> T withPeer(String name, Operation<T> operation) throws Exception {
        if (name == null || name.isBlank()) throw new IllegalArgumentException("Peer name is required");
        // Key by name because replace/remove operations cover every device of a peer.
        int hash = name.hashCode();
        ReentrantLock stripe = stripes[(hash ^ (hash >>> 16)) & (stripes.length - 1)];
        // A hot sender must not repeatedly overtake queued receive/ratchet work.
        stripe.lock();
        try {
            return operation.run();
        } finally {
            stripe.unlock();
        }
    }
}
