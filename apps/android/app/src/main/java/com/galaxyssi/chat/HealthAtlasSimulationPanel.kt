package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.view.Gravity
import android.view.animation.LinearInterpolator
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import java.text.NumberFormat

internal class HealthAtlasSimulationPanel(private val activity: Activity, private val body: LinearLayout,
    private val atlas: HealthBodyAtlas, private val item: HealthAtlasItem, initial: HealthAtlasSimulation?,
    quantitativeInitial: HealthAtlasPhysiology?, zoom: (Int, String) -> Unit, source: (String) -> Unit) {
    private val ui = HealthCenterViews(activity)
    private val mechanism = atlas.mechanism(item)
    private val cardiac = item.id in setOf("heart", "cardio")
    private var values = initial ?: HealthAtlasSimulation.initial(item.id)
    val snapshot get() = values
    private var quantitative: HealthAtlasPhysiologyPanel? = null
    val quantitativeSnapshot get() = quantitative?.model
    private var animator: ValueAnimator? = null
    private lateinit var play: ImageButton
    private lateinit var stage: TextView
    private lateinit var progress: SeekBar
    private lateinit var output: TextView
    private var diagram = HealthAtlasProcessView(activity, mechanism)
    private val resetInputs = arrayListOf<() -> Unit>()
    init {
        HealthAtlasPhysiologyKind.forItem(item.id)?.let { kind ->
            val migrated = if (kind == HealthAtlasPhysiologyKind.VENTILATION && initial != null)
                HealthAtlasPhysiology.restore(item.id, intArrayOf(initial.first, initial.second, 150)) else null
            quantitative = HealthAtlasPhysiologyPanel(activity, body, kind, quantitativeInitial ?: migrated, source)
        }
        val art = HealthAtlasUi.art(item)
        if (art != null) ui.add(body, ImageView(activity).apply {
            setImageResource(art); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = item.name
            minimumHeight = ui.dp(260); setOnClickListener { zoom(art, item.name) }; tag = "atlas-simulation-art"
            adjustViewBounds = true; maxHeight = ui.dp(280)
        })
        ui.add(body, ui.text(mechanism.title, 18f, bold = true), 14)
        body.addView(diagram, LinearLayout.LayoutParams(-1, -2))
        stage = ui.text("", 15f, bold = true).apply { tag = "atlas-simulation-stage" }; ui.add(body, stage)
        val controls = ui.line().apply {
            gravity = Gravity.CENTER
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { pause(); setPhase((values.stage - 1).coerceAtLeast(0) / 4f) })
            play = ui.icon(R.drawable.ic_rich_play, R.string.health_body_play) { if (animator == null) start() else pause() }
                .apply { tag = "atlas-simulation-play" }; addView(play)
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { pause(); setPhase((values.stage + 1).coerceAtMost(3) / 4f) }.apply { rotation = 180f })
            addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
                pause(); values = HealthAtlasSimulation.initial(item.id); resetInputs.forEach { it() }; setPhase(0f); updateOutput(); quantitative?.reset()
            }.apply { tag = "atlas-simulation-reset" })
        }; ui.add(body, controls, 8)
        progress = SeekBar(activity).apply {
            max = 1000; contentDescription = activity.getString(R.string.health_atlas_phase); tag = "atlas-simulation-progress"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seek: SeekBar?) = pause()
                override fun onStopTrackingTouch(seek: SeekBar?) = Unit
                override fun onProgressChanged(seek: SeekBar?, value: Int, user: Boolean) { if (user) setPhase(value / 1000f) }
            })
        }; ui.add(body, progress)
        if (cardiac) {
            output = ui.text("", 28f, bold = true).apply { tag = "atlas-simulation-output" }
            ui.add(body, ui.text(activity.getString(R.string.health_atlas_cardiac_output), 14f, muted = true), 16)
            ui.add(body, output)
            parameter(R.string.health_atlas_heart_rate, 40..160,
                values.first, "bpm", "first") { values = values.copy(first = it); updateOutput() }
            parameter(R.string.health_atlas_stroke_volume, 30..120,
                values.second, "mL", "second") { values = values.copy(second = it); updateOutput() }
            ui.add(body, ui.text(activity.getString(R.string.health_atlas_cardiac_formula), 13f, muted = true), 12)
            updateOutput()
        } else ui.add(body, ui.text(activity.getString(R.string.health_atlas_qualitative_note), 13f, muted = true), 14)
        parameter(R.string.health_atlas_speed, 1..4, (values.speed * 2).toInt(), "×0.5", "speed") { pause(); values = values.copy(speed = it / 2f) }
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_teaching_note), 12f, muted = true), 14)
        setPhase(values.phase)
    }
    private fun parameter(label: Int, range: IntRange, initial: Int, unit: String, key: String, changed: (Int) -> Unit) {
        fun labelText(value: Int) = activity.getString(label) + "  " + if (key == "speed")
            NumberFormat.getNumberInstance().format(value / 2.0) + "\u00d7" else "$value $unit"
        val caption = ui.text(labelText(initial), 14f)
        ui.add(body, caption, 16)
        val seek = SeekBar(activity).apply {
            max = range.last - range.first; progress = initial - range.first; contentDescription = activity.getString(label); tag = "atlas-parameter-$key"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seek: SeekBar?) = Unit
                override fun onStopTrackingTouch(seek: SeekBar?) = Unit
                override fun onProgressChanged(seek: SeekBar?, value: Int, user: Boolean) {
                    val number = value + range.first; caption.text = labelText(number); changed(number)
                }
            })
        }; ui.add(body, seek)
        val defaults = HealthAtlasSimulation.initial(item.id)
        val resetValue = when (key) { "first" -> defaults.first; "second" -> defaults.second; "speed" -> 2; else -> initial }
        resetInputs += { seek.progress = resetValue - range.first }
    }
    private fun updateOutput() {
        if (::output.isInitialized) output.text = NumberFormat.getNumberInstance().apply { minimumFractionDigits = 2; maximumFractionDigits = 2 }
            .format(values.cardiacOutput()) + " L/min"
    }
    private fun setPhase(value: Float) {
        values = values.copy(phase = value.coerceIn(0f, 1f)); diagram.phase = values.phase
        stage.text = activity.getString(R.string.health_atlas_stage, values.stage + 1, mechanism.stages.size, mechanism.stages[values.stage])
        if (::progress.isInitialized) progress.progress = (values.phase * 1000).toInt()
    }
    private fun start() {
        if (!ValueAnimator.areAnimatorsEnabled()) { setPhase((values.stage + 1).coerceAtMost(3) / 4f); return }
        if (values.phase >= 1f) setPhase(0f)
        animator = ValueAnimator.ofFloat(values.phase, 1f).apply {
            duration = ((1f - this@HealthAtlasSimulationPanel.values.phase) * 8000 / this@HealthAtlasSimulationPanel.values.speed).toLong().coerceAtLeast(1)
            interpolator = LinearInterpolator(); addUpdateListener { setPhase(it.animatedValue as Float); if (this@HealthAtlasSimulationPanel.values.phase >= 1f) pause() }
            start()
        }
        play.setImageResource(R.drawable.ic_rich_pause); play.contentDescription = activity.getString(R.string.health_body_pause)
    }
    fun pause() { animator?.removeAllUpdateListeners(); animator?.cancel(); animator = null
        if (::play.isInitialized) { play.setImageResource(R.drawable.ic_rich_play); play.contentDescription = activity.getString(R.string.health_body_play) } }
}
