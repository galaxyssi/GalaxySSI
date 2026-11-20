package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.view.Gravity
import android.view.animation.LinearInterpolator
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.SeekBar

internal class HealthAtlasFunctionPlayer(activity: Activity, private val story: HealthAtlasFunctionStory,
    initial: Float, openSource: (String) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = story.createArt(activity)
    private val caption = ui.text("", 15f).apply { tag = "atlas-function-caption" }
    private val chapterLabel = ui.text("", 16f, bold = true).apply { tag = "atlas-function-chapter" }
    private val play: ImageButton = ui.icon(R.drawable.ic_rich_play, R.string.health_body_play) {
        if (animator == null) start() else pause()
    }.apply { tag = "atlas-function-play" }
    private val position = SeekBar(activity).apply {
        max = 1000
        tag = "atlas-function-position"
        contentDescription = context.getString(R.string.health_atlas_phase)
        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(seek: SeekBar?) = pause()
            override fun onStopTrackingTouch(seek: SeekBar?) = Unit
            override fun onProgressChanged(seek: SeekBar?, value: Int, user: Boolean) {
                if (user) { pause(); setPhase(value / 1000f) }
            }
        })
    }
    private var animator: ValueAnimator? = null
    private var renderedChapter = -1
    var phase = 0f
        private set

    init {
        tag = "atlas-function-player"
        orientation = VERTICAL
        ui.add(this, ui.text(context.getString(story.title), 18f, bold = true))
        ui.add(this, art, 10)
        ui.add(this, chapterLabel, 12)
        ui.add(this, caption, 6)
        ui.add(this, ui.line().apply {
            gravity = Gravity.CENTER
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { skip(-1) }
                .apply { tag = "atlas-function-previous" })
            addView(play)
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { skip(1) }
                .apply { rotation = 180f; tag = "atlas-function-next" })
            addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) { pause(); setPhase(0f) }
                .apply { tag = "atlas-function-reset" })
        }, 6)
        ui.add(this, position)
        ui.add(this, ui.text(context.getString(story.scope), 12f, muted = true), 6)
        story.references.forEachIndexed { index, (title, url) ->
            ui.add(this, ui.row(context.getString(title)) { openSource(url) }
                .apply { tag = "atlas-function-source-$index" }, if (index == 0) 8 else 0)
        }
        setPhase(initial)
    }

    private fun skip(direction: Int) {
        pause()
        setPhase(story.startOf(story.chapter(phase) + direction))
    }

    private fun setPhase(value: Float) {
        phase = HealthAtlasFunctionStory.safePhase(value)
        val chapter = story.chapter(phase)
        if (chapter != renderedChapter) {
            val (title, detail) = story.chapters[chapter]
            chapterLabel.text = context.getString(R.string.health_atlas_stage, chapter + 1,
                story.chapters.size, context.getString(title))
            caption.setText(detail)
            renderedChapter = chapter
        }
        art.phase = phase
        position.progress = (phase * position.max).toInt()
    }

    private fun start() {
        if (phase >= 1f) setPhase(0f)
        if (!ValueAnimator.areAnimatorsEnabled()) { skip(1); return }
        play.setImageResource(R.drawable.ic_rich_pause)
        play.contentDescription = context.getString(R.string.health_body_pause)
        val player = ValueAnimator.ofFloat(phase, 1f).apply {
            duration = ((1f - phase) * story.durationMs).toLong().coerceAtLeast(1L)
            interpolator = LinearInterpolator()
            addUpdateListener {
                setPhase(it.animatedValue as Float)
                if (phase >= 1f) pause()
            }
        }
        animator = player
        player.start()
    }

    fun pause() {
        animator?.removeAllUpdateListeners()
        animator?.cancel()
        animator = null
        play.setImageResource(R.drawable.ic_rich_play)
        play.contentDescription = context.getString(R.string.health_body_play)
    }

    override fun onDetachedFromWindow() { pause(); super.onDetachedFromWindow() }
}
