package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRecoveryWakeDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun pendingFastPathNeedsNoHandoffToBeDiscoveredOnReconnect(): Unit = runBlocking {
        val context = IsolatedContext(instrumentation.targetContext)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            AgentPendingDeliveryStore.put(context, delivery(42))
            val observed = CompletableDeferred<List<AgentPendingDelivery>>()
            val wake = AgentRecoveryWakeCoordinator(scope, recover = {
                observed.complete(AgentPendingDeliveryStore.sourceIds(context).asSequence()
                    .mapNotNull { AgentPendingDeliveryStore.find(context, it) }.toList())
            })
            wake.request(isConnected = false)
            assertFalse(observed.isCompleted)
            wake.connectionChanged(true)
            val values = withTimeout(10000) { observed.await() }
            assertEquals(listOf(42L), values.map { it.sourceMessageId })
            assertEquals("\u91cd\u8fde\u6d4b\u8bd5-42", values.single().conversationId)
        } finally { scope.cancel(); context.clear() }
    }

    @Test fun pendingIdentitySnapshotIsNewestFirstAndBodiesCanBeReadInPages() {
        val context = IsolatedContext(instrumentation.targetContext)
        try {
            for (id in 1L..83L) AgentPendingDeliveryStore.put(context, delivery(id))
            AgentPendingDeliveryStore.remove(context, 41)
            AgentPendingDeliveryStore.completeResponse(context, delivery(71))
            val sources = AgentPendingDeliveryStore.sourceIds(context)
            assertEquals(81, sources.size)
            assertEquals(83L, sources.first())
            assertEquals(1L, sources.last())
            val pages = sources.toList().chunked(32).map { ids ->
                ids.mapNotNull { AgentPendingDeliveryStore.find(context, it) }
            }
            assertEquals(listOf(32, 32, 17), pages.map { it.size })
            assertFalse(pages.flatten().any { it.sourceMessageId == 41L || it.sourceMessageId == 71L })
        } finally { context.clear() }
    }

    @Test fun aNewCoordinatorUsesPersistedPendingStateAfterPreviousWorkerStops(): Unit = runBlocking {
        val context = IsolatedContext(instrumentation.targetContext)
        try {
            AgentPendingDeliveryStore.put(context, delivery(42))
            suspend fun observe(): List<Long> {
                val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
                try {
                    val result = CompletableDeferred<List<Long>>()
                    val wake = AgentRecoveryWakeCoordinator(scope, recover = {
                        result.complete(AgentPendingDeliveryStore.sourceIds(context).toList())
                    })
                    wake.request(isConnected = true)
                    return withTimeout(10000) { result.await() }
                } finally { scope.cancel() }
            }
            assertEquals(listOf(42L), observe())
            AgentPendingDeliveryStore.completeResponse(context, delivery(42))
            assertTrue(observe().isEmpty())
        } finally { context.clear() }
    }

    @Test fun mainThreadWakeRemainsResponsiveWhileObservationIsSuspended(): Unit = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            val started = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            val wake = AgentRecoveryWakeCoordinator(scope, recover = { started.complete(Unit); release.await() })
            var callbackMillis = Long.MAX_VALUE
            instrumentation.runOnMainSync {
                val start = SystemClock.elapsedRealtime()
                wake.request(isConnected = true)
                callbackMillis = SystemClock.elapsedRealtime() - start
            }
            withTimeout(10000) { started.await() }
            var mainResponsive = false
            instrumentation.runOnMainSync { mainResponsive = true; wake.request() }
            assertTrue(mainResponsive)
            assertTrue("Wake callback blocked main thread for ${callbackMillis}ms", callbackMillis < 100)
            Log.i("GalaxySSIRecoveryTest", "wakeup_main_callback_ms=$callbackMillis")
            release.complete(Unit)
        } finally { scope.cancel() }
    }

    private fun delivery(id: Long) = AgentPendingDelivery(id, "\u91cd\u8fde\u6d4b\u8bd5-$id", "turn-$id", "task-$id", "contact")

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "wakeup-test-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            val isolated = prefix + name
            synchronized(names) { names.add(isolated) }
            return baseContext.getSharedPreferences(isolated, mode)
        }
        fun clear() {
            synchronized(names) { names.forEach {
                baseContext.getSharedPreferences(it, Context.MODE_PRIVATE).edit().clear().commit()
                baseContext.deleteSharedPreferences(it)
            } }
        }
    }
}
