package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Test

class HealthPrivacyStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val trend = HealthAccessScope(HealthAccessPurpose.TREND, setOf(HealthMetric.STEPS))
    private fun fixture(test: (String, HealthPrivacyStore) -> Unit) {
        val name = "health-privacy-test-${UUID.randomUUID()}.db"
        try { HealthPrivacyStore(context, name).use { test(name, it) } } finally { context.deleteDatabase(name) }
    }
    @Test fun firstOpenHasExplicitEncryptedPolicyAndReopenRetainsSettings(): Unit = fixture { name, store ->
        val initial = store.policy()
        assertTrue(initial.metrics); assertTrue(initial.profile); assertFalse(initial.online); assertFalse(initial.images)
        val changed = store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, initial.version)
        HealthPrivacyStore(context, name).use { assertEquals(changed, it.policy()) }
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT payload FROM policy", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.ISO_8859_1).contains("metrics"))
        } }
    }
    @Test fun stalePolicyWriteIsRejectedAndNoopPreservesRevision(): Unit = fixture { _, store ->
        val p = store.policy(); assertEquals(p, store.change(HealthPrivacyOption.CONFIRMED_METRICS, true, p.version))
        val next = store.change(HealthPrivacyOption.PROFILE_CONTEXT, false, p.version)
        assertTrue(runCatching { store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, p.version) }.exceptionOrNull() is HealthPrivacyConflict)
        assertEquals(next, store.policy())
    }
    @Test fun blockedOperationNeverInvokesTheDataReader(): Unit = fixture { _, store ->
        store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, store.policy().version)
        var invoked = false
        assertTrue(runCatching { store.track(trend) { invoked = true } }.exceptionOrNull() is HealthAccessBlocked)
        assertFalse(invoked); assertEquals(HealthAccessOutcome.BLOCKED, store.page().entries.single().outcome)
    }
    @Test fun durableStartIsWrittenBeforeTheReadAndOutcomeUpdatesTheSameEvent(): Unit = fixture { name, store ->
        var id = ""
        val result = store.track(trend) {
            HealthPrivacyStore(context, name).use {
                val started = it.page().entries.single(); assertEquals(HealthAccessOutcome.STARTED, started.outcome); id = started.id
            }; "result"
        }
        assertEquals("result", result)
        val event = store.page().entries.single(); assertEquals(id, event.id); assertEquals(HealthAccessOutcome.COMPLETE, event.outcome)
    }
    @Test fun failureAndCancellationAreNotReportedAsSuccessfulAccess(): Unit = fixture { _, store ->
        val failure = IOException("private filename")
        assertSame(failure, runCatching { store.track(HealthAccessScope.originals(1)) { throw failure } }.exceptionOrNull())
        assertTrue(runCatching { store.track(trend) { throw CancellationException() } }.exceptionOrNull() is CancellationException)
        val events = store.page().entries
        assertEquals(setOf(HealthAccessOutcome.FAILED, HealthAccessOutcome.CANCELLED), events.map { it.outcome }.toSet())
        assertTrue(events.none { it.json().toString().contains("private filename") })
    }
    @Test fun revocationAndReenableDuringUseDoNotReleaseAnOldResult(): Unit = fixture { name, store ->
        val result = runCatching { store.track(trend) {
            HealthPrivacyStore(context, name).use {
                val off = it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
                it.change(HealthPrivacyOption.CONFIRMED_METRICS, true, off.version)
            }
            "old result"
        } }
        assertTrue(result.exceptionOrNull() is HealthAccessBlocked)
        assertEquals(HealthAccessOutcome.BLOCKED, store.page().entries.single().outcome)
    }
    @Test fun userInitiatedFileSaveIsNotBlockedByLocalAnalysisPermission(): Unit = fixture { _, store ->
        val p = store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, store.policy().version)
        store.change(HealthPrivacyOption.PROFILE_CONTEXT, false, p.version)
        assertEquals(3, store.track(HealthAccessScope.originals(3, true)) { 3 })
        assertEquals(HealthAccessOutcome.COMPLETE, store.page().entries.single().outcome)
    }
    @Test fun disablingProfileContextDoesNotHideTheNativeProfileOrReadSelectedEntries(): Unit = fixture { name, privacy ->
        val profile = "health-profile-test-${UUID.randomUUID()}.db"
        try { HealthProfileStore(context, profile, name).use { store ->
            val s = store.snapshot()
            store.saveBasics(HealthProfileDraft(s.generation, mapOf(HealthProfileField.NAME to HealthProfileInput("private test name")),
                mapOf(HealthProfileField.NAME to s.cells.getValue(HealthProfileField.NAME).token)))
            privacy.change(HealthPrivacyOption.PROFILE_CONTEXT, false, privacy.policy().version)
            assertTrue(runCatching { store.capture(setOf(HealthProfileField.NAME), setOf("invalid entry id")) }.exceptionOrNull() is HealthAccessBlocked)
            assertEquals("private test name", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text)
            assertFalse(privacy.page().entries.single().json().toString().contains("private test name"))
        } } finally { context.deleteDatabase(profile) }
    }
    @Test fun corruptPolicyFailsClosedWithoutResettingToDefaults(): Unit = fixture { name, store ->
        store.policy()
        context.openOrCreateDatabase(name, 0, null).use { it.update("policy", ContentValues().apply { put("payload", byteArrayOf(1, 2)) }, "id=1", null) }
        var invoked = false
        assertTrue(runCatching { store.track(trend) { invoked = true } }.isFailure)
        assertFalse(invoked); assertTrue(runCatching { store.policy() }.isFailure)
    }
    @Test fun pagedAuditKeepsEveryEventWithoutDuplicates(): Unit = fixture { _, store ->
        repeat(65) { store.track(HealthAccessScope.originals(it.toLong())) {} }
        val ids = hashSetOf<String>(); var cursor: HealthAccessCursor? = null
        do { val page = store.page(cursor); assertTrue(page.entries.size <= 30); page.entries.forEach { assertTrue(ids.add(it.id)) }; cursor = page.next } while (cursor != null)
        assertEquals(65, ids.size)
    }
    @Test fun auditPayloadCannotBeMovedToAnotherRow(): Unit = fixture { name, store ->
        store.track(trend) {}; store.track(HealthAccessScope.originals(1)) {}
        val entries = store.page().entries
        context.openOrCreateDatabase(name, 0, null).use { db ->
            val payload = db.rawQuery("SELECT payload FROM access_log WHERE id=?", arrayOf(entries[0].id)).use { it.moveToFirst(); it.getBlob(0) }
            db.update("access_log", ContentValues().apply { put("payload", payload) }, "id=?", arrayOf(entries[1].id))
        }
        assertTrue(runCatching { store.page() }.isFailure)
    }
}
