package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthProfileStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (String, HealthProfileStore) -> Unit) {
        val name = "health-profile-test-${id()}.db"
        val privacy = "health-privacy-test-${id()}.db"
        try { HealthProfileStore(context, name, privacy).use { test(name, it) } }
        finally { context.deleteDatabase(name); context.deleteDatabase(privacy) }
    }
    private fun change(store: HealthProfileStore, field: HealthProfileField, value: String, unit: String = ""): HealthProfileDraft {
        val s = store.snapshot(); return HealthProfileDraft(s.generation, mapOf(field to HealthProfileInput(value, unit)), mapOf(field to s.cells.getValue(field).token))
    }
    private fun add(store: HealthProfileStore, n: Int = 1, kind: HealthBackgroundKind = HealthBackgroundKind.HISTORY): HealthBackgroundEntry {
        val d = store.newEntry(kind); return store.saveEntry(d.copy(entry = d.entry.copy(name = "self report $n", detail = "private context $n")))
    }
    @Test fun emptyProfileHasNoInferredBirthSexHeightOrNormalConclusion(): Unit = fixture { _, store ->
        val s = store.snapshot(); assertTrue(s.cells.values.all { it.value == null }); assertTrue(s.counts.values.all { it == 0L }); assertNull(s.draft)
    }
    @Test fun basicFactsSurviveReopeningAsEncryptedSelfReportedRows(): Unit = fixture { name, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "private-profile-name"))
        HealthProfileStore(context, name).use { assertEquals("private-profile-name", it.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text) }
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT payload FROM basics", null).use { it.moveToFirst(); assertFalse(it.getBlob(0).toString(Charsets.ISO_8859_1).contains("private-profile-name")) } }
    }
    @Test fun basicDraftsAreEncryptedAndDoNotCountAsConfirmedContext(): Unit = fixture { name, store ->
        val d = change(store, HealthProfileField.BIRTH_DATE, "2026-"); store.draft(d)
        HealthProfileStore(context, name).use { assertEquals(d, it.basicDraft()); assertNull(it.snapshot().cells.getValue(HealthProfileField.BIRTH_DATE).value) }
        assertTrue(runCatching { store.saveBasics(d) }.isFailure); assertEquals(d, store.basicDraft())
    }
    @Test fun invalidBatchIsAtomicAndDoesNotSaveTheValidPart(): Unit = fixture { _, store ->
        val s = store.snapshot(); val d = HealthProfileDraft(s.generation, mapOf(HealthProfileField.NAME to HealthProfileInput("name"), HealthProfileField.BIRTH_DATE to HealthProfileInput("2099-01-01")),
            mapOf(HealthProfileField.NAME to "", HealthProfileField.BIRTH_DATE to ""))
        assertTrue(runCatching { store.saveBasics(d) }.isFailure); assertTrue(store.snapshot().cells.values.all { it.value == null })
    }
    @Test fun independentFieldEditsDoNotConflictWithAnUnrelatedFieldChange(): Unit = fixture { _, store ->
        val name = change(store, HealthProfileField.NAME, "Name"); val height = change(store, HealthProfileField.HEIGHT, "172", "cm")
        store.saveBasics(name); store.saveBasics(height)
        assertEquals("Name", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text); assertEquals("172", store.snapshot().cells.getValue(HealthProfileField.HEIGHT).value!!.text)
    }
    @Test fun staleFieldVersionsCannotOverwriteNewerFacts(): Unit = fixture { _, store ->
        val old = change(store, HealthProfileField.NAME, "older"); store.draft(old); store.saveBasics(change(store, HealthProfileField.NAME, "newer"))
        assertTrue(runCatching { store.saveBasics(old) }.exceptionOrNull() is HealthProfileConflict)
        assertEquals("newer", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text)
    }
    @Test fun independentDraftFieldsMergeAndSavingOneKeepsTheOthers(): Unit = fixture { _, store ->
        val name = change(store, HealthProfileField.NAME, "Name"); val height = change(store, HealthProfileField.HEIGHT, "170", "cm")
        store.draft(name); store.draft(height); assertEquals(2, store.basicDraft()!!.changes.size)
        store.saveBasics(name); assertEquals(height, store.basicDraft()); assertEquals("Name", store.snapshot().cells.getValue(HealthProfileField.NAME).value!!.text)
    }
    @Test fun cancellingOneFieldDoesNotEraseAConcurrentUnrelatedDraft(): Unit = fixture { _, store ->
        val name = change(store, HealthProfileField.NAME, "Name"); val height = change(store, HealthProfileField.HEIGHT, "170", "cm")
        store.draft(name); store.draft(height); store.restoreBasicField(HealthProfileField.NAME, null, name.generation, name.changes[HealthProfileField.NAME])
        assertEquals(height, store.basicDraft())
    }
    @Test fun exactNoopSaveKeepsTheDependencyTokenStable(): Unit = fixture { _, store ->
        store.saveBasics(change(store, HealthProfileField.HEIGHT, "172.50", "cm")); val stamp = store.capture(setOf(HealthProfileField.HEIGHT), emptySet()).stamp
        store.saveBasics(change(store, HealthProfileField.HEIGHT, "0172,5", "cm")); assertTrue(store.isCurrent(stamp))
    }
    @Test fun clearingOneFieldDoesNotDeleteAnotherAndInvalidatesTheUsedFact(): Unit = fixture { _, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "Name")); store.saveBasics(change(store, HealthProfileField.HEIGHT, "170", "cm"))
        val stamp = store.capture(setOf(HealthProfileField.HEIGHT), emptySet()).stamp; store.saveBasics(change(store, HealthProfileField.HEIGHT, ""))
        assertFalse(store.isCurrent(stamp)); assertNull(store.snapshot().cells.getValue(HealthProfileField.HEIGHT).value); assertNotNull(store.snapshot().cells.getValue(HealthProfileField.NAME).value)
    }
    @Test fun absenceThenCreationThenDeletionCannotProduceAnAbaFreshnessMatch(): Unit = fixture { _, store ->
        val absent = store.capture(setOf(HealthProfileField.NAME), emptySet()).stamp
        store.saveBasics(change(store, HealthProfileField.NAME, "Name")); store.saveBasics(change(store, HealthProfileField.NAME, ""))
        assertFalse(store.isCurrent(absent))
    }
    @Test fun contextsContainOnlyExplicitlySelectedFactsAndEntries(): Unit = fixture { _, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "private name")); store.saveBasics(change(store, HealthProfileField.HEIGHT, "170", "cm"))
        val wanted = add(store, 1); add(store, 2, HealthBackgroundKind.ALLERGY)
        val c = store.capture(setOf(HealthProfileField.HEIGHT), setOf(wanted.id)); assertEquals(setOf(HealthProfileField.HEIGHT), c.fields.keys)
        assertEquals(listOf(wanted), c.entries); assertEquals("self_reported", c.source); assertEquals("self", c.profileId)
    }
    @Test fun draftsAndUnrelatedFactsDoNotInvalidateASelectedAnalysisContext(): Unit = fixture { _, store ->
        store.saveBasics(change(store, HealthProfileField.HEIGHT, "170", "cm")); val stamp = store.capture(setOf(HealthProfileField.HEIGHT), emptySet()).stamp
        store.draft(change(store, HealthProfileField.HEIGHT, "190", "cm")); assertTrue(store.isCurrent(stamp))
        store.saveBasics(change(store, HealthProfileField.NAME, "Name")); add(store); assertTrue(store.isCurrent(stamp))
    }
    @Test fun ninetyFiveBackgroundEntriesUseBoundedStablePagesWithoutATotalCap(): Unit = fixture { _, store ->
        val expected = (0..94).map { add(store, it).id }.toSet(); var after: HealthBackgroundCursor? = null; val seen = hashSetOf<String>()
        do { val page = store.page(HealthBackgroundKind.HISTORY, after); assertTrue(page.entries.size <= 30); page.entries.forEach { assertTrue(seen.add(it.id)) }; after = page.next } while (after != null)
        assertEquals(expected, seen); assertEquals(95L, store.count(HealthBackgroundKind.HISTORY)); assertEquals(0L, store.count(HealthBackgroundKind.ALLERGY))
    }
    @Test fun pagingRejectsMixedCategoryVersionsButNotUnrelatedCategoryChanges(): Unit = fixture { _, store ->
        repeat(35) { add(store, it) }; val page = store.page(HealthBackgroundKind.HISTORY); add(store, 1, HealthBackgroundKind.ALLERGY)
        assertTrue(store.isCurrent(page.stamp)); assertNotNull(store.page(HealthBackgroundKind.HISTORY, page.next))
        add(store, 100); assertFalse(store.isCurrent(page.stamp)); assertTrue(runCatching { store.page(HealthBackgroundKind.HISTORY, page.next) }.exceptionOrNull() is HealthProfileConflict)
    }
    @Test fun backgroundDraftsResumeAcrossReopenWithoutChangingTheSavedEntry(): Unit = fixture { name, store ->
        val e = add(store); val d = store.editEntry(e.id).let { it.copy(entry = it.entry.copy(detail = "unfinished edit")) }; store.draft(d)
        HealthProfileStore(context, name).use { assertEquals(d, it.editEntry(e.id)); assertEquals(e, it.entry(e.id)) }
    }
    @Test fun backgroundUpdatesAndDeletesEnforceOptimisticVersions(): Unit = fixture { _, store ->
        val e = add(store); val old = store.editEntry(e.id); val updated = store.saveEntry(old.copy(entry = old.entry.copy(name = "new version")))
        assertTrue(runCatching { store.saveEntry(old) }.exceptionOrNull() is HealthProfileConflict)
        assertTrue(runCatching { store.deleteEntry(e.id, e.token, old.generation) }.exceptionOrNull() is HealthProfileConflict)
        store.deleteEntry(e.id, updated.token, old.generation); assertNull(store.entry(e.id))
    }
    @Test fun anEntryCannotMoveCategoryWithoutInvalidatingItsOriginalCategory(): Unit = fixture { _, store ->
        val e = add(store); val d = store.editEntry(e.id); assertTrue(runCatching { store.saveEntry(d.copy(entry = d.entry.copy(kind = HealthBackgroundKind.ALLERGY))) }.isFailure)
        assertEquals(e, store.entry(e.id))
    }
    @Test fun deletingAnEntryAlsoRemovesItsDraftAndInvalidatesSelectedContext(): Unit = fixture { _, store ->
        val e = add(store); val d = store.editEntry(e.id); store.draft(d); val stamp = store.capture(emptySet(), setOf(e.id)).stamp
        store.deleteEntry(e.id, e.token, d.generation); assertNull(store.entryDraft(d.key)); assertFalse(store.isCurrent(stamp))
        assertTrue(runCatching { store.draft(d) }.exceptionOrNull() is HealthProfileConflict)
    }
    @Test fun deletionPreviewRejectsNewFactsAndChangesToAnExistingDraft(): Unit = fixture { _, store ->
        val preview = store.deletePreview(); add(store); assertTrue(runCatching { store.clear(preview) }.exceptionOrNull() is HealthProfileConflict)
        val d = change(store, HealthProfileField.NAME, "first draft"); store.draft(d); val p = store.deletePreview()
        store.draft(d.copy(changes = mapOf(HealthProfileField.NAME to HealthProfileInput("changed draft"))))
        assertTrue(runCatching { store.clear(p) }.exceptionOrNull() is HealthProfileConflict)
    }
    @Test fun deletingTheWholeProfileRejectsOldDraftsAndSavesAcrossReopen(): Unit = fixture { name, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "private name")); val basic = change(store, HealthProfileField.HEIGHT, "170", "cm")
        val background = store.newEntry(HealthBackgroundKind.MEDICATION); store.draft(background); val stamp = store.capture(setOf(HealthProfileField.NAME), emptySet()).stamp
        store.clear(store.deletePreview()); assertFalse(store.isCurrent(stamp))
        HealthProfileStore(context, name).use { reopened ->
            assertTrue(runCatching { reopened.draft(basic) }.exceptionOrNull() is HealthProfileConflict)
            assertTrue(runCatching { reopened.saveEntry(background.copy(entry = background.entry.copy(name = "stale"))) }.exceptionOrNull() is HealthProfileConflict)
            assertTrue(reopened.snapshot().cells.values.all { it.value == null }); assertEquals(0L, reopened.deletePreview().drafts)
        }
    }
    @Test fun deletingProfileDoesNotTouchTheIndependentMeasurementDatabase(): Unit = fixture { _, store ->
        val measurements = "health-profile-measurement-test-${id()}.db"
        try { HealthRecordStore(context, measurements).use { records ->
            records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "60"), "kg", 1_790_000_000_000L))
            store.saveBasics(change(store, HealthProfileField.NAME, "name")); add(store); store.clear(store.deletePreview()); assertEquals(1L, records.count())
        } } finally { context.deleteDatabase(measurements) }
    }
    @Test fun encryptedFieldPayloadsCannotBeSwappedBetweenBasicKeys(): Unit = fixture { name, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "private")); store.saveBasics(change(store, HealthProfileField.PHYSIOLOGICAL_CONTEXT, "context"))
        context.openOrCreateDatabase(name, 0, null).use { db ->
            val bytes = db.rawQuery("SELECT payload FROM basics WHERE field='NAME'", null).use { it.moveToFirst(); it.getBlob(0) }
            db.update("basics", ContentValues().apply { put("payload", bytes) }, "field='PHYSIOLOGICAL_CONTEXT'", null)
        }
        assertTrue(runCatching { store.snapshot() }.isFailure)
    }
    @Test fun backgroundPayloadsAreEncryptedAndBoundToIdentityAndKind(): Unit = fixture { name, store ->
        val a = add(store); val b = add(store, 2, HealthBackgroundKind.ALLERGY)
        context.openOrCreateDatabase(name, 0, null).use { db ->
            val bytes = db.rawQuery("SELECT payload FROM entries WHERE id=?", arrayOf(a.id)).use { it.moveToFirst(); it.getBlob(0) }
            assertFalse(bytes.toString(Charsets.ISO_8859_1).contains(a.detail)); db.update("entries", ContentValues().apply { put("payload", bytes) }, "id=?", arrayOf(b.id))
        }
        assertTrue(runCatching { store.entry(b.id) }.isFailure); assertEquals(a, store.entry(a.id))
    }
    @Test fun corruptedVersionClocksFailExplicitlyWithoutClearingTheProfile(): Unit = fixture { name, store ->
        store.saveBasics(change(store, HealthProfileField.NAME, "Name"))
        context.openOrCreateDatabase(name, 0, null).use { db -> db.update("clocks", ContentValues().apply { put("payload", byteArrayOf(1, 2)) }, "key='field:NAME'", null) }
        assertTrue(runCatching { store.snapshot() }.isFailure)
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT COUNT(*) FROM basics", null).use { it.moveToFirst(); assertEquals(1L, it.getLong(0)) } }
    }
    @Test fun invalidNewBackgroundEntriesDoNotPartiallyPersist(): Unit = fixture { _, store ->
        val d = store.newEntry(HealthBackgroundKind.ALLERGY); store.draft(d)
        assertTrue(runCatching { store.saveEntry(d) }.isFailure); assertEquals(0L, store.count(HealthBackgroundKind.ALLERGY)); assertEquals(d, store.entryDraft(d.key))
    }
}
