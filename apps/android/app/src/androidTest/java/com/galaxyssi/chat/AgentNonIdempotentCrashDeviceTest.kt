package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.FileOutputStream
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentNonIdempotentCrashDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val descriptor = AgentNativeToolDescriptor("test.non-idempotent.append", "1.0.0", "Append", "Append test marker",
        AgentNativeToolLocation.PHONE, AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(),
        AgentNativeToolRisk.LOW, setOf("test"), idempotency = AgentNativeToolIdempotency.NON_IDEMPOTENT)
    private val invocation = AgentNativeToolInvocationContext(invocationId = "before-death", sessionId = "test-effect",
        conversationId = "test-effect", turnId = "test-turn", idempotencyKey = "append")

    @Test fun crashAfterRealAppendBeforeReceipt() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonidempotent_crash_prepare") == "true")
        check(!context.getDatabasePath(DB).exists() && !context.getFileStreamPath(FILE).exists()) {
            "Inspect previous crash evidence before preparing again"
        }
        val ledger = AgentRunEventStore(context, DB)
        runtime(ledger) {
            FileOutputStream(context.getFileStreamPath(FILE)).use {
                it.write("one-effect".toByteArray()); it.fd.sync()
            }
            android.os.Process.killProcess(android.os.Process.myPid())
            error("Process must terminate before the result is committed")
        }.invoke(descriptor.id, emptyMap(), invocation)
        fail("Process did not terminate")
    }

    @Test fun retryAfterProcessDeathDoesNotAppendAgain() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonidempotent_crash_verify") == "true")
        check(context.getDatabasePath(DB).exists())
        val ledger = AgentRunEventStore(context, DB)
        try {
            val result = runtime(ledger) {
                context.getFileStreamPath(FILE).appendText("duplicate")
                AgentNativeToolExecutionResult.success()
            }.invoke(descriptor.id, emptyMap(), invocation.copy(invocationId = "after-death"))
            assertEquals("effect_outcome_unknown", result.error?.code)
            assertFalse(result.error!!.retryable)
            assertEquals("before-death", result.error?.details?.get("original_invocation_id"))
            assertEquals("one-effect", context.getFileStreamPath(FILE).readText())
        } finally { ledger.close() }
    }

    @Test fun clearVerifiedCrashEvidence() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("nonidempotent_crash_clear") == "true")
        check(context.getFileStreamPath(FILE).readText() == "one-effect")
        val ledger = AgentRunEventStore(context, DB)
        try {
            val result = runtime(ledger) { error("Must not dispatch during cleanup") }
                .invoke(descriptor.id, emptyMap(), invocation.copy(invocationId = "cleanup-check"))
            check(result.error?.code == "effect_outcome_unknown")
        } finally { ledger.close() }
        check(context.deleteDatabase(DB))
        check(context.getFileStreamPath(FILE).delete())
    }

    private fun runtime(ledger: AgentRunEventStore, executor: AgentNativeToolExecutor) =
        AgentNativeToolRegistry(replayStore = EncryptedAgentNativeToolReplayStore(ledger))
            .register(AgentNativeToolDefinition(descriptor, executor))

    private companion object {
        const val DB = "test-nonidempotent-process-death.db"
        const val FILE = "test-nonidempotent-process-death.marker"
    }
}
