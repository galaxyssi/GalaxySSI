package com.galaxyssi.chat

import android.view.View
import android.view.ViewGroup
import android.content.Intent
import android.os.SystemClock
import android.widget.CheckBox
import android.widget.RadioButton
import android.widget.TextView
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
            assertFalse((activity.window.decorView.findViewWithTag<View>("health-export-camera-originals") as CheckBox).isChecked)
            assertFalse((activity.window.decorView.findViewWithTag<View>("health-export-uploaded-originals") as CheckBox).isChecked)
            assertEquals(2, (activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0) as ViewGroup).childCount)
            assertTrue(views(activity.window.decorView).filterIsInstance<android.widget.TextView>().any { it.text.toString() == activity.getString(R.string.health_export_no_originals) })
        } }
    }
    @Test fun photoAndUploadChoicesToggleZipIndependentlyAndSurviveRecreation() {
        unlocked(); ActivityScenario.launch(HealthRecordExportActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.window.decorView.findViewWithTag<View>("health-export-camera-originals").performClick()
                assertEquals(activity.getString(R.string.health_export_bundle_packaging),
                    activity.window.decorView.findViewWithTag<TextView>("health-export-packaging").text)
            }
            scenario.recreate()
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                val camera = root.findViewWithTag<CheckBox>("health-export-camera-originals")
                val uploaded = root.findViewWithTag<CheckBox>("health-export-uploaded-originals")
                assertTrue(camera.isChecked); assertFalse(uploaded.isChecked)
                uploaded.performClick()
                camera.performClick()
                assertEquals(activity.getString(R.string.health_export_bundle_packaging), root.findViewWithTag<TextView>("health-export-packaging").text)
                uploaded.performClick()
                assertEquals(activity.getString(R.string.health_export_no_originals), root.findViewWithTag<TextView>("health-export-packaging").text)
            }
        }
    }

    @Test fun nativeConfirmationListsFrozenOriginalsAndMissingSourcesBeforeConsent() {
        unlocked()
        val context = instrumentation.targetContext
        val token = java.util.UUID.randomUUID().toString()
        val db = "health-record-export-test-$token.db"
        val root = java.io.File(context.cacheDir, "health-record-export-test-$token")
        val sources = HealthOverviewDatabases(token)
        try {
            val session = HealthRecordExportStore(context, db, root).use { exports ->
                HealthRecordStore(context, sources.records).use { records ->
                    HealthOriginalStore(context, sources.originals, sources.originalRoot(context)).use { originals ->
                        val time = System.currentTimeMillis() - 60_000
                        listOf("synthetic-camera.jpg", "synthetic-missing.jpg").forEachIndexed { index, name ->
                            val file = originals.importOriginal(java.util.UUID.randomUUID().toString(), name.byteInputStream(), name, "image/jpeg", "camera")
                            val result = records.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to (50 + index).toString()), "kg", time + index,
                                evidence = HealthEvidence(file.id, file.id, "fixture", file.sha256, 1, "", confirmed = true)))
                            assertTrue(result is HealthSaveResult.Saved)
                            if (index == 1) assertTrue(originals.removeOriginalBytes(file))
                        }
                        val requested = exports.create(HealthRecordExportScope(cameraOriginals = true))
                        assertEquals(HealthOriginalArchiveOutcome.COMPLETE, HealthRecordExportPipeline.prepare(records, originals, exports, requested.id, requested.dispatch))
                        exports.session(requested.id)!!
                    }
                }
            }
            assertEquals(HealthRecordExportState.REVIEW, session.state)
            val intent = Intent(context, HealthRecordExportActivity::class.java).putExtra("record_export", session.id)
                .putExtra("health_record_export_test_id", token)
            ActivityScenario.launch<HealthRecordExportActivity>(intent).use { scenario ->
                fun await(predicate: (View) -> Boolean) {
                    val deadline = SystemClock.elapsedRealtime() + 10_000
                    do {
                        var matches = false
                        scenario.onActivity { matches = predicate(it.window.decorView) }
                        if (matches) return
                        SystemClock.sleep(50)
                    } while (SystemClock.elapsedRealtime() < deadline)
                    fail("Native export confirmation did not render")
                }
                await { it.findViewWithTag<View>("health-export-manifest") != null }
                scenario.onActivity { activity ->
                    val decor = activity.window.decorView
                    assertFalse(decor.findViewWithTag<CheckBox>("health-record-export-consent").isChecked)
                    decor.findViewWithTag<View>("health-export-manifest").performClick()
                }
                fun hasManifest(decor: View) = views(decor).filterIsInstance<TextView>().map { it.text.toString() }.let { texts ->
                    texts.any { it.startsWith("synthetic-camera.jpg") } &&
                        texts.any { it.endsWith(context.getString(R.string.health_export_attachment_missing)) }
                }
                await(::hasManifest)
                scenario.recreate()
                await(::hasManifest)
            }
        } finally {
            context.deleteDatabase(db); root.deleteRecursively()
            clearHealthOverviewFixture(context, sources)
        }
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
