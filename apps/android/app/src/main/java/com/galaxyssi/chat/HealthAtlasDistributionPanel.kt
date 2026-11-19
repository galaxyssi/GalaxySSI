package com.galaxyssi.chat

import android.app.Activity
import android.widget.LinearLayout
import android.widget.SeekBar

internal class HealthAtlasDistributionPanel(private val activity: Activity, private val body: LinearLayout,
    initial: HealthAtlasDistribution, private val changed: (HealthAtlasDistribution) -> Unit, source: (String) -> Unit) {
    private val ui = HealthCenterViews(activity)
    var model = initial
        private set
    private val diagram = HealthAtlasDistributionDiagram(activity)
    private val chart = HealthAtlasDistributionChart(activity)
    private val summary = ui.text("", 14f).apply { tag = "atlas-distribution-summary" }
    private val resets = arrayListOf<() -> Unit>()
    init {
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_model_synthetic), 13f, muted = true)
            .apply { tag = "atlas-distribution-teaching" }, 10)
        ui.add(body, diagram, 12)
        ui.add(body, summary, 8)
        ui.add(body, chart, 8)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_hours_axis), 12f, muted = true))
        listOf(R.string.health_atlas_distribution_legend_central, R.string.health_atlas_distribution_legend_peripheral,
            R.string.health_atlas_distribution_legend_eliminated).forEachIndexed { i, label ->
            ui.add(body, ui.text(activity.getString(label), 12f).apply { setTextColor(activity.getColor(HealthAtlasDistributionText.colors[i])) }, 4)
        }
        parameter(R.string.health_atlas_elapsed, "elapsed", 192, initial.quarterHours, 16, true) { model = model.copy(quarterHours = it) }
        parameter(R.string.health_atlas_distribution_outward, "outward", 300, initial.outward, 30) { model = model.copy(outward = it) }
        parameter(R.string.health_atlas_distribution_return, "return", 300, initial.returning, 15) { model = model.copy(returning = it) }
        parameter(R.string.health_atlas_distribution_loss, "loss", 300, initial.elimination, 10) { model = model.copy(elimination = it) }
        ui.add(body, ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
            resets.forEach { it() }; model = HealthAtlasDistribution(); update()
        }.apply { tag = "atlas-distribution-reset" }, 8)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_distribution_scope), 13f, muted = true), 12)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_distribution_formula), 13f, muted = true), 12)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_distribution_boundary), 13f, muted = true), 12)
        ui.add(body, ui.row(activity.getString(R.string.health_atlas_distribution_reference)) { source(HealthAtlasDistribution.SOURCE) }
            .apply { tag = "atlas-source-distribution" }, 12)
        update()
    }
    private fun update() { diagram.model = model; chart.model = model; summary.text = HealthAtlasDistributionText.summary(activity, model); changed(model) }
    private fun parameter(title: Int, key: String, maximum: Int, initial: Int, default: Int, time: Boolean = false, set: (Int) -> Unit) {
        fun text(value: Int): String {
            val number = HealthAtlasPhysiologyText.number(value / if (time) 4.0 else 100.0)
            return if (time) activity.getString(R.string.health_atlas_distribution_time, number)
            else activity.getString(R.string.health_atlas_distribution_rate, activity.getString(title), number)
        }
        val label = ui.text(text(initial), 14f).apply { tag = "atlas-distribution-label-$key" }
        ui.add(body, label, 16)
        val seek = SeekBar(activity).apply {
            tag = "atlas-distribution-$key"; contentDescription = text(initial)
            max = maximum; progress = initial
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(bar: SeekBar?) = Unit
                override fun onStopTrackingTouch(bar: SeekBar?) = Unit
                override fun onProgressChanged(bar: SeekBar?, value: Int, user: Boolean) {
                    set(value); label.text = text(value); bar?.contentDescription = text(value); update()
                }
            })
        }
        ui.add(body, seek); resets += { seek.progress = default }
    }
}
