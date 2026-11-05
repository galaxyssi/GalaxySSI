package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.Switch
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthImportRetentionPolicyDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun privacyDefaultPersistsAndImportOverrideAppliesOnlyOnce() = fixture { names ->
        val privacyIntent = Intent(context, HealthPrivacyActivity::class.java).putExtra("health_privacy_test_db", names.privacy)
        ActivityScenario.launch<HealthPrivacyActivity>(privacyIntent).use { scenario ->
            val tag = "health-privacy-RETAIN_IMPORT_ORIGINALS"
            await(scenario, tag)
            scenario.onActivity {
                val control = requireNotNull(it.window.decorView.findViewWithTag<Switch>(tag))
                assertTrue(control.isChecked)
                control.performClick()
                assertFalse(control.isChecked)
            }
            waitFor("retention policy persisted") { !policy(names).retainImportOriginals }
            scenario.recreate()
            await(scenario, tag) { !(it as Switch).isChecked && it.isEnabled }
        }
        assertFalse(policy(names).online)
        val centerIntent = Intent(context, HealthCenterActivity::class.java).putExtra("health_import_center", true)
            .putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthCenterActivity>(centerIntent).use { center ->
            val retention = "health-import-keep-original"
            await(center, retention) { !(it as Switch).isChecked }
            val first = importFile(center, names, "health-import-report", "report.pdf")
            assertFalse(first.keepOriginal)
            await(center, retention) { !(it as Switch).isChecked }
            center.onActivity {
                val control = it.window.decorView.findViewWithTag<Switch>(retention)
                control.performClick()
                assertTrue(control.isChecked)
            }
            center.recreate()
            await(center, retention) { (it as Switch).isChecked }
            val table = importFile(center, names, "health-import-table", "table.csv")
            assertTrue(table.keepOriginal)
            await(center, retention) { !(it as Switch).isChecked }
            assertFalse(policy(names).retainImportOriginals)
            val third = importFile(center, names, "health-import-report", "next.pdf")
            assertFalse(third.keepOriginal)
            HealthPrivacyStore(context, names.privacy).use {
                it.change(HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS, true, it.policy().version)
            }
            await(center, retention) { (it as Switch).isChecked }
            HealthOriginalStore(context, names.originals, names.originalRoot(context)).use {
                assertFalse(requireNotNull(it.job(first.id)).keepOriginal)
                assertTrue(requireNotNull(it.job(table.id)).keepOriginal)
            }
        }
    }

    @Test fun cameraLaunchResolvesThePolicyWithoutOpeningTheCamera() = fixture { names ->
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.RETAIN_IMPORT_ORIGINALS, false, it.policy().version)
        }
        val launched = AtomicReference<Intent>()
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.component?.className != HealthCameraActivity::class.java.name) return null
                launched.set(Intent(intent))
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            val intent = Intent(context, HealthCaptureActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("health_capture_entry", HealthCaptureEntry.CAMERA.name)
            ActivityScenario.launch<HealthCaptureActivity>(intent).use {
                waitFor("resolved camera intent") { launched.get()?.hasExtra(HEALTH_KEEP_ORIGINAL) == true }
                assertFalse(launched.get().getBooleanExtra(HEALTH_KEEP_ORIGINAL, true))
            }
        } finally { instrumentation.removeMonitor(monitor) }
    }

    private fun importFile(center: ActivityScenario<HealthCenterActivity>, names: HealthOverviewDatabases, tag: String, file: String): HealthImportJob {
        val uri = Uri.parse("content://health-retention.test/$file")
        val picker = instrumentation.addMonitor(IntentFilter(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); addDataType("*/*")
        }, Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(uri)), true)
        val capture = instrumentation.addMonitor(HealthCaptureActivity::class.java.name, null, false)
        try {
            await(center, tag)
            center.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(tag).performClick()) }
            val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(capture, 12_000) as? HealthCaptureActivity)
            try {
                var job: HealthImportJob? = null
                waitFor("isolated import job $file") {
                    HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
                        job = store.jobs().firstOrNull { it.sourceUri == uri.toString() }
                    }
                    job != null
                }
                return requireNotNull(job)
            } finally {
                instrumentation.runOnMainSync { child.finish() }
                instrumentation.waitForIdleSync()
            }
        } finally { instrumentation.removeMonitor(picker); instrumentation.removeMonitor(capture) }
    }

    private fun policy(names: HealthOverviewDatabases) = HealthPrivacyStore(context, names.privacy).use { it.policy() }
    private fun <A : Activity> await(scenario: ActivityScenario<A>, tag: String, ready: (View) -> Boolean = { true }) =
        waitFor(tag) {
            var found = false
            scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag)?.let(ready) == true }
            found
        }
    private fun waitFor(label: String, ready: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 12_000
        do {
            if (ready()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < end)
        fail("Missing $label")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse("Retention UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
}
