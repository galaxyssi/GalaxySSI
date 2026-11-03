package org.eclipse.paho.client.mqttv3.internal;

import org.eclipse.paho.client.mqttv3.MqttAsyncClient;
import org.eclipse.paho.client.mqttv3.persist.MemoryPersistence;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.lang.reflect.Field;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.AbstractExecutorService;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

@RunWith(Parameterized.class)
public class WorkerStartupTest {
    @Parameterized.Parameters(name = "{0}")
    public static Collection<Object[]> workers() {
        return Arrays.asList(new Object[][] {{"callback"}, {"sender"}, {"receiver"}});
    }

    private final String kind;
    public WorkerStartupTest(String kind) { this.kind = kind; }

    private static final class Client extends MqttAsyncClient {
        Client() throws Exception { super("tcp://127.0.0.1:1", "startup-race-test", new MemoryPersistence()); }
        ClientComms comms() { return comms; }
    }

    private Object worker(Client client) {
        ClientComms comms = client.comms();
        switch (kind) {
            case "sender": return new CommsSender(comms, comms.getClientState(),
                    new CommsTokenStore("test"), new ByteArrayOutputStream());
            case "receiver": return new CommsReceiver(comms, comms.getClientState(),
                    new CommsTokenStore("test"), new ByteArrayInputStream(new byte[0]));
            default: return new CommsCallback(comms);
        }
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    private static void state(Object worker, String fieldName, String state) {
        try {
            Field field = worker.getClass().getDeclaredField(fieldName);
            field.setAccessible(true);
            Field lifecycle = worker.getClass().getDeclaredField("lifecycle");
            lifecycle.setAccessible(true);
            synchronized (lifecycle.get(worker)) {
                field.set(worker, Enum.valueOf((Class) field.getType(), state));
            }
        } catch (Exception error) { throw new AssertionError(error); }
    }

    private static ExecutorService executor(Runnable dispatched) {
        return new AbstractExecutorService() {
            public void execute(Runnable ignored) { dispatched.run(); }
            public void shutdown() { }
            public List<Runnable> shutdownNow() { return Collections.emptyList(); }
            public boolean isShutdown() { return false; }
            public boolean isTerminated() { return false; }
            public boolean awaitTermination(long timeout, TimeUnit unit) { return true; }
        };
    }

    private Thread start(Object worker, ExecutorService executor, AtomicReference<Throwable> error) {
        Thread thread = new Thread(() -> {
            try {
                worker.getClass().getMethod("start", String.class, ExecutorService.class)
                        .invoke(worker, "test-worker", executor);
            } catch (Throwable failure) { error.set(failure); }
        });
        thread.setDaemon(true);
        thread.start();
        return thread;
    }

    @Test public void rapidWorkerExitDoesNotRetainConnectionThread() throws Exception {
        for (int attempt = 0; attempt < 32; attempt++) {
            Client client = new Client();
            Object worker = worker(client);
            AtomicReference<Throwable> error = new AtomicReference<>();
            Thread thread = start(worker, executor(() -> {
                state(worker, "current_state", "RUNNING");
                state(worker, "target_state", "STOPPED");
                state(worker, "current_state", "STOPPED");
            }), error);
            thread.join(1000);
            boolean leaked = thread.isAlive();
            // Also clean up an unpatched implementation when this regression fails.
            state(worker, "target_state", "RUNNING");
            state(worker, "current_state", "RUNNING");
            thread.join(1000);
            client.close();
            assertFalse("Connect caller retained after worker exit: " + attempt, leaked);
            assertNull(error.get());
        }
    }

    @Test public void healthyWorkerStillStarts() throws Exception {
        Client client = new Client();
        Object worker = worker(client);
        AtomicReference<Throwable> error = new AtomicReference<>();
        Thread thread = start(worker, executor(() -> state(worker, "current_state", "RUNNING")), error);
        thread.join(1000);
        client.close();
        assertFalse(thread.isAlive());
        assertNull(error.get());
    }

    @Test public void interruptedCallerCanLeaveStartupWait() throws Exception {
        Client client = new Client();
        Object worker = worker(client);
        CountDownLatch dispatched = new CountDownLatch(1);
        AtomicReference<Throwable> error = new AtomicReference<>();
        Thread thread = start(worker, executor(dispatched::countDown), error);
        assertTrue(dispatched.await(1, TimeUnit.SECONDS));
        thread.interrupt();
        thread.join(1000);
        boolean stopped = !thread.isAlive();
        state(worker, "current_state", "RUNNING");
        thread.join(1000);
        client.close();
        assertTrue(stopped);
        assertTrue(thread.isInterrupted());
        assertNull(error.get());
    }
}
