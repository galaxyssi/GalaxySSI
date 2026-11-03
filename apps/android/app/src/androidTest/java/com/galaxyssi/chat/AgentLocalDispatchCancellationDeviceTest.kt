package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.awaitCancellation
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Public local-adapter cancellation fixtures; no user goal, model or Linux process is stopped. */
@RunWith(AndroidJUnit4::class)
class AgentLocalDispatchCancellationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun stoppingAnActiveNativeToolUnwindsItAndSuppressesTheLateReplyWithoutAnotherModelCall() {
        val task = "public-local-native-stop-${UUID.randomUUID()}"
        val started = CountDownLatch(1)
        val settled = CountDownLatch(1)
        val modelCalls = AtomicInteger()
        val replies = AtomicInteger()
        val stops = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor()
        val registry = AgentNativeToolRegistry().register(AgentNativeToolDefinition(AgentNativeToolDescriptor(
            "public.local.wait", "1.0.0", "Public waiting tool", "Public cancellable fixture", AgentNativeToolLocation.PHONE,
            AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
            AgentNativeToolExecutor { invocation ->
                val cancelled = CountDownLatch(1)
                val subscription = invocation.cancellationToken.invokeOnCancellation { cancelled.countDown() }
                try {
                    started.countDown()
                    assertTrue(cancelled.await(10, TimeUnit.SECONDS))
                    invocation.checkpoint()
                    AgentNativeToolExecutionResult.success(mapOf("late" to true))
                } finally { subscription.dispose(); settled.countDown() }
            }))
        val session = LocalModelWebToolSession(context, "public-scripted-local", false, inference = { _, _ ->
            assertEquals(1, modelCalls.incrementAndGet())
            LocalModelInferenceResult("""{"answer":"公开测试：等待工具。","tool_calls":[{"id":"wait","name":"public.local.wait","arguments":{}}]}""",
                "public-scripted-local", "fixture", false, 1L)
        })
        try {
            val future = executor.submit {
                AgentLocalDispatchLease(task).execute({ token -> runLoop(task, token, registry, session) },
                    { replies.incrementAndGet() }, {
                        assertEquals("Cancellation acknowledgement must follow tool cleanup", 0L, settled.count)
                        stops.incrementAndGet()
                    })
            }
            assertTrue(started.await(10, TimeUnit.SECONDS))
            PhoneExecutionAuthority.requestCancellation(task)
            future.get(10, TimeUnit.SECONDS)
            assertEquals(0, replies.get())
            assertEquals(1, stops.get())
            assertEquals(1, modelCalls.get())
            assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
            assertFalse(PhoneExecutionAuthority.isCancelled("$task-other"))
        } finally { executor.shutdownNow(); PhoneExecutionAuthority.clearCancellation(task) }
    }

    @Test fun stoppingSuspendedLocalInferenceCancelsTheCoroutineAndDoesNotWriteAFailureReply() {
        val task = "public-local-inference-stop-${UUID.randomUUID()}"
        val started = CountDownLatch(1)
        val settled = CountDownLatch(1)
        val stops = AtomicInteger()
        val executor = Executors.newSingleThreadExecutor()
        val session = LocalModelWebToolSession(context, "public-scripted-local", false, inference = { _, _ ->
            try { started.countDown(); awaitCancellation() } finally { settled.countDown() }
        })
        try {
            val future = executor.submit {
                AgentLocalDispatchLease(task).execute({ token -> runLoop(task, token, AgentNativeToolRegistry(), session) },
                    { fail("Cancelled local inference must not publish a late answer or error") }, {
                        assertEquals(0L, settled.count)
                        stops.incrementAndGet()
                    })
            }
            assertTrue(started.await(10, TimeUnit.SECONDS))
            PhoneExecutionAuthority.requestCancellation(task)
            future.get(10, TimeUnit.SECONDS)
            assertEquals(1, stops.get())
            assertEquals(0, PhoneExecutionAuthority.cancellationListenerCount(task))
        } finally { executor.shutdownNow(); PhoneExecutionAuthority.clearCancellation(task) }
    }

    private fun runLoop(task: String, token: AgentNativeToolCancellationToken, registry: AgentNativeToolRegistry,
        session: LocalModelWebToolSession): AgentModelToolLoopOutcome = runCancellableLocalRequest(token) {
        AgentModelToolLoop(session.adapter(registry.availableCatalog().descriptors), registry)
            .run(AgentModelToolLoopRequest.forUserMessage(task, "$task-conversation", task, task,
                LocalModelAgentToolPolicy.workspace("$task-conversation", task), "公开测试：请等待工具完成。",
                cancellationToken = token))
    }
}
