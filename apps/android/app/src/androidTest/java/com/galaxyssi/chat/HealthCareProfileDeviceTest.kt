package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareProfileDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun fixture(test: (HealthOverviewDatabases, HealthProfileStore, HealthCareStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
                mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis() - 60_000, reference = "4-6")) }
            HealthCareStore(context, names.care).use { care ->
                care.configure(true, ""); HealthCareEngine.evaluate(context, names)
                HealthProfileStore(context, names.profile, names.privacy).use { profile -> test(names, profile, care) }
            }
        } finally { listOf(names.profile, names.care, names.records, names.privacy).forEach(context::deleteDatabase) }
    }
    private fun change(profile: HealthProfileStore, field: HealthProfileField, value: String, unit: String = ""): HealthProfileDraft {
        val before = profile.snapshot()
        return HealthProfileDraft(before.generation, mapOf(field to HealthProfileInput(value, unit)), mapOf(field to before.cells.getValue(field).token))
    }
    private fun select(profile: HealthProfileStore, care: HealthCareStore, fields: Set<HealthProfileField>, entries: Set<String> = emptySet()): HealthCareConcern {
        val snapshot = profile.capture(fields, entries)
        val link = HealthCareProfileLink(HealthCareProfileScope(snapshot.stamp.generation, fields, entries), snapshot.stamp)
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        return care.update(issue.id, issue.revision, "fixture_profile_selected") { it.copy(profileLink = link) }
    }
    @Test fun onlySelectedSavedFactsReachThePromptAndSelectionSurvivesReopen(): Unit = fixture { names, profile, care ->
        profile.saveBasics(change(profile, HealthProfileField.NAME, "never-share-fixture-name"))
        profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "170", "cm"))
        profile.draft(change(profile, HealthProfileField.HEIGHT, "190", "cm"))
        val selected = profile.newEntry(HealthBackgroundKind.HISTORY).let { profile.saveEntry(it.copy(entry = it.entry.copy(name = "selected-fixture-history"))) }
        profile.newEntry(HealthBackgroundKind.ALLERGY).let { profile.saveEntry(it.copy(entry = it.entry.copy(name = "unselected-fixture-allergy"))) }
        val issue = select(profile, care, setOf(HealthProfileField.HEIGHT), setOf(selected.id))
        val capture = HealthCareProfileAccess.capture(context, issue.profileLink!!, names)
        val prompt = HealthCareDiscussionPolicy.snapshot(issue, profile = capture)
        assertTrue(prompt.contains("170")); assertTrue(prompt.contains("selected-fixture-history"))
        assertFalse(prompt.contains("190")); assertFalse(prompt.contains("never-share-fixture-name")); assertFalse(prompt.contains("unselected-fixture-allergy"))
        HealthCareStore(context, names.care).use { assertEquals(issue, it.concern(issue.id)) }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM concerns", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.ISO_8859_1).contains(selected.id))
        } }
    }
    @Test fun selectedEditsReassessOnceAndInvalidateThePreviousTurn(): Unit = fixture { names, profile, care ->
        profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "170", "cm"))
        var issue = select(profile, care, setOf(HealthProfileField.HEIGHT))
        issue = care.bindDiscussion(issue.id, issue.revision, UUID.randomUUID().toString())
        val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, HealthPrivacyStore(context, names.privacy).use { it.policy().version },
            "a".repeat(64), System.currentTimeMillis(), "fixture", "fixture-model", "high", profileLink = issue.profileLink)
        care.approveDiscussion(grant)
        val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, "b".repeat(64))
        care.authorizeResearch(authorization, null)
        val initial = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
        profile.saveBasics(change(profile, HealthProfileField.NAME, "unrelated-name"))
        HealthCareEngine.evaluate(context, names)
        assertEquals(issue, care.concern(issue.id))
        profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "172", "cm"))
        assertFalse(HealthCareProfileAccess.current(context, grant.profileLink, names))
        HealthCareEngine.evaluate(context, names)
        val refreshed = care.concern(issue.id)!!
        assertEquals(issue.revision + 1, refreshed.revision)
        assertEquals(HealthCareStage.REASSESS, refreshed.stage)
        assertTrue(runCatching { care.approveDiscussion(grant.copy(turnId = UUID.randomUUID().toString())) }.exceptionOrNull() is HealthCareConflict)
        assertTrue(authorization.permits(grant.copy(researchAuthorizationId = authorization.id, revision = refreshed.revision, profileLink = refreshed.profileLink)))
        val next = care.queueResearch(authorization.id, issue.id, System.currentTimeMillis())
        assertNotEquals(initial.turnId, next.turnId)
        HealthCareEngine.evaluate(context, names)
        assertEquals(refreshed, care.concern(issue.id))
        assertEquals(next.turnId, care.queueResearch(authorization.id, issue.id, System.currentTimeMillis()).turnId)
    }
    @Test fun deletedEntryIsRemovedFromTheNextSnapshotAndArchiveResetRequiresNewSelection(): Unit = fixture { names, profile, care ->
        val entry = profile.newEntry(HealthBackgroundKind.MEDICATION).let { profile.saveEntry(it.copy(entry = it.entry.copy(name = "fixture-only-medication"))) }
        val issue = select(profile, care, emptySet(), setOf(entry.id))
        profile.deleteEntry(entry.id, entry.token, profile.currentGeneration())
        assertFalse(HealthCareProfileAccess.current(context, issue.profileLink, names))
        HealthCareEngine.evaluate(context, names)
        val refreshed = care.concern(issue.id)!!
        val capture = HealthCareProfileAccess.capture(context, refreshed.profileLink!!, names)
        val result = JSONObject(HealthCareDiscussionPolicy.snapshot(refreshed, profile = capture)).getJSONObject("selected_profile")
        assertEquals(entry.id, result.getJSONArray("unavailable_selected_entries").getString(0))
        assertEquals(0, result.getJSONArray("entries").length())
        assertFalse(result.toString().contains("fixture-only-medication"))
        assertEquals(capture.stamp, profile.dependencyStamp(emptySet(), setOf(entry.id)))
        profile.clear(profile.deletePreview())
        assertFalse(HealthCareProfileAccess.current(context, refreshed.profileLink, names))
        assertTrue(runCatching { HealthCareProfileAccess.capture(context, refreshed.profileLink, names) }.exceptionOrNull() is HealthProfileConflict)
    }
    @Test fun profileWithdrawalBlocksAccessAndNewScopeDoesNotReuseOldConsent(): Unit = fixture { names, profile, care ->
        var issue = select(profile, care, setOf(HealthProfileField.HEIGHT))
        issue = care.bindDiscussion(issue.id, issue.revision, UUID.randomUUID().toString())
        val grant = HealthCareDiscussionGrant(issue.conversationId, UUID.randomUUID().toString(), issue.id, issue.revision,
            care.settings().version, "privacy", "a".repeat(64), System.currentTimeMillis(), "fixture", "fixture", "high", profileLink = issue.profileLink)
        val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, "b".repeat(64))
        care.authorizeResearch(authorization, null)
        select(profile, care, setOf(HealthProfileField.HEIGHT, HealthProfileField.REFERENCE_SEX))
        assertTrue(runCatching { care.queueResearch(authorization.id, issue.id, System.currentTimeMillis()) }.exceptionOrNull() is HealthCareConflict)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertFalse(HealthCareProfileAccess.current(context, issue.profileLink, names))
        assertTrue(runCatching { HealthCareProfileAccess.capture(context, issue.profileLink!!, names) }.exceptionOrNull() is HealthAccessBlocked)
    }
    @Test fun missingEntryTombstonesPreventDeleteRestoreDeleteAba(): Unit = fixture { _, profile, _ ->
        val entry = profile.newEntry(HealthBackgroundKind.HISTORY).let { profile.saveEntry(it.copy(entry = it.entry.copy(name = "fixture"))) }
        profile.deleteEntry(entry.id, entry.token, profile.currentGeneration())
        val stamp = profile.capture(emptySet(), setOf(entry.id), allowMissingEntries = true).stamp
        val restored = profile.saveEntry(HealthBackgroundDraft(profile.currentGeneration(), entry.copy(token = "", updatedAt = 0)))
        profile.deleteEntry(restored.id, restored.token, profile.currentGeneration())
        assertFalse(profile.isCurrent(stamp))
        assertTrue(runCatching { profile.capture(emptySet(), setOf(entry.id)) }.exceptionOrNull() is HealthProfileConflict)
    }

    @Test fun reducingScopeOpensANewLinkedConversationWithoutImportingOldProfileAnswers(): Unit = fixture { names, profile, care ->
        val issue = select(profile, care, setOf(HealthProfileField.HEIGHT, HealthProfileField.REFERENCE_SEX))
        val transcripts = AgentTranscriptStore(context)
        val conversations = mutableListOf<String>()
        try {
            val first = HealthCareDiscussion.open(context, issue.id, names).also(conversations::add)
            transcripts.append(AgentTranscriptRole.ASSISTANT, "Synthetic withdrawn profile answer", conversationId = first)
            val reduced = select(profile, care, setOf(HealthProfileField.HEIGHT))
            assertNull(care.discussion(first))
            assertTrue(runCatching { care.bindDiscussion(reduced.id, reduced.revision, first) }.exceptionOrNull() is HealthCareConflict)
            val next = HealthCareDiscussion.open(context, issue.id, names).also(conversations::add)
            assertNotEquals(first, next); assertEquals(issue.id, care.discussion(next))
            assertTrue(transcripts.list(first).isNotEmpty()); assertTrue(transcripts.list(next).isEmpty())
            profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "172", "cm"))
            HealthCareEngine.evaluate(context, names)
            assertEquals(next, HealthCareDiscussion.open(context, issue.id, names))
        } finally { conversations.forEach(transcripts::deleteConversation) }
    }

    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup)
        (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun review(activity: HealthCareActivity) = HealthCareActivity::class.java.getDeclaredMethod("getProfileReview")
        .apply { isAccessible = true }.invoke(activity) as HealthCareProfileReview
    private fun dialog(activity: HealthCareActivity) = HealthCareProfileReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review(activity)) as? AlertDialog
    private fun await(scenario: ActivityScenario<HealthCareActivity>, ready: (HealthCareActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do {
            var done = false; scenario.onActivity { done = ready(it) }
            if (done) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Profile selection did not reach the expected UI state")
    }
    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("health_care_screenshot") != "true") return
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        SystemClock.sleep(400)
        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
            java.io.File(context.getExternalFilesDir(null), name).outputStream().use {
                image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally { image.recycle() } }
    }
    @Test fun personalHealthSelectionPersistsClearsOnBackgroundAndCanBeRemoved(): Unit = fixture { names, profile, care ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "170", "cm"))
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", issue.id).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { views(it.window.decorView).any { view -> view.tag == "health-care-profile" } }
                scenario.onActivity { activity ->
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(activity) as ExecutorService
                    review(activity).show(issue.id)
                }
                await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity {
                    val root = dialog(it)!!.window!!.decorView
                    assertFalse(views(root).any { view -> view.tag == "health-care-profile-field-NAME" })
                    (views(root).first { view -> view.tag == "health-care-profile-field-HEIGHT" } as CheckBox).performClick()
                    dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { dialog(it) == null }
                assertEquals(setOf(HealthProfileField.HEIGHT), care.concern(issue.id)!!.profileLink!!.scope.fields)
                scenario.onActivity { review(it).show(issue.id) }
                await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity {
                    assertTrue((views(dialog(it)!!.window!!.decorView).first { view -> view.tag == "health-care-profile-field-HEIGHT" } as CheckBox).isChecked)
                }
                capture("health-profile-selection-fixture.png")
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(dialog(it)) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { views(it.window.decorView).any { view -> view.tag == "health-care-profile" } }
                scenario.onActivity { review(it).show(issue.id) }
                await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_NEUTRAL).performClick() }
                await(scenario) { dialog(it) == null }
                assertNull(care.concern(issue.id)!!.profileLink)
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
    @Test fun profileEditDismissesAStaleSelectionWithoutSavingIt(): Unit = fixture { names, profile, care ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", issue.id).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { views(it.window.decorView).any { view -> view.tag == "health-care-profile" } }
                scenario.onActivity {
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    review(it).show(issue.id)
                }
                await(scenario) { dialog(it)?.isShowing == true }
                profile.saveBasics(change(profile, HealthProfileField.HEIGHT, "172", "cm"))
                await(scenario) { dialog(it) == null }
                assertNull(care.concern(issue.id)!!.profileLink)
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
    @Test fun backgroundSelectionPagesBeyondTheFirstPageAndPersistsOnlyTheChosenEntry(): Unit = fixture { names, profile, care ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        repeat(31) { n -> profile.newEntry(HealthBackgroundKind.HISTORY).let {
            profile.saveEntry(it.copy(entry = it.entry.copy(name = "合成背景记录 $n")))
        } }
        val issue = care.forMetric(HealthMetric.GLUCOSE)!!
        var worker: ExecutorService? = null
        fun picker(activity: HealthCareActivity) = HealthCareProfileReview::class.java.getDeclaredField("picker")
            .apply { isAccessible = true }.get(review(activity)) as? AlertDialog
        var chosen = ""
        try {
            ActivityScenario.launch<HealthCareActivity>(Intent(context, HealthCareActivity::class.java)
                .putExtra("health_care_id", issue.id).putHealthNavigationFixture(names)).use { scenario ->
                await(scenario) { views(it.window.decorView).any { view -> view.tag == "health-care-profile" } }
                scenario.onActivity {
                    worker = HealthCareActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    review(it).show(issue.id)
                }
                await(scenario) { dialog(it)?.isShowing == true }
                scenario.onActivity { views(dialog(it)!!.window!!.decorView).first { view -> view.tag == "health-care-profile-background" }.performClick() }
                await(scenario) { picker(it)?.window?.decorView?.let { root -> views(root).any { view -> view.tag == "health-assistant-background-next" } } == true }
                scenario.onActivity {
                    val root = picker(it)!!.window!!.decorView
                    assertEquals(30, views(root).filterIsInstance<CheckBox>().size)
                    views(root).first { view -> view.tag == "health-assistant-background-next" }.performClick()
                }
                await(scenario) { picker(it)?.window?.decorView?.let { root -> views(root).filterIsInstance<CheckBox>().size == 1 } == true }
                scenario.onActivity {
                    val item = views(picker(it)!!.window!!.decorView).filterIsInstance<CheckBox>().single()
                    chosen = item.tag.toString().removePrefix("health-assistant-background-choice-")
                    item.performClick()
                    picker(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { picker(it)?.isShowing == false }
                scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
                await(scenario) { dialog(it) == null }
                assertEquals(setOf(chosen), care.concern(issue.id)!!.profileLink!!.scope.entries)
                assertEquals(31L, profile.count(HealthBackgroundKind.HISTORY))
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS) }
    }
}
