package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.os.SystemClock
import android.view.View
import android.view.Gravity
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.SeekBar

internal class HealthAtlasFunctionPlayer(activity: Activity, val story: HealthAtlasFunctionStory,
    initial: Float, openSource: (String) -> Unit, showTitle: Boolean = true,
    private val onPlay: () -> Unit = {}) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = story.createArt(activity)
    private val caption = ui.text("", 15f).apply { tag = "atlas-function-caption" }
    private val chapterLabel = ui.text("", 16f, bold = true).apply { tag = "atlas-function-chapter" }
    private val timeline = HealthAtlasChapterClock(story.chapters.size, initial)
    private val frame = Runnable { advance() }
    private val play: ImageButton = ui.icon(R.drawable.ic_rich_play, R.string.health_body_play, ::toggle)
        .apply { tag = "atlas-function-play" }
    private val position = SeekBar(activity).apply {
        max = 1000
        tag = "atlas-function-position"
        minimumHeight = ui.dp(36)
        contentDescription = context.getString(R.string.health_atlas_phase)
        setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onStartTrackingTouch(seek: SeekBar?) = pause()
            override fun onStopTrackingTouch(seek: SeekBar?) = Unit
            override fun onProgressChanged(seek: SeekBar?, value: Int, user: Boolean) {
                if (user) seek(value / 1000f)
            }
        })
    }
    private var renderedChapter = -1
    var phase = 0f
        private set

    init {
        tag = "atlas-function-player"
        orientation = VERTICAL
        if (showTitle) ui.add(this, ui.text(context.getString(story.title), 18f, bold = true))
        ui.add(this, ui.line().apply {
            gravity = Gravity.CENTER
            tag = "atlas-function-controls"
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { skip(-1) }
                .apply { tag = "atlas-function-previous" })
            addView(play)
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { skip(1) }
                .apply { rotation = 180f; tag = "atlas-function-next" })
            addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) { seek(0f) }
                .apply { tag = "atlas-function-reset" })
        }, if (showTitle) 2 else 0)
        ui.add(this, position)
        art.setOnClickListener { toggle() }
        art.isFocusable = true
        ui.add(this, art, 6)
        ui.add(this, chapterLabel, 12)
        ui.add(this, caption, 6)
        ui.add(this, ui.text(context.getString(story.scope), 12f, muted = true), 6)
        val outline = ui.column().apply { tag = "atlas-function-outline"; visibility = View.GONE }
        ui.add(this, HealthAtlasUi.disclosure(activity, context.getString(R.string.health_atlas_function_outline),
            "atlas-function-outline-toggle") { open ->
            if (open && outline.childCount == 0) story.chapters.forEachIndexed { index, chapter ->
                val label = context.getString(R.string.health_atlas_stage, index + 1, story.chapters.size,
                    context.getString(chapter.first))
                ui.add(outline, ui.row(label, context.getString(chapter.second)) { seek(story.startOf(index)) }
                    .apply { tag = "atlas-function-outline-stage-$index" })
            }
            outline.visibility = if (open) View.VISIBLE else View.GONE
        }, 6)
        ui.add(this, outline)
        story.references.forEachIndexed { index, (title, url) ->
            ui.add(this, ui.row(context.getString(title)) { openSource(url) }
                .apply { tag = "atlas-function-source-$index" }, if (index == 0) 8 else 0)
        }
        showPhase(timeline.sample(SystemClock.uptimeMillis()))
    }

    private fun skip(direction: Int) {
        val position = timeline.sample(SystemClock.uptimeMillis())
        seek(story.startOf(story.chapter(position) + direction))
    }

    private fun showPhase(value: Float) {
        phase = HealthAtlasFunctionStory.safePhase(value)
        val chapter = story.chapter(phase)
        if (chapter != renderedChapter) {
            val (title, detail) = story.chapters[chapter]
            chapterLabel.text = context.getString(R.string.health_atlas_stage, chapter + 1,
                story.chapters.size, context.getString(title))
            caption.setText(detail)
            renderedChapter = chapter
        }
        art.phase = if (ValueAnimator.areAnimatorsEnabled()) phase else story.startOf(chapter)
        position.progress = (phase * position.max).toInt()
    }

    private fun seek(value: Float) {
        removeCallbacks(frame)
        timeline.seek(value)
        advance()
    }

    private fun toggle() {
        if (timeline.playing) pause()
        else {
            onPlay()
            timeline.resume(SystemClock.uptimeMillis())
            advance()
        }
    }

    private fun advance() {
        val now = SystemClock.uptimeMillis()
        showPhase(timeline.sample(now))
        val label = context.getString(if (timeline.playing) R.string.health_body_pause else R.string.health_body_play)
        if (play.contentDescription != label) {
            play.setImageResource(if (timeline.playing) R.drawable.ic_rich_pause else R.drawable.ic_rich_play)
            play.contentDescription = label
            play.tooltipText = label
        }
        if (timeline.playing) {
            if (ValueAnimator.areAnimatorsEnabled()) postOnAnimation(frame)
            else postDelayed(frame, timeline.nextStepIn(now))
        }
    }

    fun pause() {
        if (!timeline.playing) return
        removeCallbacks(frame)
        timeline.pause(SystemClock.uptimeMillis())
        advance()
    }

    override fun onDetachedFromWindow() { pause(); super.onDetachedFromWindow() }
}
