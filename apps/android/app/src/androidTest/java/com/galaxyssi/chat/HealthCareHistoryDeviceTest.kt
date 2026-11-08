package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareHistoryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthRecordStore, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthRecordStore(context, names.records).use { records -> HealthCareStore(context, names.care).use { care ->
            care.configure(true, care.settings().version); test(names, records, care)
        } } } finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun save(records: HealthRecordStore, at: Long, value: String = "6.3") = (records.save(HealthDraft(
        HealthMetric.GLUCOSE, mapOf("glucose" to value), "mmol/L", at, condition = "fasting", reference = "4-6")) as HealthSaveResult.Saved).record
    private fun grant(names: HealthOverviewDatabases, care: HealthCareStore): Pair<HealthCareConcern, HealthCareDiscussionGrant> {
        HealthCareEngine.evaluate(context, names)
        val prior = care.forMetric(HealthMetric.GLUCOSE)!!
        val issue = care.bindDiscussion(prior.id, prior.revision, UUID.randomUUID().toString())
        val privacy = HealthPrivacyStore(context, names.privacy).use { it.policy() }
        val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, privacy.version, "a".repeat(64), System.currentTimeMillis(), "fixture-provider", "fixture-model", "high")
        care.approveDiscussion(grant)
        return issue to grant
    }
    private fun read(names: HealthOverviewDatabases, issue: HealthCareConcern, grant: HealthCareDiscussionGrant,
        extra: Map<String, Any?> = emptyMap(), conversation: String = grant.conversationId) = HealthCareHistoryTool.read(context, names,
        AgentNativeToolInvocationContext(conversationId = conversation, turnId = grant.turnId), mapOf("input_version" to issue.inputVersion) + extra)

    @Test fun contiguousPagesPreserveSameTimeRowsAndAllHistoryWithoutDuplication(): Unit = fixture { names, records, care ->
        val at = System.currentTimeMillis() - 1000
        val saved = (0..64).map { save(records, at, "6.${it.toString().padStart(2, '0')}") }
        val (issue, grant) = grant(names, care)
        assertEquals(30, issue.assessment.series!!.samples.size); assertTrue(issue.assessment.series!!.hasEarlier)
        val ids = mutableListOf<String>(); var cursor = emptyMap<String, Any?>()
        do {
            val result = read(names, issue, grant, cursor)
            val samples = result.getJSONObject("history").getJSONArray("samples")
            assertTrue(samples.length() <= 30)
            (0 until samples.length()).forEach { ids += samples.getJSONObject(it).getJSONObject("record").getString("id") }
            cursor = result.optJSONObject("next")?.let { mapOf("before_time" to it.getLong("before_time"), "before_id" to it.getString("before_id")) } ?: emptyMap()
        } while (cursor.isNotEmpty())
        assertEquals(saved.map { it.id }.sortedDescending(), ids); assertEquals(65, ids.distinct().size)
        assertEquals(issue, care.concern(issue.id)); assertNull(care.nextDue())
    }
    @Test fun fewerThanOnePageAndEmptyEndAreExplicit(): Unit = fixture { names, records, care ->
        val old = save(records, System.currentTimeMillis() - 1000)
        val (issue, grant) = grant(names, care)
        assertFalse(issue.assessment.series!!.hasEarlier)
        assertTrue(read(names, issue, grant).getBoolean("done"))
        val empty = read(names, issue, grant, mapOf("before_time" to old.draft.measuredAt, "before_id" to old.id))
        assertTrue(empty.isNull("history")); assertTrue(empty.getBoolean("done"))
    }
    @Test fun historyChangesRejectAllSubsequentPagesBeforeReconciliation(): Unit = fixture { names, records, care ->
        val old = save(records, System.currentTimeMillis() - 1000)
        val (issue, grant) = grant(names, care)
        read(names, issue, grant)
        records.save(old.editable().copy(values = mapOf("glucose" to "5.4")))
        assertTrue(runCatching { read(names, issue, grant) }.exceptionOrNull() is HealthCareConflict)
        HealthCareEngine.evaluate(context, names)
        val updated = care.concern(issue.id)!!
        assertEquals("5.4", updated.assessment.series!!.samples.single().values.getValue("glucose"))
        assertEquals(1, updated.assessment.series!!.samples.size)
    }
    @Test fun wrongConversationVersionAndRevokedPermissionCannotRead(): Unit = fixture { names, records, care ->
        save(records, System.currentTimeMillis() - 1000)
        val (issue, grant) = grant(names, care)
        assertTrue(runCatching { read(names, issue, grant, conversation = UUID.randomUUID().toString()) }.exceptionOrNull() is HealthCareConflict)
        assertTrue(runCatching { read(names, issue, grant, mapOf("input_version" to "other")) }.exceptionOrNull() is HealthCareConflict)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version) }
        assertTrue(runCatching { read(names, issue, grant) }.exceptionOrNull() is HealthCareConflict)
    }
    @Test fun deletingOldMeasurementRemovesItAndDoesNotLeakPrivateSourceMetadata(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        val old = save(records, now - 5000); save(records, now - 1000)
        val (issue, _) = grant(names, care)
        assertEquals(2, issue.assessment.series!!.samples.size)
        records.delete(old.id, old.revision); HealthCareEngine.evaluate(context, names)
        val next = care.concern(issue.id)!!
        assertEquals(1, next.assessment.series!!.samples.size)
        val snapshot = JSONObject(HealthCareDiscussionPolicy.snapshot(next))
        assertFalse(snapshot.toString().contains("device_group")); assertFalse(snapshot.toString().contains(old.id))
        HealthCareStore(context, names.care).use { assertEquals(next, it.concern(next.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM concerns", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains("samples"))
        } }
    }
    @Test fun otherMetricsAndFutureMeasurementsDoNotEnterCurrentWindow(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        save(records, now - 1000)
        save(records, now + 60_000)
        records.save(HealthDraft(HealthMetric.HBA1C, mapOf("hba1c" to "7"), "%", now - 1000))
        val (issue, grant) = grant(names, care)
        val samples = read(names, issue, grant).getJSONObject("history").getJSONArray("samples")
        assertEquals(1, samples.length()); assertEquals("GLUCOSE", samples.getJSONObject(0).getString("metric"))
    }
    @Test fun oldAnchorIsNotInsertedIntoAContiguousRecentWindow(): Unit = fixture { names, records, care ->
        val now = System.currentTimeMillis()
        val old = save(records, now - 40 * 86_400_000L); HealthCareEngine.evaluate(context, names)
        repeat(35) { save(records, now - (35 - it) * 86_400_000L, "5.4") }
        HealthCareEngine.evaluate(context, names)
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        assertEquals(old.id, issue.assessment.comparison!!.before.record.id)
        assertEquals(30, issue.assessment.series!!.samples.size)
        assertFalse(issue.assessment.series!!.samples.any { it.record.id == old.id })
        assertEquals(0, HealthCareEngine.evaluate(context, names))
    }
}
