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
import java.util.Locale
import java.util.concurrent.Executors

class HealthBodyAtlasActivity : Activity() {
    private val ui by lazy { HealthCenterViews(this) }
    private val worker = Executors.newSingleThreadExecutor()
    private var atlas: HealthBodyAtlas? = null
    private lateinit var root: LinearLayout
    private lateinit var content: LinearLayout
    private var section = 0
    private var showTissueCatalogue = false
    private var selection = ""
    private var wholeFocus = "heart"
    private var revealTrend = false
    private var system = ""
    private var query = ""
    private var tab = HealthAtlasTab.STRUCTURE
    private var limit = 24
    private var scrollY = 0
    private var scroller: ScrollView? = null
    private data class Destination(val id: String, val tab: HealthAtlasTab,
        val research: HealthAtlasResearchTopic?, val scroll: Int, val functionScroll: Int)
    private val history = arrayListOf<Destination>()
    private var dialog: Dialog? = null
    private var simulation: HealthAtlasSimulationPanel? = null
    private var simulationItem = ""
    private val simulationStates = linkedMapOf<String, HealthAtlasSimulation>()
    private val expandedModels = linkedSetOf<String>()
    private var functionPlayer: HealthAtlasFunctionPlayer? = null
    private var functionItem = ""
    private val functionState = HealthAtlasFunctionState()
    private val physiologyStates = linkedMapOf<String, HealthAtlasPhysiology>()
    private var measurements: HealthAtlasMeasurements? = null
    private var measurementAction: View? = null
    private var measurementItem = ""
    private val measurementSelections = linkedMapOf<String, HealthAtlasMeasurementSelection>()
    private var started = false
    private var researchTopic: HealthAtlasResearchTopic? = null
    private var researchReturnScroll = 0
    private var research: HealthAtlasResearchPanel? = null
    private var aging: HealthAtlasAgingPanel? = null
    private var researchItem = ""
    private val eliminationStates = linkedMapOf<String, HealthAtlasElimination>()
    private val drugStates = linkedMapOf<String, HealthAtlasDrugState>()
    private val agingSelections = linkedMapOf<String, HealthAtlasAgingSelection>()
    private val artworkViews = linkedMapOf<String, String>()
    private enum class StructureLayer(val label: Int) {
        ORGAN(R.string.health_atlas_organ_layer),
        TISSUE(R.string.health_atlas_tissues),
        CELL(R.string.health_atlas_cells),
    }
    private val structureLayers = linkedMapOf<String, StructureLayer>()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        section = state?.getInt("section")?.coerceIn(0, 3) ?: 0
        showTissueCatalogue = state?.getBoolean("showTissueCatalogue") == true
        selection = state?.getString("selection").orEmpty()
        wholeFocus = state?.getString("wholeFocus") ?: "heart"
        revealTrend = state?.getBoolean("revealTrend") == true
        system = state?.getString("system").orEmpty()
        query = state?.getString("query").orEmpty().take(100)
        tab = HealthAtlasTab.entries.firstOrNull { it.name == state?.getString("tab") } ?: HealthAtlasTab.STRUCTURE
        researchTopic = HealthAtlasResearchTopic.entries.firstOrNull { it.name == state?.getString("researchTopic") }
        researchReturnScroll = state?.getInt("researchReturnScroll")?.coerceAtLeast(0) ?: 0
        functionState.restore(state?.getBundle("functionStateV2"), state?.getBundle("functionPhasesV1"))
        state?.getStringArrayList("expandedModels")?.let { expandedModels.addAll(it.take(320)) }
        state?.getBundle("artworkViewsV1")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getString(key)?.let { view ->
                if (HealthAtlasPlates.forId(key, view)?.viewKey == view) artworkViews[key] = view
            }
        } }
        state?.getBundle("structureLayersV1")?.let { saved -> saved.keySet().take(300).forEach { key ->
            StructureLayer.entries.firstOrNull { it.name == saved.getString(key) }?.let { structureLayers[key] = it }
        } }
        state?.getBundle("drugModelsV1")?.let { saved -> saved.keySet().take(300).forEach { key ->
            HealthAtlasDrugState.restore(saved.getIntArray(key))?.let { drugStates[key] = it }
        } }
        state?.getBundle("agingSelectionsV1")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getBundle(key)?.let { value ->
                HealthAtlasAgingSelection.restore(value.getString("topic"), value.getInt("step", -1))?.let { agingSelections[key] = it }
            }
        } }
        state?.getBundle("eliminations")?.let { saved -> saved.keySet().take(300).forEach { key ->
            saved.getBundle(key)?.let { value -> runCatching {
                HealthAtlasElimination(value.getInt("halfLife"), value.getInt("elapsed"))
            }.getOrNull()?.let { eliminationStates[key] = it } }
        } }
        state?.getBundle("historyV2")?.let { saved -> repeat(saved.getInt("count").coerceIn(0, 32)) { index ->
            saved.getBundle(index.toString())?.let { entry -> history.add(Destination(entry.getString("id").orEmpty(),
                HealthAtlasTab.entries.firstOrNull { it.name == entry.getString("tab") } ?: HealthAtlasTab.STRUCTURE,
                HealthAtlasResearchTopic.entries.firstOrNull { it.name == entry.getString("research") },
                entry.getInt("scroll").coerceAtLeast(0), entry.getInt("functionScroll").coerceAtLeast(0))) }
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
        started = false; simulation?.pause(); functionPlayer?.pause(); saveMeasurementSelection(); measurements?.close(); measurements = null
        dialog?.dismiss(); dialog = null; super.onStop()
    }
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
    override fun onSaveInstanceState(out: Bundle) {
        saveSimulation()
        saveFunctionStory()
        saveResearch()
        saveMeasurementSelection()
        out.putInt("section", section); out.putString("selection", selection); out.putString("system", system)
        out.putString("wholeFocus", wholeFocus); out.putBoolean("revealTrend", revealTrend)
        out.putBoolean("showTissueCatalogue", showTissueCatalogue)
        out.putBundle("structureLayersV1", Bundle().apply { structureLayers.forEach { (id, layer) -> putString(id, layer.name) } })
        out.putString("query", query); out.putString("tab", tab.name)
        out.putBundle("historyV2", Bundle().apply {
            putInt("count", history.size)
            history.forEachIndexed { index, value -> putBundle(index.toString(), Bundle().apply {
                putString("id", value.id); putString("tab", value.tab.name); putString("research", value.research?.name)
                putInt("scroll", value.scroll); putInt("functionScroll", value.functionScroll)
            }) }
        })
        out.putString("researchTopic", researchTopic?.name)
        out.putInt("researchReturnScroll", researchReturnScroll)
        out.putStringArrayList("expandedModels", ArrayList(expandedModels))
        out.putBundle("artworkViewsV1", Bundle().apply { artworkViews.forEach { (id, view) -> putString(id, view) } })
        out.putBundle("drugModelsV1", Bundle().apply { drugStates.forEach { (id, value) -> putIntArray(id, value.encode()) } })
        out.putBundle("agingSelectionsV1", Bundle().apply { agingSelections.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putString("topic", value.topic.name); putInt("step", value.step)
        }) } })
        out.putBundle("eliminations", Bundle().apply { eliminationStates.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putInt("halfLife", value.halfLifeHours); putInt("elapsed", value.elapsedHours)
        }) } })
        out.putInt("scroll", scroller?.scrollY ?: 0)
        out.putBundle("simulations", Bundle().apply { simulationStates.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putInt("first", value.first); putInt("second", value.second); putFloat("phase", value.phase); putFloat("speed", value.speed)
        }) } })
        out.putBundle("functionStateV2", functionState.snapshot())
        out.putBundle("physiologyV1", Bundle().apply {
            physiologyStates.forEach { (id, value) -> putIntArray(id, value.inputs.toIntArray()) }
        })
        out.putBundle("measurementSelections", Bundle().apply { measurementSelections.forEach { (id, value) -> putBundle(id, Bundle().apply {
            putString("metric", value.metric?.name); putInt("period", value.period)
        }) } }); super.onSaveInstanceState(out)
    }
    @Deprecated("Native back callback") override fun onBackPressed() = back()
    private fun back() {
        if (researchTopic != null) {
            researchTopic = null; scrollY = researchReturnScroll; researchReturnScroll = 0; render(); return
        }
        if (selection.isEmpty()) { finish(); return }
        val previous = if (history.isEmpty()) null else history.removeAt(history.lastIndex)
        selection = previous?.id.orEmpty(); tab = previous?.tab ?: HealthAtlasTab.STRUCTURE
        researchTopic = previous?.research; scrollY = previous?.scroll ?: 0
        researchReturnScroll = previous?.functionScroll ?: 0; render()
    }
    private fun select(item: HealthAtlasItem) = select(item, HealthAtlasTab.STRUCTURE)

    private fun select(item: HealthAtlasItem, destination: HealthAtlasTab, showTrend: Boolean = false) {
        if (selection.isEmpty() && section == 0) wholeFocus = item.id
        if (selection.isNotEmpty()) {
            history.add(Destination(selection, tab, researchTopic, scroller?.scrollY ?: 0, researchReturnScroll))
            if (history.size > 32) history.removeAt(0)
        }
        selection = item.id; tab = destination; scrollY = 0
        revealTrend = showTrend
        researchTopic = null; researchReturnScroll = 0
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(root.windowToken, 0)
        render()
    }
    private fun render() {
        val data = atlas ?: return
        simulation?.pause(); saveSimulation()
        functionPlayer?.pause(); saveFunctionStory(); functionPlayer = null
        saveResearch(); research = null; aging = null
        saveMeasurementSelection()
        simulation = null; measurements?.close(); measurements = null
        measurementAction = null
        root.removeAllViews()
        val item = data[selection]
        val inlineModels = item != null && usesInlineModels(item)
        if (inlineModels && tab == HealthAtlasTab.SIMULATION) {
            expandedModels += requireNotNull(item).id
            tab = HealthAtlasTab.FUNCTION
        }
        if (inlineModels && researchTopic == HealthAtlasResearchTopic.PHYSIOLOGY) {
            expandedModels += requireNotNull(item).id
            tab = HealthAtlasTab.FUNCTION
            researchTopic = null; scrollY = researchReturnScroll; researchReturnScroll = 0
        }
        val topic = researchTopic
        val topics = if (inlineModels) listOf(HealthAtlasResearchTopic.DRUGS, HealthAtlasResearchTopic.AGING)
            else HealthAtlasResearchTopic.entries
        val toolbar = ui.toolbar(R.string.health_body_title, ::back, ui.icon(R.drawable.ic_hub_search, R.string.health_atlas_search) {
            selection = ""; researchTopic = null; researchReturnScroll = 0; section = 2
            showTissueCatalogue = false; scrollY = 0; render()
            root.findViewWithTag<EditText>("atlas-search")?.let { input -> input.requestFocus()
                (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager).showSoftInput(input, InputMethodManager.SHOW_IMPLICIT) }
        })
        toolbar.findViewWithTag<TextView>("health-page-title").text = if (topic != null) getString(researchTitle(inlineModels))
            else item?.name ?: getString(R.string.health_body_title)
        root.addView(toolbar)
        val labels = if (topic != null) topics.map { it.title }
            else if (item == null) listOf(R.string.health_atlas_whole, R.string.health_atlas_systems, R.string.health_atlas_organs, R.string.health_atlas_cells)
            else if (inlineModels) listOf(R.string.health_atlas_structure, R.string.health_atlas_function, R.string.health_atlas_values)
            else listOf(R.string.health_atlas_structure, R.string.health_atlas_function, R.string.health_atlas_values, R.string.health_atlas_simulation)
        root.addView(HealthAtlasUi.tabs(this, labels, topic?.let(topics::indexOf) ?: if (item == null) section else tab.ordinal,
            if (topic == null) "atlas-tab" else "atlas-research-tab",
            tagKey = { index -> if (topic == null) index.toString() else topics[index].name.lowercase(Locale.ROOT) }) { index ->
            if (topic != null) researchTopic = topics[index]
            else if (item == null) { section = index; query = ""; limit = 24 } else tab = HealthAtlasTab.entries[index]
            revealTrend = false
            scrollY = 0; render()
        })
        content = ui.column().apply { setPadding(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(16)) }
        val scroll = ScrollView(this).apply { isFillViewport = true; isSaveEnabled = false; addView(content); tag = "atlas-scroll" }
        scroller = scroll; root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        if (item == null) catalogue(data) else if (researchTopic != null) researchPage(data, item) else detail(data, item)
        val personal = item != null && researchTopic == null && tab == HealthAtlasTab.VALUES
        root.addView(ui.command(if (personal) R.string.health_atlas_compare else R.string.health_atlas_ask) {
            if (personal) measurements?.analyze() else ask(item ?: if (section == 0) wholeItem(data) else null)
        }.apply {
            tag = "atlas-ask"
            if (personal) { measurementAction = this; isEnabled = measurements?.canAnalyze == true }
        }, LinearLayout.LayoutParams(-1, -2).apply { setMargins(ui.dp(16), ui.dp(8), ui.dp(16), ui.dp(12)) })
        scroll.post { if (scroller === scroll) scroll.scrollTo(0, scrollY) }
    }

    private fun wholeItem(data: HealthBodyAtlas) = data[wholeFocus] ?: requireNotNull(data["heart"])

    private fun catalogue(data: HealthBodyAtlas) {
        if (section == 0) {
            ui.add(content, HealthAtlasArtwork(this, data, null, ::select,
                { plate, title -> zoomAnatomy(data, null, plate, title) }).apply { tag = "atlas-whole-art" })
            val focus = wholeItem(data)
            ui.add(content, HealthAtlasUi.wholeBodyActions(this, data, focus,
                structure = { select(focus) },
                metrics = { select(focus, HealthAtlasTab.VALUES) },
                trend = { select(focus, HealthAtlasTab.VALUES, showTrend = true) }), 8)
            ui.add(content, ui.text(getString(R.string.health_atlas_counts, data.systems.size,
                data.items.count { it.kind == HealthAtlasKind.ORGAN }, data.tissues.size,
                data.items.count { it.kind == HealthAtlasKind.CELL }), 12f, muted = true), 8)
            return
        }
        val catalogueLayers = ui.column()
        if (section == 2) ui.add(content, catalogueLayers)
        val search = healthProfileInput(query, 100).apply { hint = getString(R.string.health_atlas_search); tag = "atlas-search" }
        ui.add(content, search)
        if (section > 1) ui.add(content, ui.row(data[system]?.name ?: getString(R.string.health_atlas_all)) { chooseSystem(data) })
        val list = ui.column(); ui.add(content, list)
        fun update() {
            list.removeAllViews()
            val kind = when (section) {
                1 -> HealthAtlasKind.SYSTEM
                2 -> if (showTissueCatalogue) HealthAtlasKind.TISSUE else HealthAtlasKind.ORGAN
                else -> HealthAtlasKind.CELL
            }
            val found = data.search(query, kind, if (section == 1) "" else system)
            if (found.isEmpty()) list.addView(ui.text(getString(R.string.health_atlas_no_matches), 15f, muted = true))
            found.take(limit).forEach { row(list, it) }
            if (found.size > limit) ui.add(list, ui.command(R.string.health_atlas_more) { limit += 24; update() })
            ui.add(list, ui.text(getString(R.string.health_atlas_category_note), 12f, muted = true), 12)
        }
        fun showLayers() {
            catalogueLayers.removeAllViews()
            catalogueLayers.addView(HealthAtlasUi.tabs(this, listOf(R.string.health_atlas_organs, R.string.health_atlas_tissues),
                if (showTissueCatalogue) 1 else 0, "atlas-catalogue-layer") { index ->
                if (showTissueCatalogue != (index == 1)) {
                    showTissueCatalogue = index == 1
                    limit = 24
                    showLayers()
                    update()
                }
            })
        }
        if (section == 2) showLayers()
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
    private fun usesInlineModels(item: HealthAtlasItem) =
        item.kind == HealthAtlasKind.SYSTEM || item.kind == HealthAtlasKind.ORGAN

    private fun researchTitle(inline: Boolean): Int =
        if (inline) R.string.health_atlas_targeted_research else R.string.health_atlas_research

    private fun addInlineModels(data: HealthBodyAtlas, item: HealthAtlasItem) {
        val models = ui.column().apply { tag = "atlas-inline-models" }
        fun show(open: Boolean) {
            if (open) {
                expandedModels += item.id
                functionPlayer?.pause()
                simulationItem = item.id
                simulation = HealthAtlasSimulationPanel(this, models, data, item, simulationStates[item.id],
                    physiologyStates[item.id], ::zoom, ::source, ::select, mechanismFirst = true, inline = true,
                    onPlay = { functionPlayer?.pause() })
                addMechanismSource(models, data, item)
            } else {
                expandedModels -= item.id
                simulation?.pause(); saveSimulation(); simulation = null
                models.removeAllViews()
            }
            models.visibility = if (open) View.VISIBLE else View.GONE
        }
        ui.add(content, HealthAtlasUi.disclosure(this, getString(R.string.health_atlas_inline_models),
            "atlas-open-simulation", item.id in expandedModels, ::show), 12)
        ui.add(content, models)
        show(item.id in expandedModels)
    }

    private fun addFunctionPrinciple(data: HealthBodyAtlas, item: HealthAtlasItem) {
        val mechanism = data.mechanism(item)
        val title = getString(R.string.health_atlas_related_process, mechanism.title)
        val principle = ui.column().apply { visibility = View.GONE; tag = "atlas-function-principle" }
        ui.add(content, HealthAtlasUi.disclosure(this, title, "atlas-function-principle-toggle") { open ->
            if (open && principle.childCount == 0) {
                mechanism.stages.forEachIndexed { index, stage ->
                    ui.add(principle, ui.text(getString(R.string.health_atlas_stage, index + 1, mechanism.stages.size, stage), 16f), 8)
                }
                ui.add(principle, ui.text(getString(R.string.health_atlas_process_note), 12f, muted = true), 12)
            }
            principle.visibility = if (open) View.VISIBLE else View.GONE
        }, 8)
        ui.add(content, principle)
    }

    private fun detail(data: HealthBodyAtlas, item: HealthAtlasItem) {
        when (tab) {
            HealthAtlasTab.STRUCTURE -> structure(data, item)
            HealthAtlasTab.FUNCTION -> {
                val choices = HealthAtlasFunctionStory.choicesForId(item.id)
                if (choices.isEmpty()) ui.add(content, artwork(data, item)) else functionLessons(data, item, choices)
                if (usesInlineModels(item)) addInlineModels(data, item)
                else ui.add(content, ui.navigationRow(R.drawable.ic_health_data_chart, R.string.health_atlas_open_quantitative_model) {
                    tab = HealthAtlasTab.SIMULATION
                    scrollY = 0
                    render()
                }.apply { tag = "atlas-open-simulation" }, 12)
                ui.add(content, ui.text(item.description, 17f), 12)
                addFunctionPrinciple(data, item)
                val hasAlternateView = item.kind == HealthAtlasKind.SYSTEM &&
                    HealthAtlasMusculoskeletalPlates.viewsForId(item.id).size > 1
                val hasLessonHotspots = choices.any { it.showStructurePreview } &&
                    HealthAtlasPlates.forId(item.id)?.hasLabels == true
                if (choices.isNotEmpty() && (hasAlternateView || hasLessonHotspots)) {
                    ui.add(content, artwork(data, item), 12)
                }
                ui.add(content, ui.row(getString(researchTitle(usesInlineModels(item)))) { openResearch(item) }
                    .apply { tag = "atlas-open-research" }, 12)
            }
            HealthAtlasTab.VALUES -> {
                measurementItem = item.id
                if (started) {
                    measurements = HealthAtlasMeasurements(this, content, item, measurementSelections[item.id],
                        revealTrend = revealTrend) { measurementAction?.isEnabled = it && started }
                    revealTrend = false
                }
                else content.addView(ui.text(getString(R.string.health_loading)))
            }
            HealthAtlasTab.SIMULATION -> {
                simulationItem = item.id
                simulation = HealthAtlasSimulationPanel(this, content, data, item, simulationStates[item.id], physiologyStates[item.id], ::zoom, ::source, ::select)
                ui.add(content, ui.row(getString(R.string.health_atlas_research)) { openResearch(item) }
                    .apply { tag = "atlas-open-research" }, 12)
            }
        }
        if (tab == HealthAtlasTab.STRUCTURE || tab == HealthAtlasTab.FUNCTION) HealthAtlasPlates.forId(item.id)?.source?.let { url ->
            ui.add(content, ui.row(getString(R.string.health_atlas_plate_source)) { source(url) }
                .apply { tag = "atlas-source-structure" }, 18)
        }
        if (tab != HealthAtlasTab.VALUES && !(usesInlineModels(item) && tab == HealthAtlasTab.FUNCTION))
            addMechanismSource(content, data, item)
        if (HealthAtlasUi.art(item) != null && tab != HealthAtlasTab.VALUES)
            ui.add(content, ui.text(getString(R.string.health_atlas_art_note), 11f, muted = true), 8)
    }
    private fun functionLessons(data: HealthBodyAtlas, item: HealthAtlasItem, choices: List<HealthAtlasFunctionStory>) {
        val panel = ui.column()
        ui.add(content, panel)
        fun show(story: HealthAtlasFunctionStory) {
            functionPlayer?.pause()
            saveFunctionStory()
            panel.removeAllViews()
            if (choices.size > 3) {
                val menu = ui.row(getString(R.string.health_atlas_sense_choose), getString(story.choiceTitle)) {
                    dialog = AlertDialog.Builder(this).setTitle(R.string.health_atlas_sense_choose)
                        .setSingleChoiceItems(choices.map { getString(it.choiceTitle) }.toTypedArray(), choices.indexOf(story)) { picker, index ->
                            picker.dismiss()
                            val next = choices[index]
                            if (next != story) {
                                functionState.choose(item.id, next)
                                show(next)
                                panel.findViewWithTag<View>("atlas-function-lesson-menu")?.requestFocus()
                            }
                        }.setNegativeButton(android.R.string.cancel, null).show()
                }.apply { tag = "atlas-function-lesson-menu" }
                ui.add(panel, menu)
            } else if (choices.size > 1) {
                ui.add(panel, HealthAtlasUi.tabs(this, choices.map { it.choiceTitle }, choices.indexOf(story),
                    "atlas-function-lesson") { index ->
                    val next = choices[index]
                    if (next != story) {
                        functionState.choose(item.id, next)
                        show(next)
                        panel.findViewWithTag<View>("atlas-function-lesson-$index")?.requestFocus()
                    }
                })
            }
            functionItem = item.id
            val tabAlreadyNamesLesson = choices.size in 2..3 && getString(story.choiceTitle) == getString(story.title)
            val player = HealthAtlasFunctionPlayer(this, story, functionState.loadPhase(item.id, story), ::source,
                showTitle = !tabAlreadyNamesLesson) {
                simulation?.pause()
            }
            functionPlayer = player
            ui.add(panel, player, if (choices.size > 1) 10 else 0)
            story.relatedLessons.forEach { (id, next) ->
                val target = data[id] ?: return@forEach
                ui.add(panel, ui.row(getString(next.title), target.name) {
                    functionState.choose(id, next)
                    select(target, HealthAtlasTab.FUNCTION)
                }.apply { tag = "atlas-related-lesson-$id" }, 12)
            }
        }
        show(functionState.current(item.id) ?: choices.first())
    }

    private fun structure(data: HealthBodyAtlas, item: HealthAtlasItem) {
        fun rows(parent: LinearLayout, title: Int, items: List<HealthAtlasItem>) {
            if (items.isEmpty()) return
            ui.add(parent, ui.text(getString(title), 18f, bold = true), 22)
            items.distinctBy { it.id }.forEach { row(parent, it) }
        }
        fun anatomy(parent: LinearLayout) {
            ui.add(parent, artwork(data, item))
            ui.add(parent, ui.text(item.description, 16f), 12)
            val cells = if (item.kind == HealthAtlasKind.CELL || item.kind == HealthAtlasKind.FRAGMENT) emptyList() else data.cells(item)
            rows(parent, R.string.health_atlas_related, data.children(item).filterNot { it in cells })
            if (item.kind == HealthAtlasKind.SYSTEM) rows(parent, R.string.health_atlas_tissues, data.tissues(item))
            rows(parent, if (item.kind == HealthAtlasKind.TISSUE) R.string.health_atlas_tissue_cell_examples else R.string.health_atlas_cells, cells)
            val systems = item.systems.filter { it != item.id }.mapNotNull(data::get)
            if (item.kind == HealthAtlasKind.TISSUE) {
                rows(parent, R.string.health_atlas_tissue_locations, item.locatedIn.mapNotNull(data::get))
                rows(parent, R.string.health_atlas_belongs, systems)
            } else rows(parent, R.string.health_atlas_belongs, data.parents(item) + systems)
        }
        if (item.kind != HealthAtlasKind.ORGAN) { anatomy(content); return }
        val layers = ui.column()
        val selected = ui.column().apply { tag = "atlas-structure-layer-content" }
        ui.add(content, layers)
        ui.add(content, selected)
        fun renderLayer() {
            val current = structureLayers[item.id] ?: StructureLayer.ORGAN
            layers.removeAllViews()
            layers.addView(HealthAtlasUi.tabs(this, StructureLayer.entries.map { it.label }, current.ordinal, "atlas-structure-layer") { index ->
                val next = StructureLayer.entries[index]
                if (next != current) {
                    structureLayers[item.id] = next
                    renderLayer()
                }
            })
            selected.removeAllViews()
            when (current) {
                StructureLayer.ORGAN -> anatomy(selected)
                StructureLayer.TISSUE, StructureLayer.CELL -> {
                    val items = if (current == StructureLayer.TISSUE) data.tissues(item) else data.cells(item)
                    if (items.isEmpty()) ui.add(selected, ui.text(getString(
                        if (current == StructureLayer.TISSUE) R.string.health_atlas_no_linked_tissues else R.string.health_atlas_no_linked_cells),
                        15f, muted = true), 18)
                    else items.forEach { row(selected, it) }
                }
            }
        }
        renderLayer()
    }
    private fun artwork(data: HealthBodyAtlas, item: HealthAtlasItem) = HealthAtlasArtwork(this, data, item, ::select,
        { plate, title -> zoomAnatomy(data, item.id, plate, title) }, artworkViews[item.id]) { artworkViews[item.id] = it }
    private fun saveSimulation() { simulation?.let {
        simulationStates[simulationItem] = it.snapshot
        it.quantitativeSnapshot?.let { model -> physiologyStates[simulationItem] = model }
    } }
    private fun saveFunctionStory() { functionPlayer?.let { functionState.savePhase(functionItem, it.story, it.phase) } }
    private fun saveMeasurementSelection() { measurements?.let { measurementSelections[measurementItem] = it.selection } }
    private fun saveResearch() {
        research?.let { eliminationStates[researchItem] = it.elimination; drugStates[researchItem] = it.drugState }
        aging?.let { agingSelections[researchItem] = it.selection }
    }
    private fun openResearch(item: HealthAtlasItem) {
        researchReturnScroll = scroller?.scrollY ?: 0
        researchTopic = if (usesInlineModels(item)) HealthAtlasResearchTopic.DRUGS else HealthAtlasResearchTopic.PHYSIOLOGY
        scrollY = 0; render()
    }
    private fun addMechanismSource(parent: LinearLayout, data: HealthBodyAtlas, item: HealthAtlasItem) {
        ui.add(parent, ui.row(getString(R.string.health_atlas_evidence), mechanismReferenceLabel(data, item)) {
            source(data.mechanism(item).source)
        }.apply { tag = "atlas-source-physiology" }, 16)
    }
    private fun researchPage(data: HealthBodyAtlas, item: HealthAtlasItem) {
        val topic = requireNotNull(researchTopic)
        researchItem = item.id
        if (topic == HealthAtlasResearchTopic.PHYSIOLOGY) {
            ui.add(content, ui.text(item.name + " · " + item.systems.mapNotNull(data::get).joinToString(" · ") { it.name }, 14f, muted = true))
            simulationItem = item.id
            simulation = HealthAtlasSimulationPanel(this, content, data, item, simulationStates[item.id],
                physiologyStates[item.id], ::zoom, ::source, ::select, mechanismFirst = true)
            addMechanismSource(content, data, item)
        } else if (topic == HealthAtlasResearchTopic.AGING) {
            content.tag = "atlas-research-content"
            aging = HealthAtlasAgingPanel(this, content, data, item, agingSelections[item.id], ::select, ::source)
        } else research = HealthAtlasResearchPanel(this, content, data, item, eliminationStates[item.id], ::select, ::source, drugStates[item.id])
    }
    private fun mechanismReferenceLabel(data: HealthBodyAtlas, item: HealthAtlasItem) = getString(
        if (data.mechanism(item).reference == null) R.string.health_atlas_reference_openstax else R.string.health_atlas_reference_pubmed)
    private fun source(url: String) {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
            .onFailure { Toast.makeText(this, R.string.health_storage_error, Toast.LENGTH_SHORT).show() }
    }
    private fun zoomAnatomy(data: HealthBodyAtlas, currentId: String?, plate: HealthAtlasPlate, title: String) {
        dialog?.dismiss()
        dialog = HealthAtlasAnatomyDialog(this, data, currentId, plate, title, ::select).also(Dialog::show)
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
    private fun ask(item: HealthAtlasItem?) {
        simulation?.pause()
        functionPlayer?.pause()
        val prompt = HealthAtlasAgentContext.prompt(this, atlas!!, item, simulation?.snapshot,
            simulation?.quantitativeSnapshot, researchTopic, research?.elimination, research?.drugState,
            item?.let { artworkViews[it.id] }, aging = aging?.selection, functionPhase = functionPlayer?.phase,
            functionStory = functionPlayer?.story)
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
