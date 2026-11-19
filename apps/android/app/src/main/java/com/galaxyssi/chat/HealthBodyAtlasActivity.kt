package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.Intent
import android.content.res.ColorStateList
import android.net.Uri
import android.os.Bundle
import android.text.Editable
import android.text.TextWatcher
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import java.util.concurrent.Executors

class HealthBodyAtlasActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private var atlas: HealthBodyAtlas? = null
    private lateinit var root: LinearLayout
    private lateinit var content: LinearLayout
    private var section = 0
    private var selection = ""
    private var system = ""
    private var query = ""
    private var tab = HealthAtlasTab.STRUCTURE
    private var limit = 24
    private var scrollY = 0
    private var scroller: ScrollView? = null
    private data class Destination(val id: String, val tab: HealthAtlasTab,
        val research: HealthAtlasResearchTopic?, val scroll: Int)
    private val history = arrayListOf<Destination>()
    private var dialog: Dialog? = null
    private var simulation: HealthAtlasSimulationPanel? = null
    private var simulationItem = ""
    private val simulationStates = linkedMapOf<String, HealthAtlasSimulation>()
    private val physiologyStates = linkedMapOf<String, HealthAtlasPhysiology>()
    private var measurements: HealthAtlasMeasurements? = null
    private var measurementItem = ""
    private val measurementSelections = linkedMapOf<String, HealthAtlasMeasurementSelection>()
    private var started = false
    private var researchTopic: HealthAtlasResearchTopic? = null
    private var research: HealthAtlasResearchPanel? = null
    private var researchItem = ""
    private val eliminationStates = linkedMapOf<String, HealthAtlasElimination>()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        section = state?.getInt("section")?.coerceIn(0, 3) ?: 0
        selection = state?.getString("selection").orEmpty()
        system = state?.getString("system").orEmpty()
        query = state?.getString("query").orEmpty().take(100)
        tab = HealthAtlasTab.entries.firstOrNull { it.name == state?.getString("tab") } ?: HealthAtlasTab.STRUCTURE
        researchTopic = HealthAtlasResearchTopic.entries.firstOrNull { it.name == state?.getString("researchTopic") }
        state?.getBundle("eliminations")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getBundle(key)?.let { value -> runCatching {
                HealthAtlasElimination(value.getInt("halfLife"), value.getInt("elapsed"))
            }.getOrNull()?.let { eliminationStates[key] = it } }
        } }
        state?.getBundle("historyV2")?.let { saved -> repeat(saved.getInt("count").coerceIn(0, 32)) { index ->
            saved.getBundle(index.toString())?.let { entry -> history.add(Destination(entry.getString("id").orEmpty(),
                HealthAtlasTab.entries.firstOrNull { it.name == entry.getString("tab") } ?: HealthAtlasTab.STRUCTURE,
                HealthAtlasResearchTopic.entries.firstOrNull { it.name == entry.getString("research") }, entry.getInt("scroll").coerceAtLeast(0))) }
        } }
        scrollY = state?.getInt("scroll") ?: 0
        state?.getBundle("simulations")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getBundle(key)?.let { value -> runCatching {
                HealthAtlasSimulation(value.getInt("first"), value.getInt("second"), value.getFloat("phase"), value.getFloat("speed"))
            }.getOrNull()?.let { simulationStates[key] = it } }
        } }
        state?.getBundle("physiologyV1")?.let { saved -> saved.keySet().take(300).forEach { key ->
            HealthAtlasPhysiology.restore(key, saved.getIntArray(key))?.let { physiologyStates[key] = it }
        } }
        state?.getBundle("measurementSelections")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getBundle(key)?.let { value -> measurementSelections[key] = HealthAtlasMeasurementSelection(
                HealthMetric.entries.firstOrNull { it.name == value.getString("metric") }, value.getInt("period", 1).coerceIn(0, 2)) }
        } }
        window.statusBarColor = getColor(R.color.page_bg); window.navigationBarColor = getColor(R.color.page_bg)
        if (android.os.Build.VERSION.SDK_INT >= 33) setRecentsScreenshotEnabled(false)
        root = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)); isSaveEnabled = false }
        setContentView(root)
        root.addView(ui.text(getString(R.string.health_loading)))
        worker.execute {
            val result = runCatching { HealthBodyAtlas.load(applicationContext) }
            runOnUiThread { if (!isDestroyed) result.fold({ loaded ->
                atlas = loaded
                if (loaded[selection] == null) { selection = ""; researchTopic = null }
                if (loaded[system]?.kind != HealthAtlasKind.SYSTEM) system = ""
                render()
            }, { error ->
                android.util.Log.e("HealthBodyAtlas", "Public catalogue load failed", error)
                root.removeAllViews()
                root.addView(ui.toolbar(R.string.health_body_title, ::finish))
                root.addView(ui.text(getString(R.string.health_atlas_load_error)))
                root.addView(ui.command(R.string.health_atlas_retry) { recreate() })
            }) }
        }
    }

    override fun onStart() { super.onStart(); started = true; if (atlas != null && tab == HealthAtlasTab.VALUES && selection.isNotEmpty()) render() }
    override fun onStop() {
        started = false; simulation?.pause(); saveMeasurementSelection(); measurements?.close(); measurements = null
        dialog?.dismiss(); dialog = null; super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        saveSimulation()
        saveResearch()
        saveMeasurementSelection()
        out.putInt("section", section); out.putString("selection", selection); out.putString("system", system)
        out.putString("query", query); out.putString("tab", tab.name)
        out.putBundle("historyV2", Bundle().apply {
            putInt("count", history.size)
            history.forEachIndexed { index, value -> putBundle(index.toString(), Bundle().apply {
                putString("id", value.id); putString("tab", value.tab.name); putString("research", value.research?.name); putInt("scroll", value.scroll)
            }) }
        })
        out.putString("researchTopic", researchTopic?.name)
        out.putBundle("eliminations", Bundle().apply { eliminationStates.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putInt("halfLife", value.halfLifeHours); putInt("elapsed", value.elapsedHours)
        }) } })
        out.putInt("scroll", scroller?.scrollY ?: 0)
        out.putBundle("simulations", Bundle().apply { simulationStates.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putInt("first", value.first); putInt("second", value.second); putFloat("phase", value.phase); putFloat("speed", value.speed)
        }) } })
        out.putBundle("physiologyV1", Bundle().apply {
            physiologyStates.forEach { (id, value) -> putIntArray(id, value.inputs.toIntArray()) }
        })
        out.putBundle("measurementSelections", Bundle().apply { measurementSelections.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putString("metric", value.metric?.name); putInt("period", value.period)
        }) } }); super.onSaveInstanceState(out)
    }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (researchTopic != null) { researchTopic = null; scrollY = 0; render(); return }
        if (selection.isEmpty()) { finish(); return }
        val previous = if (history.isEmpty()) null else history.removeAt(history.lastIndex)
        selection = previous?.id.orEmpty(); tab = previous?.tab ?: HealthAtlasTab.STRUCTURE
        researchTopic = previous?.research; scrollY = previous?.scroll ?: 0; render()
    }
    private fun select(item: HealthAtlasItem) {
        if (selection.isNotEmpty()) { history.add(Destination(selection, tab, researchTopic, scroller?.scrollY ?: 0)); if (history.size > 32) history.removeAt(0) }
        selection = item.id; tab = HealthAtlasTab.STRUCTURE; scrollY = 0
        researchTopic = null
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(root.windowToken, 0)
        render()
    }
    private fun render() {
        val data = atlas ?: return
        saveSimulation()
        saveResearch(); research = null
        saveMeasurementSelection()
        simulation?.pause(); simulation = null; measurements?.close(); measurements = null
        root.removeAllViews()
        val item = data[selection]
        val toolbar = ui.toolbar(R.string.health_body_title, ::back, ui.icon(R.drawable.ic_hub_search, R.string.health_atlas_search) {
            selection = ""; researchTopic = null; section = 2; scrollY = 0; render()
            root.findViewWithTag<EditText>("atlas-search")?.let { input -> input.requestFocus()
                (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(input, InputMethodManager.SHOW_IMPLICIT) }
        })
        toolbar.findViewWithTag<TextView>("health-page-title").text = if (researchTopic != null) getString(R.string.health_atlas_research)
            else item?.name ?: getString(R.string.health_body_title)
        root.addView(toolbar)
        val labels = if (researchTopic != null) HealthAtlasResearchTopic.entries.map { it.title }
            else if (item == null) listOf(R.string.health_atlas_whole, R.string.health_atlas_systems, R.string.health_atlas_organs, R.string.health_atlas_cells)
            else listOf(R.string.health_atlas_structure, R.string.health_atlas_function, R.string.health_atlas_values, R.string.health_atlas_simulation)
        root.addView(HealthAtlasUi.tabs(this, labels, researchTopic?.ordinal ?: if (item == null) section else tab.ordinal,
            if (researchTopic == null) "atlas-tab" else "atlas-research-tab") { index ->
            if (researchTopic != null) researchTopic = HealthAtlasResearchTopic.entries[index]
            else if (item == null) { section = index; query = ""; limit = 24 } else tab = HealthAtlasTab.entries[index]
            scrollY = 0; render()
        })
        content = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(16)) }
        val scroll = ScrollView(this).apply { isFillViewport = true; isSaveEnabled = false; addView(content); tag = "atlas-scroll" }
        scroller = scroll; root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        if (item == null) catalogue(data) else if (researchTopic != null) researchPage(data, item) else detail(data, item)
        root.addView(ui.command(R.string.health_atlas_ask) { ask(item, researchContext(item)) }.apply {
            tag = "atlas-ask"
        }, LinearLayout.LayoutParams(-1, -2).apply { setMargins(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12)) })
        scroll.post { if (scroller === scroll) scroll.scrollTo(0, scrollY) }
    }

    private fun catalogue(data: HealthBodyAtlas) {
        if (section == 0) {
            ui.add(content, HealthAtlasArtwork(this, data, null, ::select, ::zoom).apply { tag = "atlas-whole-art" })
            ui.add(content, ui.row(data["heart"]!!.name, data["cardio"]!!.name) { select(data["heart"]!!) })
            ui.add(content, ui.row(data["cell-pancreatic-beta-cell"]!!.name, data["endocrine"]!!.name) { select(data["cell-pancreatic-beta-cell"]!!) })
            ui.add(content, ui.text(getString(R.string.health_atlas_counts, data.systems.size,
                data.items.count { it.kind == HealthAtlasKind.ORGAN }, data.items.count { it.kind == HealthAtlasKind.CELL }), 12f, muted = true), 8)
            return
        }
        val search = healthProfileInput(query, 100).apply { hint = getString(R.string.health_atlas_search); tag = "atlas-search" }
        ui.add(content, search)
        if (section > 1) ui.add(content, ui.row(data[system]?.name ?: getString(R.string.health_atlas_all)) { chooseSystem(data) })
        val list = ui.column(); ui.add(content, list)
        fun update() {
            list.removeAllViews()
            val kind = listOf(HealthAtlasKind.SYSTEM, HealthAtlasKind.ORGAN, HealthAtlasKind.CELL)[section - 1]
            val found = data.search(query, kind, if (section == 1) "" else system)
            if (found.isEmpty()) list.addView(ui.text(getString(R.string.health_atlas_no_matches), 15f, muted = true))
            found.take(limit).forEach { row(list, it) }
            if (found.size > limit) ui.add(list, ui.command(R.string.health_atlas_more) { limit += 24; update() })
            ui.add(list, ui.text(getString(R.string.health_atlas_category_note), 12f, muted = true), 12)
        }
        search.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) { query = s.toString(); limit = 24; update() }
            override fun afterTextChanged(s: Editable?) = Unit
        }); update()
    }
    private fun chooseSystem(data: HealthBodyAtlas) {
        val choices = listOf(getString(R.string.health_atlas_all)) + data.systems.map { it.name }
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_atlas_systems).setItems(choices.toTypedArray()) { _, index ->
            system = if (index == 0) "" else data.systems[index - 1].id; limit = 24; scrollY = 0; render()
        }.setNegativeButton(android.R.string.cancel, null).show()
    }
    private fun row(parent: LinearLayout, item: HealthAtlasItem) {
        ui.add(parent, HealthAtlasUi.row(this, item, atlas!!) { select(item) }.apply { tag = "atlas-entry-${item.id}" })
    }
    private fun detail(data: HealthBodyAtlas, item: HealthAtlasItem) {
        when (tab) {
            HealthAtlasTab.STRUCTURE -> {
                ui.add(content, HealthAtlasArtwork(this, data, item, ::select, ::zoom))
                ui.add(content, ui.text(item.description, 16f), 12)
                val children = data.children(item)
                if (children.isNotEmpty()) { heading(R.string.health_atlas_related); children.forEach { row(content, it) } }
                val cells = data.cells(item)
                if (cells.isNotEmpty()) { heading(R.string.health_atlas_cells); cells.forEach { row(content, it) } }
                heading(R.string.health_atlas_belongs)
                (data.parents(item) + item.systems.filter { it != item.id }.mapNotNull(data::get)).distinctBy { it.id }.forEach { row(content, it) }
            }
            HealthAtlasTab.FUNCTION -> {
                ui.add(content, HealthAtlasArtwork(this, data, item, ::select, ::zoom))
                ui.add(content, ui.text(item.description, 17f), 12)
                val mechanism = data.mechanism(item)
                ui.add(content, ui.text(getString(R.string.health_atlas_related_process, mechanism.title), 17f, bold = true), 22)
                mechanism.stages.forEachIndexed { index, stage -> ui.add(content, ui.text("${index + 1}. $stage", 16f), 12) }
                ui.add(content, ui.text(getString(R.string.health_atlas_process_note), 12f, muted = true), 16)
                ui.add(content, ui.command(R.string.health_atlas_simulation) { tab = HealthAtlasTab.SIMULATION; scrollY = 0; render() }, 12)
                ui.add(content, ui.row(getString(R.string.health_atlas_research)) { openResearch() }.apply { tag = "atlas-open-research" }, 12)
            }
            HealthAtlasTab.VALUES -> {
                measurementItem = item.id
                if (started) measurements = HealthAtlasMeasurements(this, content, item, measurementSelections[item.id])
                else content.addView(ui.text(getString(R.string.health_loading)))
            }
            HealthAtlasTab.SIMULATION -> {
                simulationItem = item.id
                simulation = HealthAtlasSimulationPanel(this, content, data, item, simulationStates[item.id], physiologyStates[item.id], ::zoom, ::source)
                ui.add(content, ui.row(getString(R.string.health_atlas_research)) { openResearch() }.apply { tag = "atlas-open-research" }, 12)
            }
        }
        if (tab != HealthAtlasTab.VALUES) ui.add(content, ui.row(getString(R.string.health_atlas_evidence), "OpenStax · Anatomy and Physiology 2e") {
            source(data.mechanism(item).source)
        }, 18)
        if (HealthAtlasUi.art(item) != null && tab != HealthAtlasTab.VALUES)
            ui.add(content, ui.text(getString(R.string.health_atlas_art_note), 11f, muted = true), 8)
    }
    private fun heading(title: Int) { ui.add(content, ui.text(getString(title), 18f, bold = true), 22) }
    private fun saveSimulation() { simulation?.let {
        simulationStates[simulationItem] = it.snapshot
        it.quantitativeSnapshot?.let { model -> physiologyStates[simulationItem] = model }
    } }
    private fun saveMeasurementSelection() { measurements?.let { measurementSelections[measurementItem] = it.selection } }
    private fun saveResearch() { research?.let { eliminationStates[researchItem] = it.elimination } }
    private fun openResearch() { researchTopic = HealthAtlasResearchTopic.PHYSIOLOGY; scrollY = 0; render() }
    private fun researchPage(data: HealthBodyAtlas, item: HealthAtlasItem) {
        val topic = requireNotNull(researchTopic)
        researchItem = item.id
        if (topic == HealthAtlasResearchTopic.PHYSIOLOGY) {
            ui.add(content, ui.text(item.name + " · " + item.systems.mapNotNull(data::get).joinToString(" · ") { it.name }, 14f, muted = true))
            simulationItem = item.id
            simulation = HealthAtlasSimulationPanel(this, content, data, item, simulationStates[item.id], physiologyStates[item.id], ::zoom, ::source)
            ui.add(content, ui.row(getString(R.string.health_atlas_evidence), "OpenStax · Anatomy and Physiology 2e") {
                source(data.mechanism(item).source)
            }.apply { tag = "atlas-source-physiology" }, 16)
        } else research = HealthAtlasResearchPanel(this, content, data, item, topic, eliminationStates[item.id], ::select, ::source)
    }
    private fun researchContext(item: HealthAtlasItem?): String {
        item ?: return ""
        val quantitative = if (researchTopic == HealthAtlasResearchTopic.PHYSIOLOGY ||
            researchTopic == null && tab == HealthAtlasTab.SIMULATION)
            simulation?.quantitativeSnapshot?.let { HealthAtlasPhysiologyText.context(this, it) }.orEmpty() else ""
        val topic = researchTopic ?: return quantitative
        val sources = HealthAtlasResearchSources.forTopic(topic, atlas!!.mechanism(item)).joinToString("\n")
        val limits = getString(when (topic) {
            HealthAtlasResearchTopic.PHYSIOLOGY -> R.string.health_atlas_teaching_note
            HealthAtlasResearchTopic.DRUGS -> R.string.health_atlas_elimination_assumptions
            HealthAtlasResearchTopic.AGING -> R.string.health_atlas_aging_evidence
        })
        val parameters = if (topic == HealthAtlasResearchTopic.DRUGS) {
            val values = research?.elimination ?: eliminationStates[item.id] ?: HealthAtlasElimination()
            "\n" + getString(R.string.health_atlas_elimination_summary, values.halfLifeHours, values.elapsedHours,
                java.text.NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }.format(values.percent))
        } else if (quantitative.isNotEmpty()) "\n$quantitative" else ""
        return getString(topic.title) + "\n" + limits + parameters + "\n" + sources
    }
    private fun source(url: String) {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
            .onFailure { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_SHORT).show() }
    }
    private fun zoom(drawable: Int, title: String) {
        dialog?.dismiss()
        dialog = Dialog(this, android.R.style.Theme_Material_Light_NoActionBar).apply {
            val box = ui.column().apply { setBackgroundColor(getColor(R.color.page_bg)) }
            box.addView(ui.toolbar(R.string.health_body_title, { dismiss() }))
            box.addView(ui.text(title, 14f).apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(8)) })
            val image = ImageView(this@HealthBodyAtlasActivity).apply {
                setImageResource(drawable); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = title
                tag = "atlas-fullscreen-image"
            }
            box.addView(GalaxySSIPinchZoomViewport(this@HealthBodyAtlasActivity).apply { attach(image) }, LinearLayout.LayoutParams(-1, 0, 1f))
            setContentView(box); show(); window?.setLayout(-1, -1)
        }
    }
    private fun ask(item: HealthAtlasItem?, focus: String = "") {
        val prompt = (item?.let {
            val model = atlas!!.mechanism(it)
            getString(R.string.health_atlas_ask_context, it.name, it.description, model.title, model.source)
        } ?: getString(R.string.health_atlas_ask_whole_context)) +
            if (focus.isBlank()) "" else "\n$focus"
        dialog = AlertDialog.Builder(this).setTitle(R.string.health_atlas_ask_ready).setMessage(prompt)
            .setNegativeButton(android.R.string.cancel, null).setPositiveButton(R.string.health_atlas_ask) { _, _ ->
                worker.execute {
                    val result = runCatching { HealthAtlasAgentHandoff.prepare(applicationContext, item?.name ?: getString(R.string.health_body_title), prompt) }
                    runOnUiThread { if (!isDestroyed && started) result.onSuccess(::startActivity)
                        .onFailure { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_LONG).show() } }
                }
            }.show()
    }
}
