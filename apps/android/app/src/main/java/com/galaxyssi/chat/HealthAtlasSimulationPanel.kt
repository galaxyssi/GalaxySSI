package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.os.SystemClock
import android.view.Gravity
import android.view.View
import android.view.animation.LinearInterpolator
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import java.text.NumberFormat

internal class HealthAtlasSimulationPanel(private val activity: Activity, private val body: LinearLayout,
    private val atlas: HealthBodyAtlas, private val item: HealthAtlasItem, initial: HealthAtlasSimulation?,
    quantitativeInitial: HealthAtlasPhysiology?, zoom: (Int, String) -> Unit, source: (String) -> Unit,
    select: (HealthAtlasItem) -> Unit, mechanismFirst: Boolean = false, private val inline: Boolean = false,
    private val onPlay: () -> Unit = {}) {
    private val ui = HealthCenterViews(activity)
    private val mechanism = atlas.mechanism(item)
    private val cardiac = item.id in setOf("heart", "cardio")
    private var values = initial ?: HealthAtlasSimulation.initial(item.id)
    val snapshot get() = values
    private var quantitative: HealthAtlasPhysiologyPanel? = null
    val quantitativeSnapshot get() = quantitative?.model
    private var animator: ValueAnimator? = null
    private val inlineClock = if (inline) HealthAtlasChapterClock(mechanism.stages.size, values.phase) else null
    private val inlineFrame = Runnable { advanceInline() }
    private lateinit var play: ImageButton
    private var stage: TextView? = null
    private var renderedStage = -1
    private lateinit var progress: SeekBar
    private lateinit var output: TextView
    private val circulation = if (HealthAtlasCirculation.supports(item.id)) HealthAtlasCirculationView(activity, mechanism,
        { index -> pause(); setPhase(index / 4f) }, { id -> atlas[id]?.let(select) }) else null
    private val gasExchange = if (HealthAtlasGasExchange.supports(item.id)) HealthAtlasGasExchangeView(activity, mechanism,
        { index -> pause(); setPhase(index / 4f) }, { id -> atlas[id]?.let(select) }) else null
    private val endocrinePath = HealthAtlasEndocrinePath.all[item.id]?.let {
        HealthAtlasEndocrinePathView(activity, atlas, item, it, { index -> pause(); setPhase(index / 4f) }, select)
    }
    private val retinalPath = if (item.id == HealthAtlasRetinaPath.OWNER)
        HealthAtlasRetinaPath(activity, atlas, mechanism, { index -> pause(); setPhase(index / 4f) }, select) else null
    private val germline = if (item.id in HealthAtlasGermline.supported) HealthAtlasGermlineView(activity, item.id) else null
    private val heartValves = if (HealthAtlasValve.supports(item.id)) HealthAtlasValvePanel(activity, atlas, item, select) else null
    private val phagocytosis = if (item.id == HealthAtlasPhagocytosisView.OWNER) HealthAtlasPhagocytosisView(activity, mechanism) else null
    private val granulocyte = HealthAtlasGranulocyte.forId(item.id)?.let { HealthAtlasGranulocyteView(activity, it, mechanism) }
    private val immuneLink = HealthAtlasImmuneLink.forId(item.id)?.let { HealthAtlasImmuneLinkView(activity, it, mechanism) }
    private val bloodDefense = HealthAtlasBloodDefense.forId(item.id)?.let { HealthAtlasBloodDefenseView(activity, it, mechanism) }
    private val sarcomere = if (item.id == HealthAtlasSarcomere.OWNER) HealthAtlasSarcomerePanel(activity, mechanism) else null
    private val podocyte = if (item.id == HealthAtlasPodocyteView.OWNER) HealthAtlasPodocyteView(activity, mechanism) else null
    private val pancreaticRoutes = if (item.id == HealthAtlasPancreaticRoutes.OWNER) HealthAtlasPancreaticRoutes(activity, atlas, select) else null
    private val isletStages = if (item.id == HealthAtlasIsletStages.OWNER) HealthAtlasIsletStages(activity, atlas, select) else null
    private val sweatView = if (item.id == HealthAtlasSweatView.OWNER) HealthAtlasSweatView(activity, mechanism) else null
    private val sectionView = HealthAtlasSectionLesson.forId(item.id)?.let { HealthAtlasSectionLessonView(activity, it, mechanism) }
    private val diagram = circulation ?: gasExchange ?: endocrinePath ?: retinalPath
    private val closeUp = heartValves ?: germline ?: phagocytosis ?: granulocyte ?: immuneLink ?: bloodDefense ?:
        sarcomere ?: podocyte ?: pancreaticRoutes ?: isletStages ?: sweatView ?: sectionView
    private val process = if (diagram == null) {
        HealthAtlasProcessView(activity, mechanism, showLabels = !inline) { index -> pause(); setPhase(index / 4f) }
    } else null
    private val quantitativeAfterArt = mechanismFirst || gasExchange != null || pancreaticRoutes != null || endocrinePath != null ||
        sweatView != null || (sectionView != null && item.kind != HealthAtlasKind.CELL)
    private val resetInputs = arrayListOf<() -> Unit>()
    init {
        fun addQuantitative() {
            HealthAtlasPhysiologyKind.forItem(item.id)?.let { kind ->
                val migrated = if (kind == HealthAtlasPhysiologyKind.VENTILATION && initial != null)
                    HealthAtlasPhysiology.restore(item.id, intArrayOf(initial.first, initial.second, 150)) else null
                quantitative = HealthAtlasPhysiologyPanel(activity, body, kind, quantitativeInitial ?: migrated, source)
            }
        }
        if (!quantitativeAfterArt) addQuantitative()
        val scene = ui.column().apply {
            tag = "atlas-simulation-frame"
            background = ui.background()
            clipToOutline = true
            setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
        }
        ui.add(body, scene)
        val details = if (inline) ui.column().apply {
            visibility = View.GONE
            tag = "atlas-simulation-references"
        } else body
        fun note(res: Int, top: Int = 6, size: Float = 12f): TextView =
            ui.text(activity.getString(res), size, muted = true).also { ui.add(details, it, top) }
        val art = HealthAtlasUi.art(item)
        if (art != null && diagram == null && closeUp == null)
            ui.add(scene, ImageView(activity).apply {
            setImageResource(art); scaleType = ImageView.ScaleType.FIT_CENTER; contentDescription = item.name
            minimumHeight = ui.dp(260); setOnClickListener { zoom(art, item.name) }; tag = "atlas-simulation-art"
            adjustViewBounds = true; maxHeight = ui.dp(280)
        })
        ui.add(scene, ui.text(mechanism.title, 16f, bold = true), 4)
        germline?.let { ui.add(scene, it, 12) }
        if (heartValves != null) ui.add(scene, heartValves, 8)
        if (phagocytosis != null) {
            ui.add(scene, phagocytosis, 8)
            note(R.string.health_atlas_phagocytosis_scope)
        }
        fun addCellScene(view: HealthAtlasCellSceneView, scope: Int, relatedId: String? = null) {
            ui.add(scene, view, 8)
            note(scope)
            relatedId?.let(atlas::get)?.let { related ->
                ui.add(details, HealthAtlasUi.row(activity, related, atlas) { select(related) }
                    .apply { tag = "atlas-immune-related-${related.id}" }, 6)
            }
        }
        granulocyte?.let { addCellScene(it, it.lesson.scope) }
        immuneLink?.let { addCellScene(it, it.lesson.scope, it.lesson.relatedId) }
        bloodDefense?.let { addCellScene(it, it.lesson.scope, it.lesson.relatedId) }
        sarcomere?.let { ui.add(scene, it, 8) }
        podocyte?.let {
            ui.add(scene, it, 8)
            note(R.string.health_atlas_podocyte_scope)
        }
        pancreaticRoutes?.let {
            ui.add(scene, it, 8)
            note(R.string.health_atlas_digestive_routes_scope)
        }
        isletStages?.let {
            ui.add(scene, it, 8)
            note(R.string.health_atlas_digestive_islets_scope)
        }
        sweatView?.let {
            ui.add(scene, it, 8)
            note(R.string.health_atlas_context_sweat_scope)
        }
        sectionView?.let {
            ui.add(scene, it, 8)
            it.lesson.notes.forEach { res -> note(res) }
        }
        if (item.id == "hair-follicles") note(R.string.health_atlas_context_hair_scope)
        val processArt = diagram ?: process
        val processFigure = if (retinalPath == null && endocrinePath == null && processArt != null) {
            processArt.setPadding(processArt.paddingLeft, processArt.paddingTop, processArt.paddingRight,
                processArt.paddingBottom + ui.dp(HealthAtlasFigureFrame.LEGEND_OVERLAP_DP))
            val caption = ui.text("", 15f, bold = true).apply { tag = "atlas-simulation-stage" }
            stage = caption
            HealthAtlasFigureFrame(activity, processArt, "atlas-simulation-figure").apply {
                reserveCaption(caption, mechanism.stages.indices.map(::stageCaption))
                ui.add(legend, caption)
            }
        } else null
        (processFigure ?: processArt)?.let { ui.add(scene, it, 8) }
        if (circulation != null) note(R.string.health_atlas_circuit_scope, 8)
        if (gasExchange != null) note(R.string.health_atlas_gas_scope, 8)
        val controls = ui.line().apply {
            gravity = Gravity.CENTER
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { pause(); setPhase((values.stage - 1).coerceAtLeast(0) / 4f) })
            play = ui.icon(R.drawable.ic_rich_play, R.string.health_body_play) {
                if (animator == null && inlineClock?.playing != true) start() else pause()
            }
                .apply { tag = "atlas-simulation-play" }; addView(play)
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { pause(); setPhase((values.stage + 1).coerceAtMost(3) / 4f) }.apply { rotation = 180f })
            addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
                pause(); values = HealthAtlasSimulation.initial(item.id); resetInputs.forEach { it() }; setPhase(0f); updateOutput(); quantitative?.reset()
            }.apply { tag = "atlas-simulation-reset" })
        }
        val controlsAnchor = if (diagram != null) processFigure ?: diagram else closeUp
        if (controlsAnchor != null && !inline) scene.addView(controls, scene.indexOfChild(controlsAnchor),
            LinearLayout.LayoutParams(-1, -2).apply { topMargin = ui.dp(8) })
        else ui.add(scene, controls, 8)
        progress = SeekBar(activity).apply {
            max = 1000; contentDescription = activity.getString(R.string.health_atlas_phase); tag = "atlas-simulation-progress"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seek: SeekBar?) = pause()
                override fun onStopTrackingTouch(seek: SeekBar?) = Unit
                override fun onProgressChanged(seek: SeekBar?, value: Int, user: Boolean) { if (user) setPhase(value / 1000f) }
            })
        }; ui.add(scene, progress)
        if (pancreaticRoutes != null) ui.add(details, ui.row(activity.getString(R.string.health_atlas_digestive_routes_reference)) {
            source(HealthAtlasPancreaticRoutes.SOURCE)
        }.apply { tag = "atlas-source-pancreatic-routes" }, 8)
        if (retinalPath != null) ui.add(details, ui.row(activity.getString(R.string.health_atlas_sensory_retinal_paper)) {
            source(HealthAtlasRetinaPath.SOURCE)
        }.apply { tag = "atlas-source-retinal-path" }, 8)
        if (quantitativeAfterArt) addQuantitative()
        if (cardiac) {
            output = ui.text("", 28f, bold = true).apply { tag = "atlas-simulation-output" }
            ui.add(body, ui.text(activity.getString(R.string.health_atlas_cardiac_output), 14f, muted = true), 16)
            ui.add(body, output)
            parameter(R.string.health_atlas_heart_rate, 40..160,
                values.first, "bpm", "first") { values = values.copy(first = it); updateOutput() }
            parameter(R.string.health_atlas_stroke_volume, 30..120,
                values.second, "mL", "second") { values = values.copy(second = it); updateOutput() }
            note(R.string.health_atlas_cardiac_formula, 12, 13f)
            updateOutput()
        } else note(when {
            germline != null -> R.string.health_atlas_germline_timing
            quantitative != null -> R.string.health_atlas_model_process_note
            else -> R.string.health_atlas_qualitative_note
        }, 14, 13f)
        if (!inline) parameter(R.string.health_atlas_speed, 1..4, (values.speed * 2).toInt(), "×0.5", "speed") { pause(); values = values.copy(speed = it / 2f) }
        note(R.string.health_atlas_teaching_note, 14)
        if (germline != null) note(R.string.health_atlas_germline_scope, 12).tag = "atlas-germline-scope"
        if (circulation != null) ui.add(details, ui.row(activity.getString(R.string.health_atlas_circuit_reference)) {
            source(HealthAtlasCirculation.SOURCE)
        }.apply { tag = "atlas-source-circulation" }, 12)
        if (gasExchange != null) ui.add(details, ui.row(activity.getString(R.string.health_atlas_gas_reference)) {
            source(HealthAtlasGasExchange.SOURCE)
        }.apply { tag = "atlas-source-gas" }, 12)
        if (germline != null) ui.add(details, ui.row(activity.getString(R.string.health_atlas_germline_source)) {
            source(HealthAtlasGermline.SOURCE)
        }.apply { tag = "atlas-source-germline" }, 12)
        if (inline) {
            val reference = if (mechanism.reference == null) R.string.health_atlas_reference_openstax
                else R.string.health_atlas_reference_pubmed
            ui.add(details, ui.row(activity.getString(reference)) { source(mechanism.source) }
                .apply { tag = "atlas-source-physiology" }, 8)
            ui.add(body, HealthAtlasUi.disclosure(activity, activity.getString(R.string.health_atlas_evidence),
                "atlas-simulation-references-toggle") { details.visibility = if (it) View.VISIBLE else View.GONE }, 8)
            ui.add(body, details)
        }
        setPhase(values.phase)
    }
    private fun stageCaption(index: Int) = activity.getString(
        R.string.health_atlas_stage, index + 1, mechanism.stages.size, mechanism.stages[index])

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
        if (cardiac) circulation?.flowLitresPerMinute = values.cardiacOutput()
    }
    private fun setPhase(value: Float) {
        values = values.copy(phase = value.coerceIn(0f, 1f))
        circulation?.phase = values.phase; gasExchange?.phase = values.phase; process?.phase = values.phase
        germline?.stage = values.stage
        heartValves?.stage = values.stage
        phagocytosis?.phase = values.phase
        granulocyte?.phase = values.phase
        immuneLink?.phase = values.phase
        bloodDefense?.phase = values.phase
        sarcomere?.stage = values.stage
        podocyte?.stage = values.stage
        if (pancreaticRoutes?.stage != values.stage) pancreaticRoutes?.stage = values.stage
        if (isletStages?.stage != values.stage) isletStages?.stage = values.stage
        if (endocrinePath?.stage != values.stage) endocrinePath?.stage = values.stage
        if (retinalPath?.stage != values.stage) retinalPath?.stage = values.stage
        sweatView?.phase = values.phase
        sectionView?.phase = values.phase
        if (renderedStage != values.stage) {
            renderedStage = values.stage
            stage?.text = stageCaption(values.stage)
        }
        if (::progress.isInitialized) progress.progress = (values.phase * 1000).toInt()
    }
    private fun start() {
        val clock = inlineClock
        if (clock != null) {
            onPlay()
            clock.seek(values.phase)
            clock.resume(SystemClock.uptimeMillis())
            advanceInline()
            return
        }
        if (!ValueAnimator.areAnimatorsEnabled()) { setPhase((values.stage + 1).coerceAtMost(3) / 4f); return }
        onPlay()
        if (values.phase >= 1f) setPhase(0f)
        animator = ValueAnimator.ofFloat(values.phase, 1f).apply {
            val lessonMs = 8_000.0 / this@HealthAtlasSimulationPanel.values.speed
            duration = ((1f - this@HealthAtlasSimulationPanel.values.phase) * lessonMs).toLong().coerceAtLeast(1)
            interpolator = LinearInterpolator(); addUpdateListener { setPhase(it.animatedValue as Float); if (this@HealthAtlasSimulationPanel.values.phase >= 1f) pause() }
            start()
        }
        showPlaying(true)
    }
    private fun advanceInline() {
        val now = SystemClock.uptimeMillis()
        val clock = requireNotNull(inlineClock)
        setPhase(clock.sample(now))
        showPlaying(clock.playing)
        if (clock.playing) {
            if (ValueAnimator.areAnimatorsEnabled()) play.postOnAnimation(inlineFrame)
            else play.postDelayed(inlineFrame, clock.nextStepIn(now))
        }
    }
    private fun showPlaying(playing: Boolean) {
        if (!::play.isInitialized) return
        val label = activity.getString(if (playing) R.string.health_body_pause else R.string.health_body_play)
        if (play.contentDescription == label) return
        play.setImageResource(if (playing) R.drawable.ic_rich_pause else R.drawable.ic_rich_play)
        play.contentDescription = label; play.tooltipText = label
    }
    fun pause() {
        animator?.removeAllUpdateListeners(); animator?.cancel(); animator = null
        if (inlineClock?.playing == true) {
            play.removeCallbacks(inlineFrame)
            inlineClock.pause(SystemClock.uptimeMillis())
            advanceInline()
        }
        showPlaying(false)
    }
}
