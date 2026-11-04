package com.galaxyssi.chat

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.app.Dialog
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast
import java.text.NumberFormat

class HealthBodyExplorationActivity : Activity() {
    private enum class Screen { OVERVIEW, LESSON, REFERENCE, EXPERIMENT }
    private val ui by lazy { HealthCenterViews(this) }
    private val dark get() = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
    private val softGreen get() = if (dark) 0xff213e34.toInt() else 0xffe6f5ec.toInt()
    private val strongGreen get() = if (dark) 0xff94dfbe.toInt() else 0xff146544.toInt()
    private val neutral get() = getColor(R.color.surface_bg)
    private val ink get() = getColor(R.color.text_primary)
    private val muted get() = if (dark) 0xffb9c5bf.toInt() else 0xff5b6c63.toInt()
    private val hairline get() = getColor(R.color.separator)
    private lateinit var body: LinearLayout
    private var screen = Screen.OVERVIEW
    private var referenceBack = Screen.OVERVIEW
    private var topic = HealthBodyTopic.CIRCULATION
    private var layer = HealthBodyLayer.ORGAN
    private var modal: Dialog? = null
    private var scroll: ScrollView? = null
    private var homeScroll = 0
    private var slow = false
    private var position = 0f
    private var animator: ValueAnimator? = null
    private var diagram: HealthBodyDiagram? = null
    private var play: ImageButton? = null
    private var before: ImageButton? = null
    private var after: ImageButton? = null
    private var phaseTitle: TextView? = null
    private var phaseDetail: TextView? = null
    private var lastPhase = -1
    private var experiment = HealthBodyPumpExperiment()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        screen = Screen.entries.firstOrNull { it.name == state?.getString("screen") } ?: Screen.OVERVIEW
        referenceBack = if (state?.getBoolean("reference_from_lesson") == true) Screen.LESSON else Screen.OVERVIEW
        topic = HealthBodyTopic.entries.firstOrNull { it.name == state?.getString("topic") } ?: HealthBodyTopic.CIRCULATION
        layer = HealthBodyLayer.entries.firstOrNull { it.name == state?.getString("layer") } ?: HealthBodyLayer.ORGAN
        homeScroll = state?.getInt("home_scroll") ?: 0
        position = state?.getFloat("position") ?: 0f
        slow = state?.getBoolean("slow") ?: false
        experiment = HealthBodyPumpExperiment(
            state?.getInt("beats", 75)?.coerceIn(HealthBodyPumpExperiment.BEATS) ?: 75,
            state?.getInt("stroke", 60)?.coerceIn(HealthBodyPumpExperiment.STROKE_ML) ?: 60
        )
        body = healthProfileBody(R.string.health_body_title) { back() }
        render()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("screen", screen.name)
        outState.putBoolean("reference_from_lesson", referenceBack == Screen.LESSON)
        outState.putString("topic", topic.name)
        outState.putString("layer", layer.name)
        outState.putInt("home_scroll", if (screen == Screen.OVERVIEW) scroll?.scrollY ?: 0 else homeScroll)
        outState.putFloat("position", position)
        outState.putBoolean("slow", slow)
        outState.putInt("beats", experiment.beats)
        outState.putInt("stroke", experiment.strokeMl)
    }

    override fun onStop() {
        pause()
        modal?.dismiss()
        modal = null
        super.onStop()
    }

    @Deprecated("Native back callback")
    override fun onBackPressed() = back()

    private fun back() {
        when (screen) {
            Screen.OVERVIEW -> finish()
            Screen.LESSON -> open(Screen.OVERVIEW)
            Screen.REFERENCE -> open(referenceBack)
            Screen.EXPERIMENT -> open(Screen.LESSON)
        }
    }

    private fun open(next: Screen) {
        if (screen == Screen.OVERVIEW) homeScroll = scroll?.scrollY ?: 0
        if (next == Screen.REFERENCE) referenceBack = screen
        pause()
        screen = next
        render()
    }

    private fun render() {
        diagram = null
        play = null
        before = null
        after = null
        phaseTitle = null
        phaseDetail = null
        lastPhase = -1
        body.removeAllViews()
        val page = object : LinearLayout(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val max = minOf(MeasureSpec.getSize(widthMeasureSpec), ui.dp(600))
                super.onMeasure(MeasureSpec.makeMeasureSpec(max, MeasureSpec.EXACTLY), heightMeasureSpec)
            }
        }.apply {
            orientation = LinearLayout.VERTICAL
            setPadding(ui.dp(16), ui.dp(14), ui.dp(16), ui.dp(24))
        }
        val scroller = ScrollView(this).apply {
            isFillViewport = true
            addView(page, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER_HORIZONTAL))
        }
        scroll = scroller
        body.addView(scroller, LinearLayout.LayoutParams(-1, 0, 1f))
        when (screen) {
            Screen.OVERVIEW -> {
                overview(page)
                scroller.post { if (scroll === scroller) scroller.scrollTo(0, homeScroll) }
            }
            Screen.LESSON -> lessonPage(page)
            Screen.REFERENCE -> referencePage(page)
            Screen.EXPERIMENT -> experimentPage(page)
        }
    }

    private fun overview(page: LinearLayout) {
        page.addView(ui.text(getString(R.string.health_body_heading), 24f, bold = true))
        ui.add(page, ui.text(getString(R.string.health_body_subtitle), 14f).apply { setTextColor(muted) }, 4)
        val panel = ui.column()
        val layerButtons = linkedMapOf<HealthBodyLayer, TextView>()
        val topicButtons = linkedMapOf<HealthBodyTopic, TextView>()
        lateinit var more: TextView
        fun update() {
            layerButtons.forEach { (value, view) -> styleChoice(view, value == layer, rail = true) }
            topicButtons.forEach { (value, view) -> styleChoice(view, value == topic) }
            more.setText(if (topic.ordinal >= 4) topic.label else R.string.health_body_more)
            styleChoice(more, topic.ordinal >= 4)
            panel.removeAllViews()
            overviewContent(panel)
        }
        val hero = object : FrameLayout(this) {
            override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                val w = MeasureSpec.getSize(widthMeasureSpec)
                val h = (w * .84f).toInt().coerceIn(ui.dp(252), ui.dp(332))
                super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
            }
        }.apply {
            background = ui.background(0xffe7f6ee.toInt(), radius = 8)
            clipToOutline = true
            tag = "health-body-hero"
            addView(conceptImage(), FrameLayout.LayoutParams(-1, -1))
            val rail = ui.column().apply {
                for (level in HealthBodyLayer.entries) {
                    val chip = choice(level.label, "health-body-layer-${level.name}") {
                        if (layer != level) { layer = level; update() }
                    }
                    layerButtons[level] = chip
                    addView(chip, LinearLayout.LayoutParams(ui.dp(74), ui.dp(44)).apply { bottomMargin = ui.dp(5) })
                }
            }
            addView(rail, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.START).apply {
                topMargin = ui.dp(10); marginStart = ui.dp(10)
            })
            addView(ui.icon(R.drawable.ic_screen_assistant_expand, R.string.health_body_zoom) { zoom() }.apply {
                tag = "health-body-zoom"
                background = ui.background(0xfffcfffd.toInt(), radius = 8)
                imageTintList = android.content.res.ColorStateList.valueOf(0xff31604a.toInt())
            }, FrameLayout.LayoutParams(ui.dp(48), ui.dp(48), Gravity.BOTTOM or Gravity.END).apply {
                marginEnd = ui.dp(10); bottomMargin = ui.dp(10)
            })
        }
        ui.add(page, hero, 14)
        val tabs = ui.line().apply {
            for (value in HealthBodyTopic.entries.take(4)) {
                val button = choice(value.label, "health-body-topic-${value.name}") {
                    if (topic != value) { topic = value; update() }
                }
                topicButtons[value] = button
                addView(button, LinearLayout.LayoutParams(-2, -2).apply { marginEnd = ui.dp(6) })
            }
            more = choice(R.string.health_body_more, "health-body-more") {
                val extras = HealthBodyTopic.entries.drop(4)
                modal = AlertDialog.Builder(this@HealthBodyExplorationActivity).setTitle(R.string.health_body_more)
                    .setItems(extras.map { getString(it.label) }.toTypedArray()) { _, index ->
                        topic = extras[index]; update()
                    }.setNegativeButton(android.R.string.cancel, null).show()
            }
            addView(more)
        }
        ui.add(page, HorizontalScrollView(this).apply { isHorizontalScrollBarEnabled = false; addView(tabs) }, 10)
        page.addView(panel)
        update()
    }

    private fun conceptImage() = ImageView(this).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        setImageResource(R.drawable.health_body_concept)
        contentDescription = getString(R.string.health_body_concept_alt)
        tag = "health-body-illustration"
    }

    private fun choice(label: Int, key: String, action: () -> Unit) = ui.text(getString(label), 14f).apply {
        tag = key
        gravity = Gravity.CENTER
        minimumHeight = ui.dp(44)
        setPadding(ui.dp(10), ui.dp(3), ui.dp(10), ui.dp(3))
        setOnClickListener { action() }
        isFocusable = true
        maxLines = 1
        setAutoSizeTextTypeUniformWithConfiguration(10, 14, 1, TypedValue.COMPLEX_UNIT_SP)
    }

    private fun styleChoice(view: TextView, selected: Boolean, rail: Boolean = false) {
        view.isSelected = selected
        view.setTextColor(if (rail) 0xff214b39.toInt() else if (selected) strongGreen else ink)
        val color = if (rail) { if (selected) 0xffc8edda.toInt() else 0xfff9fdfa.toInt() } else if (selected) softGreen else neutral
        val stroke = if (selected) { if (rail) 0xff86bb9d.toInt() else strongGreen } else if (rail) null else hairline
        view.background = ui.background(color, stroke, radius = 8)
    }

    private fun card() = ui.column().apply {
        setPadding(ui.dp(14), ui.dp(12), ui.dp(14), ui.dp(12))
        background = ui.background(neutral, hairline, radius = 8)
    }

    private fun secondary(label: Int, key: String, action: () -> Unit) = ui.command(label, action).apply {
        tag = key
        setTextColor(strongGreen)
        setPadding(ui.dp(10), ui.dp(6), ui.dp(10), ui.dp(6))
        background = ui.background(softGreen, radius = 8)
    }

    private fun smallLine(container: LinearLayout, label: Int, top: Int) =
        ui.add(container, ui.text(getString(label), 13f).apply { setTextColor(muted) }, top)

    private fun overviewContent(panel: LinearLayout) {
        val info = HealthBodyLessons.info(topic)
        val lesson = HealthBodyLessons.lesson(topic, layer)
        ui.add(panel, card().apply {
            addView(ui.text(getString(R.string.health_body_mechanism), 12f, bold = true).apply { setTextColor(strongGreen) })
            ui.add(this, ui.text(getString(lesson.title), 19f, bold = true).apply { tag = "health-body-lesson-title" }, 3)
            ui.add(this, ui.text(getString(lesson.summary), 14f).apply { setTextColor(muted) }, 6)
            ui.add(this, ui.text(getString(info.layers[layer.ordinal]), 14f).apply { tag = "health-body-insight" }, 8)
            ui.add(this, secondary(R.string.health_body_preview, "health-body-preview") {
                position = 0f
                open(Screen.LESSON)
                start()
            }, 10)
        }, 12)
        val heading = if (topic == HealthBodyTopic.CIRCULATION) R.string.health_body_bp_title else R.string.health_body_reference_title
        ui.add(panel, ui.profileRow(getString(heading), getString(R.string.health_body_reference_caption)) { open(Screen.REFERENCE) }
            .apply { tag = "health-body-reference"; background = ui.background(neutral, hairline, radius = 8) }, 10)
        smallLine(panel, R.string.health_body_concept_note, 11)
    }

    private fun lessonPage(page: LinearLayout) {
        val value = HealthBodyLessons.lesson(topic, layer)
        page.addView(ui.text(getString(value.title), 22f, bold = true).apply { tag = "health-body-lesson-title" })
        smallLine(page, R.string.health_body_model_caption, 4)
        val canvas = HealthBodyDiagram(this, value)
        diagram = canvas
        page.addView(canvas.apply { background = ui.background(neutral, hairline, radius = 8) },
            LinearLayout.LayoutParams(-1, ui.dp(216)).apply { topMargin = ui.dp(12) })
        ui.add(page, ui.line().apply {
            before = ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { jump(-1) }.apply {
                tag = "health-body-previous"
            }.also(::addView)
            play = ui.icon(R.drawable.ic_rich_play, R.string.health_body_play) {
                if (animator == null) start() else pause()
            }.apply {
                tag = "health-body-play"
                background = ui.background(softGreen, radius = 8)
                imageTintList = android.content.res.ColorStateList.valueOf(strongGreen)
            }.also(::addView)
            after = ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { jump(1) }.apply {
                rotation = 180f
                tag = "health-body-next"
            }.also(::addView)
            addView(View(this@HealthBodyExplorationActivity), LinearLayout.LayoutParams(0, 1, 1f))
            addView(Switch(this@HealthBodyExplorationActivity).apply {
                setText(R.string.health_body_slow)
                isChecked = slow
                isSaveEnabled = false
                tag = "health-body-slow"
                setOnCheckedChangeListener { _, checked ->
                    val playing = animator != null
                    pause()
                    slow = checked
                    if (playing) start()
                }
            })
        }, 8)
        phaseTitle = ui.text("", 17f, bold = true).apply { tag = "health-body-phase" }
            .also { ui.add(page, it, 10) }
        phaseDetail = ui.text("", 15f).also { ui.add(page, it, 5) }
        if (topic in setOf(HealthBodyTopic.CIRCULATION, HealthBodyTopic.BREATHING)) smallLine(page, R.string.health_body_color_note, 8)
        if (topic == HealthBodyTopic.CIRCULATION && layer != HealthBodyLayer.MOLECULE)
            ui.add(page, ui.profileRow(getString(R.string.health_body_experiment), getString(R.string.health_body_example_only)) {
                open(Screen.EXPERIMENT)
            }.apply { tag = "health-body-experiment" }, 10)
        ui.add(page, ui.profileRow(getString(R.string.health_body_reference_title)) { open(Screen.REFERENCE) }, 8)
        showFrame()
        syncControls()
    }

    private fun start() {
        if (screen != Screen.LESSON || animator != null || !ValueAnimator.areAnimatorsEnabled()) return
        val steps = HealthBodyLessons.lesson(topic, layer).steps.size
        if (position >= steps) position = 0f
        val initial = position
        val animation = ValueAnimator.ofFloat(initial, steps.toFloat()).apply {
            duration = ((steps - initial) / steps * HealthBodyTimeline.duration(steps, slow)).toLong().coerceAtLeast(1L)
            interpolator = LinearInterpolator()
            addUpdateListener { source ->
                if (animator === source) {
                    position = source.animatedValue as Float
                    showFrame()
                }
            }
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(value: Animator) {
                    if (animator === value) { animator = null; syncControls() }
                }
            })
        }
        animator = animation
        syncControls()
        animation.start()
    }

    private fun pause() {
        val running = animator
        animator = null
        running?.cancel()
        syncControls()
    }

    private fun jump(direction: Int) {
        pause()
        position = HealthBodyTimeline.jump(position, HealthBodyLessons.lesson(topic, layer).steps.size, direction)
        showFrame()
        phaseTitle?.announceForAccessibility(phaseTitle?.text)
    }

    private fun showFrame() {
        val value = HealthBodyLessons.lesson(topic, layer)
        val frame = HealthBodyTimeline.frame(position, value.steps.size)
        diagram?.position = position
        if (frame.step == lastPhase) return
        lastPhase = frame.step
        val step = value.steps[frame.step]
        phaseTitle?.text = getString(R.string.health_body_step_count, frame.step + 1, value.steps.size, getString(step.title))
        phaseDetail?.setText(step.detail)
        before?.isEnabled = frame.step > 0
        after?.isEnabled = frame.step < value.steps.lastIndex
        before?.alpha = if (frame.step > 0) 1f else .35f
        after?.alpha = if (frame.step < value.steps.lastIndex) 1f else .35f
    }

    private fun syncControls() {
        play?.apply {
            val running = animator != null
            isEnabled = ValueAnimator.areAnimatorsEnabled()
            setImageResource(if (running) R.drawable.ic_rich_pause else R.drawable.ic_rich_play)
            contentDescription = getString(if (!isEnabled) R.string.health_body_motion_disabled
                else if (running) R.string.health_body_pause else R.string.health_body_play)
            tooltipText = contentDescription
        }
    }

    private fun referencePage(page: LinearLayout) {
        val info = HealthBodyLessons.info(topic)
        val value = HealthBodyLessons.lesson(topic, layer)
        page.addView(ui.text(getString(R.string.health_body_reference_title), 22f, bold = true))
        smallLine(page, R.string.health_body_reference_boundary, 4)
        ui.add(page, ui.text(getString(if (value != info.lesson) R.string.health_body_oxygen_reference else info.reference), 16f), 12)
        ui.add(page, ui.profileRow(getString(value.source)) { openSource(value.url) }.apply {
            tag = "health-body-source"
        }, 8)
        if (topic == HealthBodyTopic.CIRCULATION) {
            ui.add(page, card().apply {
                addView(ui.text(getString(R.string.health_body_personal), 13f, bold = true).apply { setTextColor(strongGreen) })
                ui.add(this, ui.text(getString(R.string.health_body_personal_boundary), 14f), 7)
                ui.add(this, secondary(R.string.health_body_open_bp, "health-body-open-bp") {
                    startActivity(Intent(this@HealthBodyExplorationActivity, HealthTrendActivity::class.java)
                        .putExtra("health_metric", HealthMetric.BLOOD_PRESSURE.name))
                }, 10)
            }, 14)
        }
    }

    private fun experimentPage(page: LinearLayout) {
        page.addView(ui.line().apply {
            addView(ui.text(getString(R.string.health_body_experiment), 22f, bold = true), LinearLayout.LayoutParams(0, -2, 1f))
            addView(ui.icon(R.drawable.ic_reset_data, R.string.health_body_reset_experiment) {
                experiment = HealthBodyPumpExperiment()
                render()
            }.apply { tag = "health-body-experiment-reset" })
        })
        smallLine(page, R.string.health_body_example_only, 5)
        val number = NumberFormat.getNumberInstance().apply { minimumFractionDigits = 2; maximumFractionDigits = 2 }
        val output = ui.text("", 28f, bold = true).apply { tag = "health-body-output"; setTextColor(strongGreen) }
        fun refresh() {
            output.text = getString(R.string.health_body_output, number.format(experiment.outputMlPerMinute / 1000.0))
        }
        ui.add(page, output, 13)
        smallLine(page, R.string.health_body_formula, 2)
        fun slider(key: String, range: IntRange, value: Int, label: Int, change: (Int) -> Unit) {
            val name = ui.text(getString(label, value), 15f, bold = true)
            ui.add(page, name, 14)
            ui.add(page, SeekBar(this).apply {
                tag = key
                isSaveEnabled = false
                max = range.last - range.first
                progress = value - range.first
                contentDescription = name.text
                setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                    override fun onProgressChanged(bar: SeekBar, progress: Int, fromUser: Boolean) {
                        val next = range.first + progress
                        name.text = getString(label, next)
                        bar.contentDescription = name.text
                        change(next)
                        refresh()
                    }
                    override fun onStartTrackingTouch(bar: SeekBar) = Unit
                    override fun onStopTrackingTouch(bar: SeekBar) = Unit
                })
            }, 4)
        }
        slider("health-body-beats", HealthBodyPumpExperiment.BEATS, experiment.beats, R.string.health_body_rate) {
            experiment = experiment.copy(beats = it)
        }
        slider("health-body-stroke", HealthBodyPumpExperiment.STROKE_ML, experiment.strokeMl, R.string.health_body_stroke) {
            experiment = experiment.copy(strokeMl = it)
        }
        smallLine(page, R.string.health_body_experiment_boundary, 12)
        ui.add(page, ui.profileRow(getString(R.string.health_body_source_pump)) {
            openSource("https://openstax.org/books/anatomy-and-physiology/pages/19-4-cardiac-physiology")
        }, 8)
        refresh()
    }

    private fun openSource(url: String) {
        try { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        catch (_: android.content.ActivityNotFoundException) {
            Toast.makeText(this, R.string.health_body_browser_unavailable, Toast.LENGTH_SHORT).show()
        }
    }

    private fun zoom() {
        val dialog = Dialog(this, android.R.style.Theme_Material_NoActionBar)
        val picture = conceptImage().apply { isClickable = true }
        val viewport = GalaxySSIPinchZoomViewport(this).apply { attach(picture) }
        dialog.setContentView(ui.column().apply {
            setBackgroundColor(neutral)
            addView(ui.line().apply {
                addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_back) { dialog.dismiss() })
                addView(ui.text(getString(R.string.health_body_title), 18f, bold = true))
            }, LinearLayout.LayoutParams(-1, ui.dp(56)))
            addView(viewport, LinearLayout.LayoutParams(-1, 0, 1f))
            smallLine(this, R.string.health_body_concept_note, 8)
        })
        dialog.setOnDismissListener { picture.setImageDrawable(null) }
        modal = dialog
        dialog.show()
        dialog.window?.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    }
}
