package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.RadioButton
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthRecordExportUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private fun unlocked() = assumeFalse("Visible export acceptance requires an unlocked device", instrumentation.targetContext.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    @Test fun configDefaultsToScopedCsvWithoutAnnotationsOrOriginalBytes() {
        unlocked(); ActivityScenario.launch(HealthRecordExportActivity::class.java).use { scenario -> scenario.onActivity { activity ->
            assertTrue(views(activity.window.decorView).filterIsInstance<RadioButton>().single { it.tag == "health-export-format-CSV" }.isChecked)
            assertFalse(views(activity.window.decorView).filterIsInstance<CheckBox>().single { it.tag == "health-export-annotations" }.isChecked)
            assertEquals(2, (activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
            assertTrue(views(activity.window.decorView).filterIsInstance<android.widget.TextView>().any { it.text.toString() == activity.getString(R.string.health_export_no_originals) })
        } }
    }
    @Test fun formatAndOptInSurviveRotationButBackgroundDropsDecryptedViews() {
        unlocked(); ActivityScenario.launch(HealthRecordExportActivity::class.java).use { scenario ->
            scenario.onActivity { activity -> views(activity.window.decorView).single { it.tag == "health-export-format-XLSX" }.performClick(); views(activity.window.decorView).single { it.tag == "health-export-annotations" }.performClick() }
            scenario.recreate(); scenario.onActivity { activity ->
                assertTrue((views(activity.window.decorView).single { it.tag == "health-export-format-XLSX" } as RadioButton).isChecked)
                assertTrue((views(activity.window.decorView).single { it.tag == "health-export-annotations" } as CheckBox).isChecked)
            }
            scenario.moveToState(Lifecycle.State.CREATED); scenario.onActivity { activity ->
                assertEquals(0, ((activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).getChildAt(1) as ViewGroup).childCount)
            }
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { activity -> assertNotNull(views(activity.window.decorView).singleOrNull { it.tag == "health-export-preview" }) }
        }
    }
    @Test fun dataHubSeparatesMeasurementOriginalAndHistoryRoutes() {
        unlocked(); ActivityScenario.launch(HealthDataFilesActivity::class.java).use { scenario -> scenario.onActivity { activity ->
            val labels = views(activity.window.decorView).filterIsInstance<android.widget.TextView>().map { it.text.toString() }
            for (resource in listOf(R.string.health_first_import_title, R.string.health_export_import_originals, R.string.health_export_records, R.string.health_original_library, R.string.health_export_history))
                assertTrue(labels.contains(activity.getString(resource)))
        } }
    }
    @Test fun confirmationBackReturnsToConfigurationInsteadOfUnrelatedHistory() {
        unlocked(); ActivityScenario.launch(HealthRecordExportActivity::class.java).use { scenario -> scenario.onActivity { activity ->
            HealthRecordExportActivity::class.java.getDeclaredField("mode").apply { isAccessible = true }.set(activity, "session")
            activity.onBackPressed()
            assertNotNull(views(activity.window.decorView).singleOrNull { it.tag == "health-export-preview" })
        } }
    }
    @Test fun historyPagingMetadataSurvivesRecreationWithoutSerializingRecords() {
        unlocked(); ActivityScenario.launch(HealthRecordExportActivity::class.java).use { scenario ->
            val cursor = 17L to java.util.UUID.randomUUID().toString()
            val field = HealthRecordExportActivity::class.java.getDeclaredField("historyCursor").apply { isAccessible = true }
            scenario.onActivity { field.set(it, cursor) }; scenario.recreate(); scenario.onActivity { assertEquals(cursor, field.get(it)) }
        }
    }
}
