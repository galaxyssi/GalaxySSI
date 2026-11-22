package com.galaxyssi.chat

import android.app.Activity
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import java.text.NumberFormat

/** Public reading and teaching controls. This surface never opens a health database. */
internal class HealthAtlasResearchPanel(
    private val activity: Activity, private val body: LinearLayout, private val atlas: HealthBodyAtlas,
    private val item: HealthAtlasItem, initial: HealthAtlasElimination?,
    private val select: (HealthAtlasItem) -> Unit, private val source: (String) -> Unit, drugInitial: HealthAtlasDrugState? = null,
) {
    private val ui = HealthCenterViews(activity)
    var elimination = initial ?: HealthAtlasElimination()
        private set
    var drugState = drugInitial ?: HealthAtlasDrugState()
        private set
    private val resetInputs = arrayListOf<() -> Unit>()
    private lateinit var modelBody: LinearLayout
    init {
        body.tag = "atlas-research-content"
        ui.add(body, ui.text(item.name, 18f, bold = true), 8)
        ui.add(body, ui.text(item.description, 15f), 8)
        drugs()
    }
    private fun heading(title: Int) = ui.add(body, ui.text(activity.getString(title), 18f, bold = true), 24)
    private fun note(text: Int) = ui.add(body, ui.text(activity.getString(text), 13f, muted = true), 10)
    private fun sourceRow(title: Int, url: String, key: String) {
        ui.add(body, ui.row(activity.getString(title)) { source(url) }.apply { tag = "atlas-source-$key" }, 8)
    }
    private fun drugs() {
        heading(R.string.health_atlas_adme_title)
        note(R.string.health_atlas_adme_scope)
        val stages = listOf(R.string.health_atlas_absorption, R.string.health_atlas_distribution,
            R.string.health_atlas_metabolism, R.string.health_atlas_excretion)
        val model = HealthAtlasMechanism("adme", "teaching", activity.getString(R.string.health_atlas_adme_title),
            stages.map(activity::getString), "")
        body.addView(HealthAtlasProcessView(activity, model).apply { phase = 1f }, LinearLayout.LayoutParams(-1, -2))
        val structures = listOf("small-intestine", "blood-vessels", "liver", "kidneys")
        val descriptions = listOf(R.string.health_atlas_absorption_note, R.string.health_atlas_distribution_note,
            R.string.health_atlas_metabolism_note, R.string.health_atlas_excretion_note)
        structures.forEachIndexed { index, id ->
            val structure = requireNotNull(atlas[id])
            ui.add(body, ui.row(activity.getString(stages[index]) + " · " + structure.name,
                activity.getString(descriptions[index])) { select(structure) }.apply { tag = "atlas-adme-$id" }, 8)
        }
        heading(R.string.health_atlas_drug_models)
        val choice = ui.column()
        ui.add(body, choice, 8)
        modelBody = ui.column(); ui.add(body, modelBody)
        fun renderModel() {
            choice.removeAllViews(); modelBody.removeAllViews(); resetInputs.clear()
            choice.addView(HealthAtlasUi.tabs(activity, listOf(R.string.health_atlas_drug_single, R.string.health_atlas_drug_two,
                R.string.health_atlas_compare_title),
                drugState.mode.ordinal, "atlas-drug-model") { index ->
                drugState = drugState.copy(mode = HealthAtlasDrugMode.entries[index]); renderModel()
            })
            when (drugState.mode) {
                HealthAtlasDrugMode.SINGLE -> singleCompartment()
                HealthAtlasDrugMode.TWO -> HealthAtlasDistributionPanel(activity, modelBody, drugState.distribution,
                    { drugState = drugState.copy(distribution = it) }, source)
                HealthAtlasDrugMode.COMPARISON -> HealthAtlasComparisonPanel(activity, modelBody, drugState.comparison,
                    drugState.showComparisonTotals,
                    { model, totals -> drugState = drugState.copy(comparison = model, showComparisonTotals = totals) }, source)
            }
        }
        renderModel()
        heading(R.string.health_atlas_evidence)
        sourceRow(R.string.health_atlas_pharmacology_source, HealthAtlasResearchSources.PHARMACOLOGY, "pharmacology")
        sourceRow(R.string.health_atlas_kinetics_source, HealthAtlasResearchSources.KINETICS, "kinetics")
    }
    private fun singleCompartment() {
        val body = modelBody
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_elimination_assumptions), 13f, muted = true), 10)
        val output = ui.text("", 24f, bold = true).apply { tag = "atlas-elimination-output" }
        ui.add(body, output, 12)
        val summary = ui.text("", 13f, muted = true).apply { tag = "atlas-elimination-summary" }
        ui.add(body, summary, 4)
        val chart = HealthAtlasEliminationChart(activity)
        body.addView(chart, LinearLayout.LayoutParams(-1, -2))
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_hours_axis), 12f, muted = true))
        fun update() {
            val percentage = NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }.format(elimination.percent)
            output.text = activity.getString(R.string.health_atlas_remaining_percent, percentage)
            summary.text = activity.getString(R.string.health_atlas_elimination_summary, elimination.halfLifeHours, elimination.elapsedHours, percentage)
            chart.model = elimination
        }
        parameter(R.string.health_atlas_half_life, 1..24, elimination.halfLifeHours, 4, "half-life") {
            elimination = elimination.copy(halfLifeHours = it); update()
        }
        parameter(R.string.health_atlas_elapsed, 0..48, elimination.elapsedHours, 8, "elapsed") {
            elimination = elimination.copy(elapsedHours = it); update()
        }
        ui.add(body, ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
            elimination = HealthAtlasElimination(); resetInputs.forEach { it() }; update()
        }.apply { tag = "atlas-elimination-reset" }, 8)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_elimination_formula), 13f, muted = true), 10)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_drug_note), 13f, muted = true), 10)
        update()
    }
    private fun parameter(title: Int, range: IntRange, initial: Int, default: Int, key: String, changed: (Int) -> Unit) {
        val body = modelBody
        fun label(value: Int) = activity.getString(R.string.health_atlas_hours_value, activity.getString(title), value)
        val caption = ui.text(label(initial), 14f)
        ui.add(body, caption, 16)
        val seek = SeekBar(activity).apply {
            tag = "atlas-elimination-$key"; contentDescription = activity.getString(title)
            max = range.last - range.first; progress = initial - range.first
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar: SeekBar?) = Unit
                override fun onStopTrackingTouch(bar: SeekBar?) = Unit
                override fun onProgressChanged(bar: SeekBar?, value: Int, user: Boolean) {
                    caption.text = label(value + range.first); changed(value + range.first)
                }
            })
        }
        ui.add(body, seek)
        resetInputs += { seek.progress = default - range.first }
    }
}
