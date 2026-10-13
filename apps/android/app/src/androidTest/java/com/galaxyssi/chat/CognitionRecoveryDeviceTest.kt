package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CognitionRecoveryDeviceTest {
    @Test fun encryptedRepositoryRepairsTruncatedEdgesAndPersistsAllLinks() = isolated { context ->
        val previous = (1..40).map { item("old-$it").copy(status = GlobalWorldItemStatus.SUPERSEDED,
            supersededByItemId = "new") }
        GlobalAgentRepository(context).saveWorld(PersonalWorldModel(items = previous + item("new").copy(
            supersedesItemIds = previous.takeLast(12).map { it.id })))
        val restored = GlobalAgentRepository(context)
        val repaired = restored.promptContextSnapshot().world
        assertEquals(40, repaired.items.last().supersedesItemIds.size)
        GlobalMemorySupersessionPolicy.inspect(repaired).requireSafe()
        assertEquals(repaired, GlobalAgentRepository(context).loadWorld())
        assertEquals(repaired, restored.loadWorld())
    }

    @Test fun encryptedRetryBudgetSurvivesNewInstancesAndManualResumeIsIdempotent() = isolated { context ->
        val mode = AndroidCognitionWorkMode.SCHEDULED
        repeat(10) { AndroidCognitionRecovery(context).failed(mode, IllegalStateException("fixture")) }
        assertFalse(AndroidCognitionRecovery(context).mayAttempt(mode))
        assertEquals(10, AndroidCognitionRecovery(context).state(mode).failures)
        AndroidCognitionRecovery(context).resumeOnce("fixture-resume")
        assertTrue(AndroidCognitionRecovery(context).mayAttempt(mode))
        AndroidCognitionRecovery(context).failed(mode, IllegalStateException("fixture"))
        AndroidCognitionRecovery(context).resumeOnce("fixture-resume")
        assertEquals(1, AndroidCognitionRecovery(context).state(mode).failures)
    }

    @Test fun inspectInstalledWorldWithoutModelCallsOrContentLogging() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("inspect_existing") == "true")
        val context = ApplicationProvider.getApplicationContext<Context>()
        val stored = GlobalAgentRepository(context).loadWorld()
        GlobalMemorySupersessionPolicy.inspect(stored).requireSafe()
        val audited = GlobalMemoryCritic.audit(stored, GlobalMemoryInbox()).first
        GlobalMemorySupersessionPolicy.inspect(audited).requireSafe()
        Log.i("GalaxySSICognitionTest", "installed_items=${stored.items.size} audited_items=${audited.items.size} integrity=passed")
    }

    private fun item(id: String) = GlobalWorldItem(id = id, stableKey = "fixture-$id",
        kind = GlobalWorldItemKind.FACT, layer = GlobalWorldLayer.TOPIC, topic = "Fixture", value = "Fixture",
        confidence = 0.9, evidenceCount = 1, conversationIds = emptySet(), evidenceEventIds = emptyList(),
        firstSeenAtMillis = 1L, lastSeenAtMillis = 1L)

    private fun isolated(block: (Context) -> Unit) {
        val context = IsolatedContext(ApplicationProvider.getApplicationContext())
        try { block(context) } finally { context.cleanup() }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "cognition-fixture-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name)
            baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?,
            errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
        fun cleanup() { names.forEach(baseContext::deleteDatabase) }
    }
}
