package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
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

class HealthAtlasRenalDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val cells = listOf("podocyte", "mesangial-cell", "proximal-tubular-cell", "distal-tubular-cell",
        "collecting-duct-principal-cell", "collecting-duct-intercalated-cell", "urothelial-cell").map { "cell-$it" }
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
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun Activity.open(id: String) {
        view(if (id.startsWith("cell-")) "atlas-tab-3" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id); view("atlas-entry-$id").performClick()
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
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-renal-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun catalogueConnectsNewSegmentsAndCellsWithoutMislabelingArtwork() {
        val atlas = HealthBodyAtlas.load(context)
        assertEquals(listOf("proximal-tubule", "nephron-loop", "distal-tubule"), atlas["renal-tubules"]!!.related)
        assertTrue(atlas.cells(atlas["proximal-tubule"]!!).any { it.id == "cell-proximal-tubular-cell" })
        assertTrue(atlas.cells(atlas["distal-tubule"]!!).any { it.id == "cell-distal-tubular-cell" })
        assertEquals(7, cells.map { atlas.mechanism(atlas[it]!!).stages }.toSet().size)
        for (id in cells) {
            assertEquals(id, atlas[id]!!.mechanism)
            assertEquals("cell", atlas.mechanism(atlas[id]!!).kind)
            assertNull(HealthAtlasPlates.forId(id))
        }
        assertEquals("nephron", HealthAtlasPlates.forId("glomerulus")!!.owner)
    }
    @Test fun nephronBitmapHasTransparentMarginAndMarkersOnVisibleStructures() {
        val plate = HealthAtlasPlates.forId("nephron")!!
        assertEquals(6, plate.markers.size)
        val bitmap = BitmapFactory.decodeResource(context.resources, plate.drawable)
        try {
            assertTrue(bitmap.width >= 1024 && bitmap.height >= 1024)
            assertTrue(Color.alpha(bitmap.getPixel(0, 0)) < 5)
            assertTrue(Color.alpha(bitmap.getPixel(bitmap.width - 1, bitmap.height - 1)) < 5)
            for (marker in plate.markers) assertTrue("Invisible ${marker.id}", Color.alpha(bitmap.getPixel(
                (marker.x * bitmap.width).toInt(), (marker.y * bitmap.height).toInt())) > 200)
        } finally { bitmap.recycle() }
    }
    @Test fun kidneyToNephronToCellNavigationRestoresItsOwnStage() = native { scenario ->
        scenario.onActivity {
            it.open("kidneys"); it.view("atlas-entry-nephron").performClick()
            it.view("atlas-hotspot-proximal-tubule").performClick()
            assertTrue(it.view("atlas-hotspot-proximal-tubule").isSelected)
            it.view("atlas-entry-cell-proximal-tubular-cell").performClick()
            assertNull(it.window.decorView.tagged("atlas-art-image"))
            it.view("atlas-tab-3").performClick(); it.view("atlas-process-stage-2").performClick()
            (it.view("atlas-physiology-reabsorbed") as SeekBar).progress = 50
        }
        scenario.recreate(); ready(scenario, "atlas-process-stage-2")
        scenario.onActivity {
            assertTrue(it.view("atlas-process-stage-2").isSelected)
            assertEquals(50, (it.view("atlas-physiology-reabsorbed") as SeekBar).progress)
            it.onBackPressed(); assertTrue(it.view("atlas-hotspot-proximal-tubule").isSelected)
            it.onBackPressed(); assertFalse(it.view("atlas-hotspot-proximal-tubule").isSelected)
            it.onBackPressed(); assertNotNull(it.view("atlas-hotspot-renal-cortex"))
        }
    }
    @Test fun balanceUpdatesLocallyAndRestoresWithResearchWithoutChangingOtherEntries() = native { scenario ->
        scenario.onActivity {
            it.open("nephron"); it.view("atlas-tab-3").performClick()
            (it.view("atlas-physiology-reabsorbed") as SeekBar).progress = 50
            (it.view("atlas-physiology-secreted") as SeekBar).progress = 30
            val balance = it.view("atlas-renal-balance") as HealthAtlasRenalBalanceView
            assertEquals(80.0, balance.amounts.excreted, 1e-9)
            assertTrue((it.view("atlas-renal-amount-1") as TextView).text.contains("50"))
            it.view("atlas-open-research").performClick()
        }
        scenario.recreate(); ready(scenario, "atlas-renal-balance")
        scenario.onActivity {
            assertEquals(80.0, (it.view("atlas-renal-balance") as HealthAtlasRenalBalanceView).amounts.excreted, 1e-9)
            it.view("atlas-research-tab-1").performClick()
            assertNull(it.window.decorView.tagged("atlas-renal-balance"))
            it.view("atlas-research-tab-0").performClick()
            it.view("atlas-physiology-reset").performClick()
            assertEquals(20.0, (it.view("atlas-renal-balance") as HealthAtlasRenalBalanceView).amounts.excreted, 1e-9)
            (it.view("atlas-physiology-filtered") as SeekBar).progress = 0
            (it.view("atlas-physiology-secreted") as SeekBar).progress = 0
            assertEquals(0.0, (it.view("atlas-renal-balance") as HealthAtlasRenalBalanceView).amounts.excreted, 0.0)
            it.onBackPressed(); it.onBackPressed(); it.open("distal-tubule"); it.view("atlas-tab-3").performClick()
            assertEquals(20.0, (it.view("atlas-renal-balance") as HealthAtlasRenalBalanceView).amounts.excreted, 1e-9)
        }
    }
    @Test fun labelsFitLargeTextAndNumericUpdatesChangePixels() = native { scenario ->
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
                val balance = HealthAtlasRenalBalanceView(activity); enlarge(balance)
                fun render(): Bitmap {
                    balance.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                    balance.layout(0, 0, width, balance.measuredHeight); fits(balance)
                    return Bitmap.createBitmap(width, balance.height, Bitmap.Config.ARGB_8888).also { balance.draw(Canvas(it)) }
                }
                val before = render(); balance.amounts = HealthAtlasRenal.amounts(0.0, 0.0, 0.0); val after = render()
                try { assertFalse(before.sameAs(after)) } finally { before.recycle(); after.recycle() }
                val data = HealthBodyAtlas.load(activity)
                var selected = ""
                val plate = HealthAtlasLabeledImage(activity, HealthAtlasPlates.forId("nephron")!!, "nephron", data, "nephron") { selected = it.id }
                enlarge(plate)
                plate.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                plate.layout(0, 0, width, plate.measuredHeight); fits(plate)
                plate.tagged("atlas-hotspot-nephron-loop")!!.performClick(); assertEquals("nephron-loop", selected)
            }
        }
    }
    @Test fun publicPromptsIncludeMassDirectionsAndOnlyTheSelectedCellMechanism() {
        val data = HealthBodyAtlas.load(context)
        val model = HealthAtlasPhysiology(HealthAtlasPhysiologyKind.RENAL_EXCRETION, listOf(150, 80, 20))
        val prompt = HealthAtlasAgentContext.prompt(context, data, data["cell-proximal-tubular-cell"], HealthAtlasSimulation(phase = .5f), model)
        assertTrue(prompt.contains(data.mechanism(data["cell-proximal-tubular-cell"]!!).stages[2]))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_renal_balance_reabsorbed, "120")))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_renal_lumen_blood)))
        assertTrue(prompt.contains(context.getString(R.string.health_atlas_renal_balance_scope)))
        val drugs = HealthAtlasAgentContext.prompt(context, data, data["nephron"], HealthAtlasSimulation(), model, HealthAtlasResearchTopic.DRUGS)
        assertFalse(drugs.contains(context.getString(R.string.health_atlas_renal_balance_scope)))
        val unrelated = HealthAtlasAgentContext.prompt(context, data, data["heart"], HealthAtlasSimulation(), model)
        assertFalse(unrelated.contains(context.getString(R.string.health_atlas_renal_balance_scope)))
    }
    @Test fun actualAgentConfirmationContainsTheVisibleBalanceAndCanBeCancelled() = native { scenario ->
        scenario.onActivity {
            it.open("nephron"); it.view("atlas-tab-3").performClick()
            (it.view("atlas-physiology-filtered") as SeekBar).progress = 150
            it.view("atlas-ask").performClick()
        }
        val expected = context.getString(R.string.health_atlas_renal_balance_filtered, "150")
        val root = activeWindow(expected)
        assertTrue(root.findAccessibilityNodeInfosByText(expected).isNotEmpty())
        assertTrue(root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel)).any {
            it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK)
        })
    }
    @Test fun structureFullscreenAndSimulationRenderWithPreservedSelection() = native { scenario ->
        scenario.onActivity { it.open("nephron") }; capture("structure")
        scenario.onActivity { it.view("atlas-fullscreen").performClick() }; capture("fullscreen")
        instrumentation.sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK); instrumentation.waitForIdleSync(); SystemClock.sleep(250)
        scenario.onActivity { it.view("atlas-tab-3").performClick() }; capture("balance")
        scenario.onActivity { it.onBackPressed(); it.open("cell-collecting-duct-intercalated-cell"); it.view("atlas-tab-1").performClick() }
        capture("cell-function")
    }
}
