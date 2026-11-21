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
    private val chart = HealthAtlasPhysiologyChart(activity, model).apply { tag = "atlas-physiology-curve" }
    private val renalBalance = if (kind == HealthAtlasPhysiologyKind.RENAL_EXCRETION) HealthAtlasRenalBalanceView(activity) else null
    private val elbowBalance = if (kind == HealthAtlasPhysiologyKind.ELBOW_BALANCE) HealthAtlasElbowView(activity) else null
    private val vesselFlow = if (kind == HealthAtlasPhysiologyKind.VESSEL_FLOW) HealthAtlasVesselFlowView(activity) else null
    private val eyeOptics = if (kind == HealthAtlasPhysiologyKind.EYE_FOCUS) HealthAtlasEyeOpticsView(activity) else null
    private val middleEar = if (kind == HealthAtlasPhysiologyKind.MIDDLE_EAR) HealthAtlasMiddleEarView(activity) else null
    private val alveolar = if (kind == HealthAtlasPhysiologyKind.ALVEOLAR_SURFACE) HealthAtlasAlveolarSurfaceView(activity) else null
    private val villus = if (kind == HealthAtlasPhysiologyKind.VILLUS_AREA) HealthAtlasVillusAreaView(activity) else null
    private val materialResponse = when (kind) {
        HealthAtlasPhysiologyKind.ALVEOLAR_DIFFUSION, HealthAtlasPhysiologyKind.CARTILAGE_COMPRESSION,
        HealthAtlasPhysiologyKind.BONE_BENDING, HealthAtlasPhysiologyKind.CALF_PUMP,
        HealthAtlasPhysiologyKind.PELVIC_SUPPORT, HealthAtlasPhysiologyKind.CUSHION_CONTACT_PRESSURE,
        HealthAtlasPhysiologyKind.DIAPHRAGM_DISPLACEMENT ->
            HealthAtlasMaterialResponseView(activity, model)
        else -> null
    }
    init {
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.title(kind)), 19f, bold = true), 12)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_model_synthetic), 12f, muted = true), 4)
        ui.add(body, output, 8); ui.add(body, companion, 4)
        renalBalance?.let { ui.add(body, it, 12) }
        elbowBalance?.let { ui.add(body, it, 12) }
        vesselFlow?.let { ui.add(body, it, 12) }
        eyeOptics?.let { ui.add(body, it, 12) }
        middleEar?.let { ui.add(body, it, 12) }
        alveolar?.let { ui.add(body, it, 12) }
        villus?.let {
            ui.add(body, it, 8)
            ui.add(body, ui.text(activity.getString(R.string.health_atlas_gut_section_area_views), 12f, muted = true), 4)
        }
        materialResponse?.let {
            ui.add(body, it, 8)
            ui.add(body, ui.text(activity.getString(it.diagramDescription), 12f, muted = true), 4)
        }
        val axisKey = kind.inputs[kind.axis].key
        fun addChart() {
            ui.add(body, chart, 12)
            val axisLabel = activity.getString(HealthAtlasPhysiologyText.label(axisKey))
            val unit = HealthAtlasPhysiologyText.displayUnit(activity, HealthAtlasPhysiologyText.unit(axisKey))
            ui.add(body, ui.text(if (unit.isEmpty()) axisLabel else
                activity.getString(R.string.health_atlas_model_axis, axisLabel, unit), 12f, muted = true))
        }
        val controlsFirst = alveolar != null || villus != null || materialResponse != null ||
            kind == HealthAtlasPhysiologyKind.PHOTON_CAPTURE
        if (!controlsFirst) addChart()
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
        if (controlsFirst) addChart()
        if (eyeOptics != null) ui.add(body, ui.command(R.string.health_atlas_eye_match_plane) {
            val index = model.kind.axis
            val targetSteps = requireNotNull(model.eyeOptics).targetPowerSteps
            controls[index].first.progress = targetSteps - model.kind.inputs[index].range.first
        }.apply { tag = "atlas-eye-match-plane" }, 12)
        body.addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) { reset() }
            .apply { tag = "atlas-physiology-reset" }, LinearLayout.LayoutParams(ui.dp(48), ui.dp(48)).apply { topMargin = ui.dp(8) })
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.formula(kind)), 14f), 8)
        ui.add(body, ui.text(activity.getString(HealthAtlasPhysiologyText.scope(kind)), 13f, muted = true), 8)
        kind.sources.forEachIndexed { index, url ->
            ui.add(body, ui.row(activity.getString(HealthAtlasPhysiologyText.sourceTitle(kind, index))) { source(url) }
                .apply { tag = if (index == 0) "atlas-physiology-source" else "atlas-physiology-source-$index" }, 12)
        }
        update()
    }
    fun reset() {
        model = HealthAtlasPhysiology(model.kind)
        controls.forEachIndexed { index, (seek, _) -> seek.progress = model.inputs[index] - model.kind.inputs[index].range.first }
        update()
    }
    private fun update() {
        output.text = HealthAtlasPhysiologyText.resultNumber(model, model.result) + " " +
            HealthAtlasPhysiologyText.displayUnit(activity, model.kind.unit)
        companion.text = HealthAtlasPhysiologyText.companion(activity, model)
        chart.model = model
        model.renalAmounts?.let { renalBalance?.amounts = it }
        model.elbowForces?.let { elbowBalance?.forces = it }
        model.vesselFlow?.let { vesselFlow?.flow = it }
        model.eyeOptics?.let { eyeOptics?.eye = it }
        model.middleEar?.let { middleEar?.model = it }
        alveolar?.model = model
        villus?.model = model
        materialResponse?.model = model
        controls.forEachIndexed { index, (_, label) -> label.text = HealthAtlasPhysiologyText.input(activity, model, index) }
    }
}
