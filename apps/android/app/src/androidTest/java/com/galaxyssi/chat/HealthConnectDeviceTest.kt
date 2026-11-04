package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthConnectDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = System.currentTimeMillis()
    private val window = HealthConnectWindow(24, Instant.ofEpochMilli(now), ZoneId.of("UTC"))
    private class Reader(var grants: Set<String>) : HealthConnectReader {
        val requests = mutableListOf<HealthConnectScope>()
        var rows: (HealthConnectScope) -> List<HealthConnectMeasurement> = { emptyList() }
        override suspend fun granted() = grants
        override suspend fun read(scope: HealthConnectScope, window: HealthConnectWindow, emit: (HealthConnectMeasurement) -> Unit) {
            requests += scope
            rows(scope).forEach(emit)
        }
    }

    private fun bp(id: String, origin: String = "example.watch", upper: String = "120") = HealthConnectMeasurement(
        id, origin, HealthDraft(values = mapOf("systolic" to upper, "diastolic" to "80"), measuredAt = now - 1000))

    private fun database(test: (HealthRecordStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthRecordStore(context, names.records).use(test) } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun previewReadsOnlySelectedAndGrantedScopesAndNeverSaves() = database { store ->
        runBlocking {
            val bloodPressure = HealthConnectScope.BLOOD_PRESSURE
            val reader = Reader(setOf(bloodPressure.permission, HealthConnectScope.WEIGHT.permission)).apply {
                rows = { listOf(bp("sample-1"), bp("sample-1")) }
            }
            val preview = HealthConnectImport.preview(reader, setOf(bloodPressure, HealthConnectScope.SLEEP), window)
            assertEquals(listOf(bloodPressure), reader.requests)
            assertEquals(setOf(bloodPressure), preview.allowed)
            assertEquals(1, preview.rows.size)
            assertEquals(0L, store.count())
        }
    }

    @Test fun revocationAfterPreviewBlocksEveryWrite() = database { store ->
        runBlocking {
            val scope = HealthConnectScope.BLOOD_PRESSURE
            val reader = Reader(setOf(scope.permission)).apply { rows = { listOf(bp("sample-1")) } }
            val preview = HealthConnectImport.preview(reader, setOf(scope), window)
            reader.grants = emptySet()
            assertTrue(runCatching { HealthConnectImport.save(reader, store, preview) }.exceptionOrNull() is HealthConnectPermissionChanged)
            assertEquals(0L, store.count())
        }
    }

    @Test fun repeatImportKeepsEditsAndNeverRestoresDeletedCopies() = database { store ->
        runBlocking {
            val scope = HealthConnectScope.BLOOD_PRESSURE
            val reader = Reader(setOf(scope.permission)).apply {
                rows = { listOf(bp("same-provider-id"), bp("same-provider-id", "example.second")) }
            }
            val preview = HealthConnectImport.preview(reader, setOf(scope), window)
            assertEquals(2, HealthConnectImport.save(reader, store, preview))
            assertEquals(0, HealthConnectImport.save(reader, store, preview))
            assertEquals(0L, store.confirmedImportCount())
            assertNull(store.latestManualMeasurement(now))
            val saved = store.page().records.single { it.platformOrigin == "example.watch" }
            assertEquals("health_connect", saved.source)
            val edited = (store.save(saved.editable().copy(note = "my edit")) as HealthSaveResult.Saved).record
            assertEquals("health_connect", edited.source)
            assertEquals(saved.platformOrigin, edited.platformOrigin)
            assertEquals(0, HealthConnectImport.save(reader, store, preview))
            assertEquals("my edit", store.record(saved.id)!!.draft.note)
            assertTrue(store.delete(edited.id, edited.revision))
            assertEquals(0, HealthConnectImport.save(reader, store, preview))
            assertEquals(1L, store.count())
        }
    }

    @Test fun interruptedImportRollsBackAndCanBeRetried() = database { store ->
        val rows = listOf(bp("first"), bp("second"))
        var processed = 0
        assertTrue(runCatching { store.importHealthConnect(rows) {
            if (processed++ == 1) throw IllegalStateException("Test interruption")
        } }.isFailure)
        assertEquals(0L, store.count())
        assertEquals(2, store.importHealthConnect(rows) {})
    }

    @Test fun versionFourMigratesToPlatformDeduplicationWithoutChangingExistingMeasurements() {
        val name = "health-connect-v4-${UUID.randomUUID()}.db"
        try {
            val original = seedLegacyHealthObservation(context, name, 4, bp("unused").draft)
            HealthRecordStore(context, name).use { store ->
                assertEquals(original, store.record(original.id))
                assertEquals(listOf(original), store.history(original.id))
                assertEquals(1, store.importHealthConnect(listOf(bp("external"))) {})
                assertEquals(0, store.importHealthConnect(listOf(bp("external"))) {})
                assertEquals(2L, store.count())
                assertEquals(HealthRecordStore.SCHEMA_VERSION, store.tableDatabase.version)
            }
        } finally { context.deleteDatabase(name) }
    }

    @Test fun unsupportedOrMissingPlatformKeepsManualFallbackWithoutRequestingPermission() {
        assumeFalse("Source UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val status = HealthSourcesRepository.platform(context)
        assumeFalse("Missing-platform test requires an unavailable provider", status == HealthPlatformAvailability.AVAILABLE)
        ActivityScenario.launch<HealthConnectActivity>(Intent(context, HealthConnectActivity::class.java)).use { scenario ->
            val end = SystemClock.elapsedRealtime() + 10_000
            var shown = false
            while (!shown && SystemClock.elapsedRealtime() < end) {
                scenario.onActivity { shown = it.window.decorView.findViewWithTag<View>("health-connect-unavailable") != null }
                if (!shown) SystemClock.sleep(40)
            }
            assertTrue(shown)
            scenario.onActivity {
                assertNull(it.window.decorView.findViewWithTag<View>("health-connect-scope-BLOOD_PRESSURE"))
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>("health-connect-unavailable")) }
        }
    }
}
