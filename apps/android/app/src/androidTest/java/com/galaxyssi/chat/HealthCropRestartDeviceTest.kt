package com.galaxyssi.chat

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test

class HealthCropRestartDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()

    @Test fun killedDuringEncryptedStagingKeepsTheOldPageAndRemovesThePartial() = recoverAfter("staging")

    @Test fun killedAfterRenameBeforeCommitKeepsTheOldPageAndRemovesTheOrphan() = recoverAfter("renamed")

    @Test fun leftoverMarkerAfterCommittedCropPreservesTheNewPageAndCiphertext() = recoverAfter("committed")

    @Test fun cleanupDoesNotTouchAnActiveWriteOrUntrackedFiles() {
        val names = HealthOverviewDatabases(id())
        val ledger = HealthCropRecovery(names.originalRoot(context))
        val id = id()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val recovering = CountDownLatch(1)
        val recovered = CountDownLatch(1)
        val workers = java.util.concurrent.Executors.newFixedThreadPool(2)
        val files = ledger.files(id)
        val untracked = java.io.File(files.destination.parentFile, "untracked.enc")
        try {
            val writer = workers.submit {
                ledger.write(id, { _, _ -> false }) { pending ->
                    pending.staging.writeBytes(byteArrayOf(1, 2, 3))
                    untracked.writeBytes(byteArrayOf(4))
                    entered.countDown()
                    check(release.await(5, TimeUnit.SECONDS))
                }
            }
            assertTrue(entered.await(5, TimeUnit.SECONDS))
            val cleanup = workers.submit {
                recovering.countDown()
                ledger.recover { _, _ -> false }
                recovered.countDown()
            }
            assertTrue(recovering.await(5, TimeUnit.SECONDS))
            assertFalse(recovered.await(150, TimeUnit.MILLISECONDS))
            assertTrue(files.staging.isFile)
            assertTrue(ledger.marker(id).isFile)
            release.countDown()
            writer.get(5, TimeUnit.SECONDS)
            cleanup.get(5, TimeUnit.SECONDS)
            assertFalse(ledger.marker(id).exists())
            assertFalse(files.staging.exists())
            assertArrayEquals(byteArrayOf(4), untracked.readBytes())
        } finally {
            release.countDown()
            workers.shutdownNow()
            workers.awaitTermination(5, TimeUnit.SECONDS)
            clearHealthOverviewFixture(context, names)
        }
    }

    private fun recoverAfter(phase: String) {
        val names = HealthOverviewDatabases(id())
        val root = names.originalRoot(context)
        val ledger = HealthCropRecovery(root)
        val batch = HealthPhotoBatch(id(), "report", System.currentTimeMillis())
        val page = id()
        val crop = id()
        val bytes = syntheticHealthPaper()
        try {
            val original = HealthOriginalStore(context, names.originals, root).use { store ->
                store.createCaptureBatch(batch)
                store.addCaptureJob(batch.id, HealthImportJob(page, "content://fixture/report", System.currentTimeMillis(),
                    name = "report.png", mime = "image/png", captureBatch = batch.id))
                val original = store.importOriginal(page, bytes.inputStream(), "report.png", "image/png", "file")
                store.updateJob(page) { it.copy(originalId = original.id) }
                store.inspectCapture(page, HealthPhotoInspector.inspect(store, original, report = true))
                original
            }
            stopFixture(names, phase, original.id, batch.id, page, crop)
            val files = ledger.files(crop)
            assertTrue("Expected a durable pending marker", ledger.marker(crop).isFile)
            if (phase == "staging") assertTrue(files.staging.length() > 0L)
            else assertTrue(files.destination.length() > 0L)

            HealthOriginalStore(context, names.originals, root).use { store ->
                if (phase != "committed") {
                    assertEquals(page, store.capturePages(batch.id).single().jobId)
                    assertNull(store.job(crop))
                    assertNull(store.originalForJob(crop))
                }
                store.recoverCropWrites()
                store.recoverCropWrites()
                assertFalse(ledger.marker(crop).exists())
                assertFalse(files.staging.exists())
                assertArrayEquals(bytes, store.input(original).use { it.readBytes() })
                val current = store.capturePages(batch.id).single()
                if (phase == "committed") {
                    assertEquals(crop, current.jobId)
                    assertNull(store.job(page))
                    assertEquals(HealthImportState.CAPTURE_READY, store.job(crop)?.state)
                    val derivative = requireNotNull(store.originalForJob(crop))
                    assertEquals(files.relativePath, derivative.relativePath)
                    assertEquals(derivative.size, store.copyVerified(derivative, java.io.ByteArrayOutputStream()))
                    assertTrue(files.destination.isFile)
                    assertEquals(2L, store.originalCount())
                } else {
                    assertEquals(page, current.jobId)
                    assertEquals(HealthImportState.CAPTURE_READY, store.job(page)?.state)
                    assertFalse(files.destination.exists())
                    assertEquals(1L, store.originalCount())
                }
            }
        } finally { bytes.fill(0); clearHealthOverviewFixture(context, names) }
    }

    private fun stopFixture(names: HealthOverviewDatabases, phase: String, parent: String, batch: String, page: String, id: String) {
        val disconnected = CountDownLatch(1)
        val sent = AtomicBoolean()
        var error: String? = null
        val reply = Messenger(Handler(Looper.getMainLooper()) { message ->
            error = message.data.getString("failure")
            disconnected.countDown()
            true
        })
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                if (!sent.compareAndSet(false, true)) return
                runCatching {
                    Messenger(binder).send(Message.obtain(null, 1).apply {
                        replyTo = reply
                        data = Bundle().apply {
                            putString("fixture", names.fixture); putString("phase", phase); putString("parent", parent)
                            putString("batch", batch); putString("page", page); putString("id", id)
                        }
                    })
                }.onFailure { error = it.javaClass.simpleName; disconnected.countDown() }
            }
            override fun onServiceDisconnected(name: ComponentName) { disconnected.countDown() }
            override fun onBindingDied(name: ComponentName) { disconnected.countDown() }
        }
        assertTrue(context.bindService(Intent(context, HealthCropProcessFixture::class.java), connection, Context.BIND_AUTO_CREATE))
        try {
            assertTrue("Fixture process did not reach $phase", disconnected.await(30, TimeUnit.SECONDS))
            assertTrue(sent.get())
            assertNull("Fixture failed before process termination", error)
        } finally { context.unbindService(connection) }
    }
}
