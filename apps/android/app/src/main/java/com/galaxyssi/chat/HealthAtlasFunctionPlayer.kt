package com.galaxyssi.chat

import android.animation.ValueAnimator
import android.app.Activity
import android.app.AlertDialog
import android.os.SystemClock
import android.view.Gravity
import android.widget.ImageButton
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.SeekBar
import android.widget.TextView

internal class HealthAtlasFunctionPlayer(activity: Activity, val story: HealthAtlasFunctionStory,
    initial: Float, openSource: (String) -> Unit, showTitle: Boolean = true,
    private val onPlay: () -> Unit = {}) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val art = story.createArt(activity)
    private val caption = ui.text("", 15f).apply { tag = "atlas-function-caption" }
    private val chapterLabel = ui.text("", 14f, bold = true).apply {
        tag = "atlas-function-chapter"
        setTextColor(context.getColor(R.color.health_atlas_film_chapter))
    }
    private val chapterLabels = story.chapters.mapIndexed { index, chapter ->
        context.getString(R.string.health_atlas_scene_chapter, index + 1, story.chapters.size, context.getString(chapter.first))
    }
    private val chapterCaptions = story.chapters.map { context.getString(it.second) }
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
        val scene = HealthAtlasSceneFrame(activity, "atlas-function-frame").apply {
            background = ui.background(context.getColor(R.color.health_atlas_film_ground))
            val captionInset = 2 * ui.dp(14)
            reserveCaption(chapterLabel, chapterLabels, captionInset)
            reserveCaption(caption, chapterCaptions, captionInset)
            if (showTitle) ui.add(this, ui.text(context.getString(story.title), 16f, bold = true).apply {
                setPadding(ui.dp(12), ui.dp(10), ui.dp(12), ui.dp(8))
            })
            art.setOnClickListener { toggle() }
            art.isFocusable = true
            ui.add(this, art)
            ui.add(this, ui.column().apply {
                tag = "atlas-function-subtitles"
                setPadding(ui.dp(14), ui.dp(9), ui.dp(14), ui.dp(12))
                setBackgroundColor(context.getColor(R.color.health_atlas_film_caption))
                caption.setTextColor(context.getColor(R.color.health_atlas_film_text))
                ui.add(this, chapterLabel)
                ui.add(this, caption, 2)
            })
        }
        ui.add(this, scene)
        ui.add(this, position)
        ui.add(this, ui.line().apply {
            gravity = Gravity.CENTER
            tag = "atlas-function-controls"
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { skip(-1) }
                .apply { tag = "atlas-function-previous" })
            addView(play)
            addView(ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { skip(1) }
                .apply { rotation = 180f; tag = "atlas-function-next" })
            addView(ui.icon(R.drawable.ic_more_horizontal, R.string.health_atlas_scene_menu) {
                pause()
                PopupMenu(activity, findViewWithTag("atlas-function-menu")).apply {
                    menu.add(R.string.health_atlas_function_outline).setOnMenuItemClickListener {
                        AlertDialog.Builder(activity).setTitle(R.string.health_atlas_function_outline)
                            .setSingleChoiceItems(chapterLabels.toTypedArray(), story.chapter(phase)) { dialog, index ->
                                seek(story.startOf(index))
                                dialog.dismiss()
                            }
                            .setNegativeButton(android.R.string.cancel, null).show()
                        true
                    }
                    menu.add(R.string.health_atlas_reset).setOnMenuItemClickListener { seek(0f); true }
                    menu.add(R.string.health_atlas_evidence).setOnMenuItemClickListener {
                        AlertDialog.Builder(activity).setTitle(R.string.health_atlas_evidence)
                            .setMessage(context.getString(story.scope))
                            .setNegativeButton(android.R.string.cancel, null)
                            .setPositiveButton(R.string.health_atlas_scene_sources) { _, _ ->
                                AlertDialog.Builder(activity).setTitle(R.string.health_atlas_scene_sources)
                                    .setItems(story.references.map { context.getString(it.first) }.toTypedArray()) { _, index ->
                                        openSource(story.references[index].second)
                                    }.setNegativeButton(android.R.string.cancel, null).show()
                            }.show()
                        true
                    }
                }.show()
            }.apply { tag = "atlas-function-menu" })
        })
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
            chapterLabel.text = chapterLabels[chapter]
            caption.text = chapterCaptions[chapter]
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
