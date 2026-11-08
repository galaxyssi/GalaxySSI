package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareAgendaUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup)
        (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun await(scenario: ActivityScenario<HealthCareActionsActivity>, ready: (HealthCareActionsActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < deadline)
        fail("Action agenda did not reach its expected state")
    }
    private fun dialog(review: HealthCareActionReview) = HealthCareActionReview::class.java.getDeclaredField("dialog")
        .apply { isAccessible = true }.get(review) as? AlertDialog

    @Test fun actionReviewFiltersAndBackgroundKeepCanonicalResults() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            val initial = HealthCareFollowUpTestFixture.confirmed(context, names)
            val now = System.currentTimeMillis()
            val issue = HealthCareStore(context, names.care).use { care ->
                care.update(initial.id, initial.revision, "fixture_today") { it.copy(actions = it.actions.map { action ->
                    action.copy(dueFrom = now - 1000, dueUntil = now + 86400000)
                }) }
            }
            ActivityScenario.launch<HealthCareActionsActivity>(Intent(context, HealthCareActionsActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario ->
                fun hasActions(activity: HealthCareActionsActivity) = views(activity.window.decorView).any { it.tag == "health-agenda-action-${issue.actions.first().id}" }
                await(scenario, ::hasActions)
                lateinit var review: HealthCareActionReview
                scenario.onActivity {
                    worker = HealthCareActionsActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    review = (HealthCareActionsActivity::class.java.getDeclaredField("review\$delegate").apply { isAccessible = true }.get(it) as Lazy<*>).value as HealthCareActionReview
                }
                if (InstrumentationRegistry.getArguments().getString("health_agenda_screenshot") == "true") {
                    InstrumentationRegistry.getInstrumentation().waitForIdleSync(); SystemClock.sleep(600)
                    InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap -> try {
                        java.io.File(context.getExternalFilesDir(null), "health-action-agenda-fixture.png").outputStream().use {
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                        }
                    } finally { bitmap.recycle() } }
                }
                scenario.onActivity { views(it.window.decorView).first { v -> v.tag == "health-agenda-action-${issue.actions.first().id}" }.performClick() }
                await(scenario) { dialog(review)?.isShowing == true }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity {
                    assertNull(dialog(review))
                    assertFalse(views(it.window.decorView).any { v -> v.tag?.toString()?.startsWith("health-agenda-action-") == true })
                }
                scenario.moveToState(Lifecycle.State.RESUMED); await(scenario, ::hasActions)
                HealthCareStore(context, names.care).use { care ->
                    val latest = care.concern(issue.id)!!
                    care.finishAction(issue.id, latest.revision, issue.actions.first().id, "合成行动结果，非健康结论", now + 1000)
                }
                await(scenario) { !hasActions(it) && views(it.window.decorView).any { v -> v.tag == "health-agenda-filter-RECORDED" } }
                scenario.onActivity { views(it.window.decorView).first { v -> v.tag == "health-agenda-filter-RECORDED" }.performClick() }
                await(scenario, ::hasActions)
                scenario.recreate(); await(scenario, ::hasActions)
                scenario.onActivity {
                    worker = HealthCareActionsActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                    assertTrue(views(it.window.decorView).filterIsInstance<TextView>().any { v -> v.text == context.getString(R.string.health_agenda_recorded_note) ||
                        v.text.contains(context.getString(R.string.health_agenda_recorded_note)) })
                }
                HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
                await(scenario) { !hasActions(it) && views(it.window.decorView).filterIsInstance<TextView>().any { v -> v.text == context.getString(R.string.health_overview_permission) } }
            }
        } finally {
            worker?.awaitTermination(10, TimeUnit.SECONDS)
            listOf(names.care, names.records, names.privacy, names.reminders, names.profile).forEach(context::deleteDatabase)
        }
    }
}
