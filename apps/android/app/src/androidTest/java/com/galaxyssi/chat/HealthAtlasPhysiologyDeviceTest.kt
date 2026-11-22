package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
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

class HealthAtlasPhysiologyDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun View.tagged(key: String): View? = if (tag == key) this else if (this is ViewGroup)
        (0 until childCount).firstNotNullOfOrNull { getChildAt(it).tagged(key) } else null
    private fun Activity.view(key: String) = requireNotNull(window.decorView.tagged(key)) { key }
    private fun native(block: (ActivityScenario<HealthBodyAtlasActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(java.util.UUID.randomUUID().toString())
        try {
            ActivityScenario.launch<HealthBodyAtlasActivity>(Intent(context, HealthBodyAtlasActivity::class.java)
                .putHealthNavigationFixture(names)).use { scenario -> ready(scenario, "atlas-whole-art"); block(scenario) }
        } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun ready(scenario: ActivityScenario<HealthBodyAtlasActivity>, key: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        var found = false
        while (!found && SystemClock.elapsedRealtime() < deadline) {
            scenario.onActivity { found = it.window.decorView.tagged(key) != null }
            if (!found) SystemClock.sleep(40)
        }
        assertTrue("Missing $key", found)
    }
    private fun Activity.open(id: String, cell: Boolean = false) {
        view(if (cell) "atlas-tab-3" else "atlas-tab-2").performClick()
        (view("atlas-search") as EditText).setText(id)
        view("atlas-entry-$id").performClick(); view("atlas-tab-3").performClick()
    }
    private fun capture(name: String) {
        instrumentation.waitForIdleSync(); SystemClock.sleep(180)
        val bitmap = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { java.io.File(context.getExternalFilesDir(null), "body-atlas-physiology-$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        } } finally { bitmap.recycle() }
    }
    @Test fun modelsUpdateAndRestorePerEntityWithoutCrossSelectionLeakage() = native { scenario ->
        scenario.onActivity {
            it.open("kidneys")
            (it.view("atlas-physiology-reabsorbed") as SeekBar).progress = 75
            assertTrue((it.view("atlas-physiology-output") as TextView).text.contains("35"))
            it.view("atlas-tab-1").performClick(); it.view("atlas-open-research").performClick()
            assertEquals(75, (it.view("atlas-physiology-reabsorbed") as SeekBar).progress)
        }
        scenario.recreate(); ready(scenario, "atlas-physiology-output")
        scenario.onActivity {
            assertEquals(75, (it.view("atlas-physiology-reabsorbed") as SeekBar).progress)
            it.onBackPressed(); it.onBackPressed(); it.open("lungs")
            assertEquals(150, (it.view("atlas-physiology-dead-space") as SeekBar).progress)
            (it.view("atlas-physiology-dead-space") as SeekBar).progress = 200
            assertTrue((it.view("atlas-physiology-output") as TextView).text.contains("3.6"))
            it.onBackPressed(); it.open("kidneys")
            assertEquals(75, (it.view("atlas-physiology-reabsorbed") as SeekBar).progress)
            it.view("atlas-physiology-reset").performClick()
            assertEquals(90, (it.view("atlas-physiology-reabsorbed") as SeekBar).progress)
            assertTrue((it.view("atlas-physiology-output") as TextView).text.contains("20"))
        }
    }
    @Test fun publicAgentPreviewCarriesCurrentNumbersLimitsAndSource() = native { scenario ->
        scenario.onActivity {
            it.open("cell-neuron", cell = true)
            (it.view("atlas-physiology-outside") as SeekBar).progress = 70
            it.view("atlas-ask").performClick()
        }
        instrumentation.waitForIdleSync()
        val expected = HealthAtlasPhysiologyText.context(context,
            HealthAtlasPhysiology(HealthAtlasPhysiologyKind.POTASSIUM).withInput(0, 80))
        val root = requireNotNull(instrumentation.uiAutomation.rootInActiveWindow)
        val messages = root.findAccessibilityNodeInfosByText(HealthAtlasPhysiologyKind.POTASSIUM.source)
        assertTrue(messages.any { it.text?.contains(expected) == true })
        val cancel = root.findAccessibilityNodeInfosByText(context.getString(android.R.string.cancel))
        assertTrue(cancel.any { it.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK) })
        instrumentation.waitForIdleSync()
        scenario.onActivity { assertNotNull(it.view("atlas-physiology-output")) }
    }
    @Test fun parameterCurvesChangePixelsAndExposeNumericalAccessibilityText() = native { scenario ->
        scenario.onActivity { activity ->
            for (kind in HealthAtlasPhysiologyKind.entries) {
                val chart = HealthAtlasPhysiologyChart(activity, HealthAtlasPhysiology(kind))
                chart.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                chart.layout(0, 0, chart.measuredWidth, chart.measuredHeight)
                fun draw() = Bitmap.createBitmap(chart.width, chart.height, Bitmap.Config.ARGB_8888).also { chart.draw(Canvas(it)) }
                val before = draw(); chart.model = chart.model.withInput(0, kind.inputs[0].range.last); val after = draw()
                try {
                    assertFalse("Unchanged curve: $kind", before.sameAs(after))
                    assertTrue(chart.contentDescription.contains(HealthAtlasPhysiologyText.resultNumber(chart.model, chart.model.result)))
                    val pixels = IntArray(chart.width * chart.height); after.getPixels(pixels, 0, chart.width, 0, 0, chart.width, chart.height)
                    assertTrue(pixels.count { android.graphics.Color.alpha(it) > 0 } > 1000)
                } finally { before.recycle(); after.recycle() }
            }
        }
    }
    @Test fun modelControlsRemainReadableAtLargeTextAndSourcesUseTheSelectedModel() = native { scenario ->
        scenario.onActivity { activity ->
            for (kind in HealthAtlasPhysiologyKind.entries) {
                val body = HealthCenterViews(activity).column()
                var opened = ""
                HealthAtlasPhysiologyPanel(activity, body, kind, null) { opened = it }
                for (i in 0 until body.childCount) (body.getChildAt(i) as? TextView)?.textSize = 26f
                body.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                body.layout(0, 0, body.measuredWidth, body.measuredHeight)
                for (i in 0 until body.childCount) {
                    val child = body.getChildAt(i)
                    assertTrue(child.right <= body.width && child.left >= 0)
                    if (child is TextView) assertTrue(child.height >= child.layout.height + child.compoundPaddingTop + child.compoundPaddingBottom)
                }
                assertEquals(HealthCenterViews(activity).dp(48), body.tagged("atlas-physiology-reset")!!.width)
                body.tagged("atlas-physiology-source")!!.performClick(); assertEquals(kind.source, opened)
            }
        }
    }
    @Test fun everyQuantitativeMappingUsesAnExistingCanonicalEntry() {
        val atlas = HealthBodyAtlas.load(context)
        val mapped = atlas.items.mapNotNull { item -> HealthAtlasPhysiologyKind.forItem(item.id)?.let { item.id to it } }
        val teaching = HealthAtlasPhysiologyKind.entries.filter { it.teaching != null }
        assertEquals(67 + teaching.sumOf { requireNotNull(it.teaching).entryIds.size }, mapped.size)
        teaching.forEach { kind ->
            assertEquals(requireNotNull(kind.teaching).entryIds,
                mapped.filter { it.second == kind }.map { it.first }.toSet())
        }
        assertEquals(HealthAtlasPhysiologyKind.entries.toSet(), mapped.map { it.second }.toSet())
        assertEquals(setOf("ventricles", "left-ventricle", "right-ventricle"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.VENTRICULAR_EJECTION }.map { it.first }.toSet())
        assertEquals(setOf("peripheral-nerves", "spinal-nerves", "cranial-nerves"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.NERVE_TRANSIT }.map { it.first }.toSet())
        assertEquals(listOf("cell-type-ii-pneumocyte"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE }.map { it.first })
        assertEquals(setOf("pancreas", "pancreatic-duct", "cell-pancreatic-ductal-cell"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.BICARBONATE_MIX }.map { it.first }.toSet())
        assertEquals(listOf("thyroid-gland"), mapped.filter { it.second == HealthAtlasPhysiologyKind.THYROID_FEEDBACK }.map { it.first })
        assertEquals(listOf("cell-rod-photoreceptor"), mapped.filter { it.second == HealthAtlasPhysiologyKind.PHOTON_CAPTURE }.map { it.first })
        assertEquals(listOf("sweat-glands"), mapped.filter { it.second == HealthAtlasPhysiologyKind.SWEAT_EVAPORATION }.map { it.first })
        assertEquals(listOf("lymphatic-vessels"), mapped.filter { it.second == HealthAtlasPhysiologyKind.LYMPH_VALVE }.map { it.first })
        assertEquals(setOf("small-intestine", "jejunum"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.VILLUS_AREA }.map { it.first }.toSet())
        assertEquals(setOf("respiratory-membrane", "pulmonary-capillaries", "tissue-alveolar-epithelium", "cell-type-i-pneumocyte"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION }.map { it.first }.toSet())
        assertEquals(setOf("cartilage", "tissue-hyaline-cartilage", "cell-chondrocyte"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION }.map { it.first }.toSet())
        assertEquals(setOf("limb-bones", "femur", "tibia", "fibula"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.BONE_BENDING }.map { it.first }.toSet())
        assertEquals(setOf("soleus", "gastrocnemius"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.CALF_PUMP }.map { it.first }.toSet())
        assertEquals(listOf("pelvis"), mapped.filter { it.second == HealthAtlasPhysiologyKind.PELVIC_SUPPORT }.map { it.first })
        assertEquals(listOf("subcutaneous-tissue"),
            mapped.filter { it.second == HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE }.map { it.first })
        mapped.forEach { (id, kind) ->
            val model = requireNotNull(HealthAtlasPhysiology.restore(id, kind.inputs.map { it.initial }.toIntArray()))
            assertTrue(HealthAtlasPhysiologyText.context(context, model).length < 3000)
        }
    }

    @Test fun allSystemPagesOpenAQuantitativeModelWithoutRemovingTheirSimulation() = native { scenario ->
        val systems = HealthBodyAtlas.load(context).systems
        assertEquals(14, systems.size)
        scenario.onActivity { activity ->
            for (system in systems) {
                activity.view("atlas-tab-1").performClick()
                (activity.view("atlas-search") as EditText).setText(system.id)
                activity.view("atlas-entry-${system.id}").performClick()
                activity.view("atlas-tab-3").performClick()
                val curve = activity.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart
                assertEquals(system.id, requireNotNull(HealthAtlasPhysiologyKind.forItem(system.id)), curve.model.kind)
                assertNotNull(activity.view("atlas-simulation-play"))
                if (system.id == "cardio") assertNotNull(activity.view("atlas-simulation-output"))
                activity.onBackPressed()
            }
        }
    }

    @Test fun capillaryExchangeInputsStayLocalWhenMovingBetweenTissueAndCell() = native { scenario ->
        val kind = HealthAtlasPhysiologyKind.CAPILLARY_EXCHANGE
        val key = "atlas-physiology-capillary-exchange-ps"
        val baseline = HealthAtlasPhysiology(kind)
        val changed = baseline.withInput(0, 35)
        scenario.onActivity {
            it.open("capillaries")
            val slider = it.view(key) as SeekBar
            assertEquals(20, slider.progress)
            slider.progress = 35
            assertEquals(changed, (it.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart).model)
            assertEquals(HealthAtlasPhysiologyText.companion(it, changed),
                (it.view("atlas-physiology-companion") as TextView).text.toString())
        }
        scenario.recreate(); ready(scenario, key)
        scenario.onActivity {
            assertEquals(changed, (it.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart).model)
        }
        capture("capillary-exchange")
        scenario.onActivity {
            it.onBackPressed()
            it.open("cell-vascular-endothelial-cell", cell = true)
            assertEquals(baseline, (it.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart).model)
            it.onBackPressed()
            it.open("capillaries")
            assertEquals(35, (it.view(key) as SeekBar).progress)
            it.view("atlas-physiology-reset").performClick()
            assertEquals(baseline, (it.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart).model)
        }
    }
    @Test fun newMaterialDiagramsShowChangesAndRestoreSyntheticInputs() = native { scenario ->
        val examples = listOf(
            Triple("respiratory-membrane", "diffusion-layer", "diffusion-gradient"),
            Triple("cartilage", "cartilage-compression", "cartilage-stress"),
            Triple("limb-bones", "bone-bending", "bone-moment"),
            Triple("soleus", "calf-pump", "calf-stroke"),
            Triple("pelvis", "pelvic-support", "pelvis-load"),
            Triple("subcutaneous-tissue", "cushion-contact", "cushion-load"),
            Triple("diaphragm", "diaphragm-displacement", "diaphragm-descent"),
            Triple("aorta", "arterial-continuity", "arterial-lumen-diameter"),
            Triple("nasal-cavity", "airway-cilia-track", "airway-ciliary-clearance-cycles"),
            Triple("cornea", "corneal-rays", "corneal-refraction-incident-angle"),
        )
        for ((id, art, input) in examples) {
            var initial = 0
            scenario.onActivity { activity ->
                activity.open(id)
                val seek = activity.view("atlas-physiology-$input") as SeekBar
                initial = seek.progress
                val diagram = activity.view("atlas-$art")
                diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
                fun draw() = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888).also { diagram.draw(Canvas(it)) }
                val before = draw()
                seek.progress = 0
                val after = draw()
                try {
                    assertFalse("$id illustration did not respond", before.sameAs(after))
                    val model = (activity.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart).model
                    assertTrue(diagram.contentDescription.contains(HealthAtlasPhysiologyText.result(activity, model)))
                } finally { before.recycle(); after.recycle() }
            }
            scenario.recreate()
            ready(scenario, "atlas-$art")
            scenario.onActivity { activity ->
                val seek = activity.view("atlas-physiology-$input") as SeekBar
                assertEquals(id, 0, seek.progress)
                activity.view("atlas-physiology-reset").performClick()
                assertEquals(id, initial, seek.progress)
            }
            capture(id)
            scenario.onActivity { it.onBackPressed() }
        }
    }
    @Test fun newStructureLessonsExposeLiveControlsAndKeepTheirFunctionPlayback() = native { scenario ->
        val examples = listOf("pulmonary-trunk", "colon", "thoracic-duct", "clavicle", "hair",
            "cell-oligodendrocyte", "cell-pancreatic-beta-cell", "cell-retinal-bipolar-cell", "cell-skeletal-myocyte",
            "stomach", "vestibular-apparatus", "cell-megakaryocyte", "cell-osteoblast", "cell-sebocyte",
            "external-ear", "liver", "joints", "cell-granulosa-cell", "cell-sweat-gland-secretory-cell")
        for (id in examples) scenario.onActivity { activity ->
            activity.open(id, cell = id.startsWith("cell-"))
            val kind = requireNotNull(HealthAtlasPhysiologyKind.forItem(id))
            val curve = activity.view("atlas-physiology-curve") as HealthAtlasPhysiologyChart
            val panel = activity.view("atlas-physiology-output") as TextView
            val control = activity.view("atlas-physiology-${kind.inputs[kind.axis].key}") as SeekBar
            assertEquals(id, kind, curve.model.kind)
            val initial = curve.model
            val initialText = panel.text.toString()
            control.progress = control.max
            assertNotEquals(id, initial.result, curve.model.result)
            assertNotEquals(id, initialText, panel.text.toString())
            assertNotNull(activity.view("atlas-physiology-source"))
            assertNotNull(activity.view("atlas-simulation-play"))
            activity.view("atlas-physiology-reset").performClick()
            assertEquals(id, initial, curve.model)
            activity.onBackPressed()
        }
    }
    @Test fun bladderFillingPlaybackChangesTheDiagramWithoutChangingTheSelectedVolume() = native { scenario ->
        scenario.onActivity { it.open("bladder") }
        capture("bladder-filling")
        scenario.onActivity { activity ->
            val diagram = activity.view("atlas-bladder-filling-diagram")
            val play = activity.view("atlas-bladder-filling-play")
            val output = activity.view("atlas-physiology-output") as TextView
            val added = activity.view("atlas-physiology-bladder-added-volume") as SeekBar
            val selected = added.progress
            val selectedOutput = output.text.toString()
            diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
            fun draw() = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888).also {
                diagram.draw(Canvas(it))
            }
            assertEquals(android.animation.ValueAnimator.areAnimatorsEnabled(), play.isEnabled)
            val full = draw()
            try {
                if (play.isEnabled) {
                    play.performClick()
                    assertEquals(activity.getString(R.string.health_atlas_bladder_expansion_pause), play.contentDescription)
                    play.performClick()
                    assertEquals(activity.getString(R.string.health_atlas_bladder_expansion_play), play.contentDescription)
                    val early = draw()
                    try { assertFalse(full.sameAs(early)) } finally { early.recycle() }
                }
                assertEquals(selected, added.progress)
                assertEquals(selectedOutput, output.text.toString())
                added.progress = 0
                assertFalse(play.isEnabled)
                assertNotEquals(selectedOutput, output.text.toString())
                val baseline = draw()
                try { assertFalse(full.sameAs(baseline)) } finally { baseline.recycle() }
                assertNotNull(activity.view("atlas-simulation-play"))
            } finally { full.recycle() }
        }
        scenario.recreate()
        ready(scenario, "atlas-bladder-filling-diagram")
        scenario.onActivity {
            assertEquals(0, (it.view("atlas-physiology-bladder-added-volume") as SeekBar).progress)
            assertFalse(it.view("atlas-bladder-filling-play").isEnabled)
        }
    }
    @Test fun ureterDiagramSeparatesPlaybackFromModelInputsAndRestoresTheSelection() = native { scenario ->
        scenario.onActivity { it.open("ureters") }
        capture("ureter-transport")
        scenario.onActivity { activity ->
            val play = activity.view("atlas-ureter-transport-play")
            val diagram = activity.view("atlas-ureter-transport-diagram")
            val count = activity.view("atlas-physiology-ureter-delivery-pushes") as SeekBar
            val perPush = activity.view("atlas-physiology-ureter-delivery-volume") as SeekBar
            val output = activity.view("atlas-physiology-output") as TextView
            val original = output.text.toString()
            diagram.measure(View.MeasureSpec.makeMeasureSpec(720, View.MeasureSpec.EXACTLY),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
            diagram.layout(0, 0, diagram.measuredWidth, diagram.measuredHeight)
            fun draw() = Bitmap.createBitmap(diagram.width, diagram.height, Bitmap.Config.ARGB_8888).also {
                diagram.draw(Canvas(it))
            }
            val selected = draw()
            try {
                if (android.animation.ValueAnimator.areAnimatorsEnabled()) {
                    assertTrue(play.isEnabled)
                    play.performClick()
                    assertEquals(activity.getString(R.string.health_atlas_ureter_delivery_pause), play.contentDescription)
                    play.performClick()
                    val early = draw()
                    try { assertFalse(selected.sameAs(early)) } finally { early.recycle() }
                }
                assertEquals(original, output.text.toString())
                assertEquals(3, count.progress)
                perPush.progress = perPush.max
                assertNotEquals(original, output.text.toString())
                val more = draw()
                try { assertFalse(selected.sameAs(more)) } finally { more.recycle() }
                count.progress = 2
            } finally { selected.recycle() }
        }
        scenario.recreate()
        ready(scenario, "atlas-ureter-transport-diagram")
        scenario.onActivity {
            assertEquals(2, (it.view("atlas-physiology-ureter-delivery-pushes") as SeekBar).progress)
            assertNotNull(it.view("atlas-simulation-play"))
        }
    }
    @Test fun threePhysiologyScreensShowIndependentModels() = native { scenario ->
        for (id in listOf("lungs", "kidneys", "cell-neuron")) {
            scenario.onActivity { it.open(id, id.startsWith("cell-")) }
            capture(id)
            scenario.onActivity { it.onBackPressed() }
        }
    }
}
