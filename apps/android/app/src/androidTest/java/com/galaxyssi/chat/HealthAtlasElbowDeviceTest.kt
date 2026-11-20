package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.SeekBar
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthAtlasElbowDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val kind = HealthAtlasPhysiologyKind.ELBOW_BALANCE
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue(key, found)
    }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        instrumentation.uiAutomation
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view("atlas-tab-1").performClick()
        (view("atlas-search") as EditText).setText(id); view("atlas-entry-$id").performClick()
        view("atlas-tab-3").performClick()
    }
    private fun activeWindow(text: String? = null): android.view.accessibility.AccessibilityNodeInfo {
        instrumentation.waitForIdleSync()
        val deadline = SystemClock.elapsedRealtime() + 5000
        while (SystemClock.elapsedRealtime() < deadline) {
            val root = instrumentation.uiAutomation.rootInActiveWindow
            if (root?.packageName?.toString() == context.packageName &&
                (text == null || root.findAccessibilityNodeInfosByText(text).isNotEmpty())) return root
            SystemClock.sleep(50)
        }
        error("Atlas window did not become accessible")
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(250); activeWindow()
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-elbow-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }

    @Test fun parameterChangeRetainsPageAndUpdatesForceDiagramLocally() = native { scenario ->
        scenario.onActivity {
            it.open("muscle")
            val scroll = it.view("atlas-scroll"); val ask = it.view("atlas-ask")
            val balance = it.view("atlas-elbow-balance") as HealthAtlasElbowView
            assertEquals(470.4, balance.forces.muscle, 1e-9)
            (it.view("atlas-physiology-elbow-load") as SeekBar).progress = 0
            assertSame(scroll, it.view("atlas-scroll")); assertSame(ask, it.view("atlas-ask"))
            assertSame(balance, it.view("atlas-elbow-balance"))
            assertEquals(98.0, balance.forces.muscle, 1e-9)
            assertEquals("98 N", (it.view("atlas-physiology-output") as TextView).text.toString())
            it.view("atlas-physiology-reset").performClick()
            assertEquals(470.4, balance.forces.muscle, 1e-9)
        }
    }
    @Test fun parametersSurviveRecreationAndStayIndependentBetweenEntries() = native { scenario ->
        scenario.onActivity {
            it.open("muscle"); (it.view("atlas-physiology-elbow-load") as SeekBar).progress = 70
            (it.view("atlas-physiology-elbow-muscle-arm") as SeekBar).progress = 10
        }
        scenario.recreate(); ready(scenario, "atlas-elbow-balance")
        scenario.onActivity {
            assertEquals(70, (it.view("atlas-physiology-elbow-load") as SeekBar).progress)
            assertEquals(10, (it.view("atlas-physiology-elbow-muscle-arm") as SeekBar).progress)
            it.view("atlas-tab-0").performClick(); it.view("atlas-tab-3").performClick()
            assertEquals(70, (it.view("atlas-physiology-elbow-load") as SeekBar).progress)
            it.onBackPressed(); it.open("skeletal")
            assertEquals(40, (it.view("atlas-physiology-elbow-load") as SeekBar).progress)
            it.onBackPressed(); it.open("muscle")
            assertEquals(70, (it.view("atlas-physiology-elbow-load") as SeekBar).progress)
        }
    }
    @Test fun localizedPublicPromptsIncludeAssumptionsButDoNotLeakToOtherTopics() {
        for (locale in listOf(java.util.Locale.ENGLISH, java.util.Locale.SIMPLIFIED_CHINESE)) {
            val localized = context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocale(locale) })
            val atlas = HealthBodyAtlas.load(localized)
            val model = HealthAtlasPhysiology(kind).withInput(0, 0)
            for (id in listOf("skeletal", "muscle", "biceps-brachii", "humerus", "radius", "ulna")) {
                val prompt = HealthAtlasAgentContext.prompt(localized, atlas, atlas[id], quantitative = model)
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_elbow_muscle_force, "98")))
                assertTrue(prompt.contains(localized.getString(R.string.health_atlas_elbow_scope)))
                assertTrue(prompt.contains(kind.source))
            }
            for (topic in listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING))
                assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas["muscle"], quantitative = model, topic = topic)
                    .contains(localized.getString(R.string.health_atlas_elbow_scope)))
            assertFalse(HealthAtlasAgentContext.prompt(localized, atlas, atlas["cell-skeletal-myocyte"], quantitative = model)
                .contains(localized.getString(R.string.health_atlas_elbow_scope)))
        }
    }
    @Test fun diagramRendersNonblankUpdatesAndLargeLabelsFit() = native { scenario ->
        scenario.onActivity { activity ->
            fun enlarge(view: View) {
                if (view is TextView) view.textSize = 26f
                if (view is ViewGroup) for (i in 0 until view.childCount) enlarge(view.getChildAt(i))
            }
            fun fits(view: View) {
                if (view is TextView) assertTrue(view.height >= view.layout.height + view.compoundPaddingTop + view.compoundPaddingBottom)
                if (view is ViewGroup) for (i in 0 until view.childCount) {
                    val child = view.getChildAt(i)
                    assertTrue(child.left >= 0 && child.top >= 0 && child.right <= view.width && child.bottom <= view.height)
                    fits(child)
                }
            }
            for (width in listOf(720, 1080, 1600)) {
                val balance = HealthAtlasElbowView(activity); enlarge(balance)
                fun draw(): Bitmap {
                    balance.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                        View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    balance.layout(0, 0, width, balance.measuredHeight); fits(balance)
                    val diagram = balance.tagged("atlas-elbow-diagram")!!
                    return Bitmap.createBitmap(width, diagram.height, Bitmap.Config.ARGB_8888).also { diagram.draw(Canvas(it)) }
                }
                val before = draw(); balance.forces = HealthAtlasElbow.forces(0.0, 20.0, 60.0); val after = draw()
                try {
                    assertFalse(before.sameAs(after))
                    val pixels = IntArray(after.width * after.height); after.getPixels(pixels, 0, after.width, 0, 0, after.width, after.height)
                    assertTrue(pixels.count { android.graphics.Color.alpha(it) > 0 } > 1000)
                    assertTrue(balance.tagged("atlas-elbow-diagram")!!.contentDescription.contains(HealthAtlasPhysiologyText.number(balance.forces.muscle)))
                } finally { before.recycle(); after.recycle() }
            }
        }
    }
    @Test fun actualAgentPreviewHasCurrentForceAndCanBeCancelled() = native { scenario ->
        scenario.onActivity {
            it.open("muscle"); (it.view("atlas-physiology-elbow-load") as SeekBar).progress = 0
            it.view("atlas-ask").performClick()
        }
        val root = activeWindow(context.getString(R.string.health_atlas_elbow_muscle_force, "98"))
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
        instrumentation.waitForIdleSync()
        scenario.onActivity { assertNotNull(it.view("atlas-elbow-balance")) }
    }
    @Test fun nativeSimulationAndControlsAreVisibleOnDevice() = native { scenario ->
        scenario.onActivity { it.open("muscle") }; capture("forces")
        scenario.onActivity {
            val target = it.view("atlas-physiology-elbow-load")
            target.requestRectangleOnScreen(android.graphics.Rect(0, 0, target.width, target.height), true)
        }
        capture("controls")
        scenario.onActivity {
            (it.view("atlas-physiology-elbow-load") as SeekBar).progress = 80
            val chart = it.view("atlas-physiology-chart")
            chart.requestRectangleOnScreen(android.graphics.Rect(0, 0, chart.width, chart.height), true)
        }
        capture("curve")
    }
}
