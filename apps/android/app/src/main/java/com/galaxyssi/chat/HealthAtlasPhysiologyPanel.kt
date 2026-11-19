package com.galaxyssi.chat

import android.app.Activity
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView

internal class HealthAtlasPhysiologyPanel(private val activity: Activity, private val body: LinearLayout,
    kind: HealthAtlasPhysiologyKind, initial: HealthAtlasPhysiology?, source: (String) -> Unit) {
    private val ui = HealthCenterViews(activity)
    var model = initial?.takeIf { it.kind == kind } ?: HealthAtlasPhysiology(kind)
        private set
    private val controls = arrayListOf<Pair<SeekBar, TextView>>()
    private val output = ui.text("", 26f, bold = true).apply { tag = "atlas-physiology-output" }
    private val companion = ui.text("", 14f, muted = true).apply { tag = "atlas-physiology-companion" }
    private val chart = HealthAtlasPhysiologyChart(activity, model)
    init {
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.title(kind)), 19f, bold = true), 12)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_model_synthetic), 12f, muted = true), 4)
        ui.add(body, output, 8); ui.add(body, companion, 4)
        ui.add(body, chart, 12)
        val axisKey = kind.inputs[kind.axis].key
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_model_axis,
            activity.getString(HealthAtlasPhysiologyText.label(axisKey)), HealthAtlasPhysiologyText.unit(axisKey)), 12f, muted = true))
        kind.inputs.forEachIndexed { index, input ->
            val caption = ui.text("", 14f).apply { tag = "atlas-physiology-label-${input.key}" }
            ui.add(body, caption, 14)
            val seek = SeekBar(activity).apply {
                tag = "atlas-physiology-${input.key}"; isSaveEnabled = false
                max = input.range.last - input.range.first; progress = model.inputs[index] - input.range.first
                contentDescription = activity.getString(HealthAtlasPhysiologyText.label(input.key))
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onStartTrackingTouch(bar: SeekBar?) = Unit
                    override fun onStopTrackingTouch(bar: SeekBar?) = Unit
                    override fun onProgressChanged(bar: SeekBar?, progress: Int, user: Boolean) {
                        model = model.withInput(index, progress + input.range.first); update()
                    }
                })
            }
            controls += seek to caption
            ui.add(body, seek)
        }
        body.addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) { reset() }
            .apply { tag = "atlas-physiology-reset" }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)).apply { topMargin = ui.dp(8) })
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.formula(kind)), 14f), 8)
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.scope(kind)), 13f, muted = true), 8)
        ui.add(body, ui.row(activity.getString(R.string.health_atlas_model_source)) { source(kind.source) }
            .apply { tag = "atlas-physiology-source" }, 12)
        update()
    }
    fun reset() {
        model = HealthAtlasPhysiology(model.kind)
        controls.forEachIndexed { index, (seek, _) -> seek.progress = model.inputs[index] - model.kind.inputs[index].range.first }
        update()
    }
    private fun update() {
        output.text = HealthAtlasPhysiologyText.number(model.result) + " " + model.kind.unit
        companion.text = HealthAtlasPhysiologyText.companion(activity, model)
        chart.model = model
        controls.forEachIndexed { index, (_, label) -> label.text = HealthAtlasPhysiologyText.input(activity, model, index) }
    }
}
