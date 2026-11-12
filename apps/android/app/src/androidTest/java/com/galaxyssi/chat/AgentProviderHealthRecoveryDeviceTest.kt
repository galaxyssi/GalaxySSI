package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentProviderHealthRecoveryDeviceTest {
    @Test fun independentLedgersObserveReconnectionAndNewFailuresWithoutRestart() {
        val context = IsolatedContext(InstrumentationRegistry.getInstrumentation().targetContext)
        try {
            val executor = EncryptedAgentProviderHealthLedger(context)
            val registry = EncryptedAgentProviderHealthLedger(context)
            val registration = AgentRegistration(agentId = "fixture:codex", displayName = "Fixture",
                installationId = "fixture", deviceId = "fixture", providerId = "fixture",
                kind = AgentConnectorKind.AGENT, location = AgentResourceLocation.TRUSTED_DESKTOP,
                status = AgentEndpointStatus.ONLINE, capabilities = setOf(AgentCapability.CHAT),
                protocol = AgentProtocolRange(preferred = "1.0", minimum = "1.0", maximum = "1.0"),
                connectionKind = AgentConnectionKind.GALAXYSSI_LINK,
                adapterType = "codex-app-server-or-cli", runtimeFailureDomain = "fixture:codex",
                lastHeartbeatMillis = 1_500L)
            assertTrue(registry.snapshots().isEmpty())
            executor.recordFailure(registration, "start_run", AgentProviderFailureKind.TRANSPORT_CRASH, 1, 1_000L)
            assertEquals(1, registry.snapshot(registration).failures)
            registry.observeAvailability(registration, 2_000L)
            assertTrue(executor.acquire(registration, "start_run", 2_001L).probe)
            assertFalse(registry.acquire(registration, "start_run", 2_002L).allowed)
            executor.recordSuccess(registration, "start_run", 1, 2_003L)
            assertEquals(AgentProviderCircuitState.CLOSED, registry.snapshot(registration).circuitState(2_004L))
            executor.recordFailure(registration, "start_run", AgentProviderFailureKind.TRANSPORT_CRASH, 1, 2_005L)
            registry.observeAvailability(registration, 2_006L)
            assertFalse(EncryptedAgentProviderHealthLedger(context).acquire(registration, "start_run", 2_007L).allowed)
        } finally { context.cleanup() }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "provider-recovery-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name)
            baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, handler)
        fun cleanup() { names.forEach(baseContext::deleteDatabase) }
    }
}
