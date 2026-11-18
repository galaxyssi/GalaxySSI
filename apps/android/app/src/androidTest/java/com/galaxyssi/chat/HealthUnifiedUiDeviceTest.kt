package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.Switch
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthUnifiedUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun intent(type: Class<*>, names: HealthOverviewDatabases) = Intent(context, type).putHealthNavigationFixture(names)
        .putExtra("health_profile_test_db", names.profile).putExtra("health_privacy_test_db", names.privacy)
        .putExtra("health_sources_test_id", names.fixture)
    private fun <A : Activity> await(screen: ActivityScenario<A>, condition: (A) -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            screen.onActivity { ready = condition(it) }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Unified health page did not become ready")
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(150)
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            File(context.getExternalFilesDir(null), "$name.png").outputStream().use {
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }; bitmap.recycle()
        }
    }
    @Test fun functionMenuIsAFlatAccessibleListWithoutDuplicateHomeOrClassifications() = fixture { names ->
        ActivityScenario.launch<HealthCenterActivity>(intent(HealthCenterActivity::class.java, names).putExtra("health_functions", true)).use { screen ->
            screen.onActivity { activity ->
                val list = views(activity.body).single { it.tag == "health-functions-list" } as ViewGroup
                assertEquals(14, list.childCount)
                val text = views(list).filterIsInstance<TextView>().map { it.text.toString() }
                listOf(R.string.health_title, R.string.health_management, R.string.health_profile_preferences).forEach {
                    assertFalse(text.contains(activity.getString(it)))
                }
                for (index in 0 until list.childCount) {
                    val row = list.getChildAt(index) as ViewGroup
                    assertTrue(row.isClickable); assertTrue(row.isFocusable)
                    assertTrue(row.minimumHeight >= activity.resources.displayMetrics.density * 48)
                    assertFalse(row.contentDescription.isNullOrBlank())
                    assertTrue(row.getChildAt(0) is ImageView)
                }
            }
            capture("health-unified-functions")
        }
    }
    @Test fun healthFeatureIconsUseDistinctReadableMedicalSymbols() = fixture { names ->
        ActivityScenario.launch<HealthCenterActivity>(intent(HealthCenterActivity::class.java, names).putExtra("health_functions", true)).use { screen ->
            screen.onActivity { activity ->
                val icons = listOf("health-care-entry" to R.drawable.ic_health_proactive,
                    "health-profile-entry" to R.drawable.ic_health_profile, "health-body-entry" to R.drawable.ic_health_body)
                val rendered = mutableListOf<android.graphics.Bitmap>()
                fun render(drawable: android.graphics.drawable.Drawable): android.graphics.Bitmap {
                    val bitmap = android.graphics.Bitmap.createBitmap(72, 72, android.graphics.Bitmap.Config.ARGB_8888)
                    drawable.setBounds(0, 0, 72, 72); drawable.draw(android.graphics.Canvas(bitmap)); return bitmap
                }
                try {
                    icons.forEach { (tag, resource) ->
                        val row = views(activity.body).single { it.tag == tag } as ViewGroup
                        val icon = row.getChildAt(0) as ImageView
                        val actual = render(icon.drawable.constantState!!.newDrawable(activity.resources).mutate())
                        rendered += actual
                        val expected = activity.getDrawable(resource)!!.mutate().apply { setTint(activity.getColor(R.color.health_overview_green)) }
                        val reference = render(expected)
                        try { assertTrue(tag, actual.sameAs(reference)) } finally { reference.recycle() }
                        val pixels = IntArray(72 * 72); actual.getPixels(pixels, 0, 72, 0, 0, 72, 72)
                        assertTrue(tag, pixels.count { android.graphics.Color.alpha(it) > 0 } > 100)
                    }
                    rendered.forEachIndexed { index, bitmap -> rendered.drop(index + 1).forEach { assertFalse(bitmap.sameAs(it)) } }
                } finally { rendered.forEach { it.recycle() } }
            }
        }
    }
    @Test fun everyMenuEntryOpensItsRealDestinationAndPreservesTheFixtureScope() = fixture { names ->
        val external = linkedMapOf(
            "health-care-entry" to HealthCareActivity::class.java, "health-agenda-entry" to HealthCareActionsActivity::class.java,
            "health-originals-entry" to HealthOriginalLibraryActivity::class.java, "health-catalog-entry" to HealthCatalogActivity::class.java,
            "health-weekly-entry" to HealthWeeklyActivity::class.java, "health-assistant-entry" to HealthAssistantActivity::class.java,
            "health-sources-entry" to HealthSourcesActivity::class.java, "health-data-files-entry" to HealthDataFilesActivity::class.java,
            "health-profile-entry" to HealthProfileActivity::class.java, "health-privacy-entry" to HealthPrivacyActivity::class.java,
            "health-body-entry" to HealthBodyExplorationActivity::class.java)
        ActivityScenario.launch<HealthCenterActivity>(intent(HealthCenterActivity::class.java, names).putExtra("health_functions", true)).use { screen ->
            external.forEach { (tag, destination) ->
                val launched = AtomicReference<Intent>()
                val monitor = object : Instrumentation.ActivityMonitor() {
                    override fun onStartActivity(request: Intent): Instrumentation.ActivityResult? {
                        launched.set(Intent(request)); return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
                    }
                }
                instrumentation.addMonitor(monitor)
                try {
                    screen.onActivity { views(it.body).single { view -> view.tag == tag }.performClick() }
                    val target = requireNotNull(launched.get())
                    assertEquals(destination.name, target.component?.className)
                    assertEquals(names.fixture, target.getStringExtra("health_overview_test_id"))
                    if (destination == HealthProfileActivity::class.java) assertEquals(names.profile, target.getStringExtra("health_profile_test_db"))
                    if (destination == HealthPrivacyActivity::class.java) assertEquals(names.privacy, target.getStringExtra("health_privacy_test_db"))
                } finally { instrumentation.removeMonitor(monitor) }
            }
            listOf("health-functions-record-center" to R.string.health_record_center, "health-manual-entry" to R.string.health_manual,
                "health-records-entry" to R.string.health_records).forEach { (tag, title) ->
                screen.onActivity { activity ->
                    views(activity.body).single { it.tag == tag }.performClick()
                    assertEquals(activity.getString(title), (views(activity.window.decorView).single { it.tag == "health-page-title" } as TextView).text.toString())
                    activity.onBackPressed()
                    assertTrue(views(activity.body).any { it.tag == "health-functions-list" })
                }
            }
        }
    }
    @Test fun allHealthActivitiesUseTheSameThemeAndBothModesHaveReadablePrimaryActions() {
        @Suppress("DEPRECATION")
        val pages = context.packageManager.getPackageInfo(context.packageName, PackageManager.GET_ACTIVITIES).activities.orEmpty()
            .filter { it.name.startsWith("${context.packageName}.Health") }
        assertTrue(pages.size >= 37)
        pages.forEach { assertEquals(it.name, R.style.Theme_GalaxySSI_Health, it.themeResource) }
        listOf(Configuration.UI_MODE_NIGHT_NO, Configuration.UI_MODE_NIGHT_YES).forEach { night ->
            val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
                uiMode = uiMode and Configuration.UI_MODE_NIGHT_MASK.inv() or night
            }).resources
            val fill = resources.getColor(R.color.health_overview_green, null)
            val text = resources.getColor(R.color.health_action_text, null)
            assertTrue(ColorUtils.calculateContrast(text, fill) >= 4.5)
        }
    }
    @Test fun eachFeaturePageHasTheSameCenteredHeaderAndReturnsWithoutLosingItsPage() = fixture { names ->
        val pages = listOf(HealthCareActivity::class.java, HealthCareActionsActivity::class.java, HealthOriginalLibraryActivity::class.java,
            HealthCatalogActivity::class.java, HealthWeeklyActivity::class.java, HealthAssistantActivity::class.java,
            HealthSourcesActivity::class.java, HealthDataFilesActivity::class.java, HealthProfileActivity::class.java,
            HealthPrivacyActivity::class.java, HealthBodyExplorationActivity::class.java)
        pages.forEach { type ->
            val workers = mutableListOf<ExecutorService>()
            ActivityScenario.launch<Activity>(intent(type, names)).use { screen ->
                instrumentation.waitForIdleSync(); SystemClock.sleep(100)
                screen.onActivity { activity ->
                    val toolbar = views(activity.window.decorView).single { it.tag == "health-page-toolbar" } as ViewGroup
                    val title = toolbar.getChildAt(1) as TextView
                    assertEquals(3, toolbar.childCount); assertEquals(1, title.maxLines)
                    val position = IntArray(2); val heading = IntArray(2)
                    toolbar.getLocationOnScreen(position); title.getLocationOnScreen(heading)
                    assertTrue(toolbar.width > 0)
                    assertTrue(kotlin.math.abs(position[0] + toolbar.width / 2 - heading[0] - title.width / 2) <= 1)
                    assertTrue(toolbar.getChildAt(0).isClickable); assertTrue(toolbar.getChildAt(2).isClickable)
                    activity.javaClass.declaredFields.filter { ExecutorService::class.java.isAssignableFrom(it.type) }.forEach {
                        it.isAccessible = true; (it.get(activity) as? ExecutorService)?.let(workers::add)
                    }
                }
                if (type == HealthProfileActivity::class.java) capture("health-unified-profile")
                if (type == HealthPrivacyActivity::class.java) capture("health-unified-privacy")
                screen.moveToState(Lifecycle.State.CREATED)
                screen.moveToState(Lifecycle.State.RESUMED)
                screen.onActivity { assertTrue(views(it.window.decorView).any { view -> view.tag == "health-page-toolbar" }) }
            }
            workers.forEach { it.awaitTermination(10, TimeUnit.SECONDS) }
        }
    }
    @Test fun profileEditingAndPrivacySwitchesStillPersistWithTheSharedControls() = fixture { names ->
        ActivityScenario.launch<HealthProfileActivity>(intent(HealthProfileActivity::class.java, names)).use { screen ->
            await(screen) { views(it.window.decorView).any { view -> view.tag == "health-profile-field-NAME" } }
            screen.onActivity { activity ->
                views(activity.window.decorView).single { it.tag == "health-profile-field-NAME" }.performClick()
            }
            instrumentation.waitForIdleSync()
            // Existing profile tests exercise commit/cancel; here verify the themed editor remains native.
            screen.onActivity { activity ->
                val dialog = HealthProfileActivity::class.java.getDeclaredField("dialog").apply { isAccessible = true }
                    .get(activity) as android.app.AlertDialog
                assertTrue(views(requireNotNull(dialog.window).decorView).filterIsInstance<EditText>().any { !it.isSaveEnabled })
            }
        }
        ActivityScenario.launch<HealthPrivacyActivity>(intent(HealthPrivacyActivity::class.java, names)).use { screen ->
            await(screen) { views(it.window.decorView).any { view -> view.tag == "health-privacy-ONLINE_ANALYSIS" } }
            screen.onActivity { activity ->
                val online = views(activity.window.decorView).single { it.tag == "health-privacy-ONLINE_ANALYSIS" } as Switch
                assertFalse(online.isChecked)
                (views(activity.window.decorView).single { it.tag == "health-privacy-CONFIRMED_METRICS" } as Switch).performClick()
            }
            await(screen) { (views(it.window.decorView).singleOrNull { view -> view.tag == "health-privacy-CONFIRMED_METRICS" } as? Switch)?.let { view -> view.isEnabled && !view.isChecked } == true }
            HealthPrivacyStore(context, names.privacy).use { assertFalse(it.policy().metrics); assertFalse(it.policy().online) }
        }
    }
}
