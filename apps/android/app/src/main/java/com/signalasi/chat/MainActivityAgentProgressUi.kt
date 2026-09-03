package com.signalasi.chat

import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

internal fun MainActivity.agentPlanProgressSummaryRow(
    entry: AgentTranscriptEntry,
    groupKey: String,
    presentation: AgentInteractiveProgressPresentation
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    minimumHeight = dp(30)
    setPadding(0, dp(3), 0, dp(3))

    val trigger = FrameLayout(this@agentPlanProgressSummaryRow).apply {
        isClickable = true
        isFocusable = true
        contentDescription = getString(R.string.agent_plan_progress_open)
        addView(
            agentPlanProgressSpinner(presentation.running),
            FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER)
        )
        setOnClickListener {
            toggleAgentPlanProgressOverlay(entry, groupKey, presentation)
        }
    }
    addView(trigger, LinearLayout.LayoutParams(dp(24), dp(24)))
    addView(TextView(this@agentPlanProgressSummaryRow).apply {
        text = if (presentation.planRevision > 1) {
            getString(
                R.string.agent_plan_progress_revision_counter,
                presentation.planRevision,
                presentation.currentStep,
                presentation.totalSteps
            )
        } else {
            presentation.counter
        }
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 11f
        includeFontPadding = false
        gravity = Gravity.CENTER_VERTICAL
        maxLines = 1
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply {
        marginStart = dp(2)
        marginEnd = dp(7)
    })
    addView(TextView(this@agentPlanProgressSummaryRow).apply {
        text = localizedAgentProcessText(presentation.summary)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 12f
        includeFontPadding = false
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

    refreshAgentPlanProgressOverlayIfVisible(entry, groupKey, presentation)
}

internal fun MainActivity.toggleAgentPlanProgressOverlay(
    entry: AgentTranscriptEntry,
    groupKey: String,
    presentation: AgentInteractiveProgressPresentation
) {
    if (agentPlanProgressOverlay != null && agentPlanProgressOverlayGroupKey == groupKey) {
        dismissAgentPlanProgressOverlay()
        return
    }
    showAgentPlanProgressOverlay(entry, groupKey, presentation)
}

internal fun MainActivity.dismissAgentPlanProgressOverlay() {
    (agentPlanProgressOverlay?.parent as? ViewGroup)?.removeView(agentPlanProgressOverlay)
    agentPlanProgressOverlay = null
    agentPlanProgressOverlayGroupKey = ""
}

private fun MainActivity.refreshAgentPlanProgressOverlayIfVisible(
    entry: AgentTranscriptEntry,
    groupKey: String,
    presentation: AgentInteractiveProgressPresentation
) {
    if (agentPlanProgressOverlay == null || agentPlanProgressOverlayGroupKey != groupKey) return
    agentOutputList.post {
        if (agentPlanProgressOverlay != null && agentPlanProgressOverlayGroupKey == groupKey) {
            showAgentPlanProgressOverlay(entry, groupKey, presentation)
        }
    }
}

private fun MainActivity.showAgentPlanProgressOverlay(
    entry: AgentTranscriptEntry,
    groupKey: String,
    presentation: AgentInteractiveProgressPresentation
) {
    dismissAgentPlanProgressOverlay()
    val viewport = findViewById<FrameLayout>(R.id.agentOutputViewport)
    val runtime = agentTimelineRuntime(entry)
    val timelineActions = runtime?.snapshot()?.phase
        ?.let(AgentExecutionLoopTimelinePolicy::actionsForPhase)
        .orEmpty()
    val root = FrameLayout(this).apply {
        isClickable = true
        isFocusable = true
        setBackgroundColor(Color.argb(54, 17, 22, 26))
        setOnClickListener { dismissAgentPlanProgressOverlay() }
    }
    val panel = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        isClickable = true
        elevation = dp(12).toFloat()
        setPadding(dp(14), dp(8), dp(14), dp(14))
        background = GradientDrawable().apply {
            setColor(getColorCompat(R.color.surface_bg))
            cornerRadii = floatArrayOf(
                dp(8).toFloat(), dp(8).toFloat(),
                dp(8).toFloat(), dp(8).toFloat(),
                0f, 0f,
                0f, 0f
            )
        }
    }
    panel.addView(View(this).apply {
        background = GradientDrawable().apply {
            cornerRadius = dp(2).toFloat()
            setColor(getColorCompat(R.color.separator))
        }
    }, LinearLayout.LayoutParams(dp(34), dp(4)).apply {
        gravity = Gravity.CENTER_HORIZONTAL
        bottomMargin = dp(7)
    })
    panel.addView(agentPlanProgressHeader(presentation))
    panel.addView(View(this).apply {
        setBackgroundColor(getColorCompat(R.color.separator))
    }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(1)))
    panel.addView(agentPlanProgressHeadline(presentation))

    val planRows = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        presentation.batches.forEach { batch ->
            if (presentation.batches.size > 1 || batch.planRevision > 1) {
                addView(agentPlanProgressBatchHeader(batch))
            }
            batch.steps.forEach { step -> addView(agentPlanProgressStepRow(step)) }
        }
    }
    panel.addView(AgentPlanProgressScrollView(this).apply {
        isFillViewport = false
        maximumHeight = (viewport.height - dp(264)).coerceIn(dp(112), dp(350))
        addView(planRows, FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ))

    if (presentation.recentActivity.isNotEmpty()) {
        panel.addView(agentPlanCurrentActivity(presentation))
    }
    if (runtime != null && presentation.running) {
        panel.addView(agentPlanProgressControls(entry, runtime, timelineActions))
    }
    root.addView(panel, FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
        Gravity.BOTTOM
    ))
    viewport.addView(root, FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
    ))
    agentPlanProgressOverlay = root
    agentPlanProgressOverlayGroupKey = groupKey
}

private fun MainActivity.agentPlanProgressHeader(
    presentation: AgentInteractiveProgressPresentation
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    minimumHeight = dp(49)
    addView(LinearLayout(this@agentPlanProgressHeader).apply {
        orientation = LinearLayout.VERTICAL
        addView(TextView(this@agentPlanProgressHeader).apply {
            text = getString(R.string.agent_plan_progress_title)
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 16f
            includeFontPadding = false
        })
        addView(TextView(this@agentPlanProgressHeader).apply {
            text = getString(
                if (presentation.running) {
                    R.string.agent_plan_progress_live
                } else {
                    R.string.agent_plan_progress_finished
                }
            )
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 11f
            includeFontPadding = false
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(3) })
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
    addView(FrameLayout(this@agentPlanProgressHeader).apply {
        isClickable = true
        isFocusable = true
        contentDescription = getString(R.string.common_close)
        addView(ImageView(this@agentPlanProgressHeader).apply {
            setImageResource(R.drawable.ic_agent_progress_close)
            imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_primary))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
        }, FrameLayout.LayoutParams(dp(18), dp(18), Gravity.CENTER))
        setOnClickListener { dismissAgentPlanProgressOverlay() }
    }, LinearLayout.LayoutParams(dp(34), dp(34)))
}

private fun MainActivity.agentPlanProgressHeadline(
    presentation: AgentInteractiveProgressPresentation
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(0, dp(13), 0, 0)
    addView(agentPlanProgressSpinner(presentation.running), LinearLayout.LayoutParams(dp(16), dp(16)).apply {
        marginEnd = dp(8)
    })
    addView(TextView(this@agentPlanProgressHeadline).apply {
        text = localizedAgentProcessText(presentation.summary)
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 12.5f
        includeFontPadding = false
        maxLines = 2
        ellipsize = android.text.TextUtils.TruncateAt.END
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
    addView(TextView(this@agentPlanProgressHeadline).apply {
        text = getString(
            R.string.agent_plan_progress_current_batch_count,
            presentation.currentStep,
            presentation.totalSteps
        )
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 12f
        includeFontPadding = false
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { marginStart = dp(10) })
}

private fun MainActivity.agentPlanProgressBatchHeader(
    batch: AgentInteractiveProgressBatch
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(0, dp(11), 0, dp(3))
    addView(TextView(this@agentPlanProgressBatchHeader).apply {
        text = getString(R.string.agent_plan_progress_revision, batch.planRevision)
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 10.5f
        includeFontPadding = false
    })
    if (!batch.current) {
        addView(TextView(this@agentPlanProgressBatchHeader).apply {
            text = getString(R.string.agent_plan_progress_revised)
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 10f
            includeFontPadding = false
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ).apply { marginStart = dp(8) })
    }
}

private fun MainActivity.agentPlanProgressStepRow(
    step: AgentInteractiveProgressStep
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.TOP
    minimumHeight = dp(52)
    setPadding(0, dp(9), 0, dp(9))
    addView(agentPlanProgressStepIndicator(step.state), LinearLayout.LayoutParams(dp(18), dp(18)).apply {
        marginEnd = dp(9)
    })
    addView(TextView(this@agentPlanProgressStepRow).apply {
        text = localizedAgentProcessText(step.text)
        setTextColor(
            getColorCompat(
                if (step.state == AgentInteractiveProgressStepState.PENDING) {
                    R.color.text_secondary
                } else {
                    R.color.text_primary
                }
            )
        )
        textSize = 12.5f
        includeFontPadding = false
        maxLines = 3
        ellipsize = android.text.TextUtils.TruncateAt.END
    }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
    addView(TextView(this@agentPlanProgressStepRow).apply {
        text = getString(step.state.labelResource())
        setTextColor(getColorCompat(R.color.text_secondary))
        textSize = 10f
        includeFontPadding = false
        maxLines = 1
    }, LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { marginStart = dp(8) })
}

private fun MainActivity.agentPlanProgressStepIndicator(
    state: AgentInteractiveProgressStepState
): View = when (state) {
    AgentInteractiveProgressStepState.COMPLETED -> ImageView(this).apply {
        setImageResource(R.drawable.ic_agent_progress_complete)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.composer_send_icon))
    }
    AgentInteractiveProgressStepState.ACTIVE -> agentPlanProgressSpinner(running = true)
    AgentInteractiveProgressStepState.FAILED -> View(this).apply {
        background = progressRingDrawable(getColorCompat(R.color.unread_red))
    }
    AgentInteractiveProgressStepState.SUPERSEDED -> ImageView(this).apply {
        setImageResource(R.drawable.ic_process_analysis)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }
    AgentInteractiveProgressStepState.PENDING -> View(this).apply {
        background = progressRingDrawable(getColorCompat(R.color.separator))
    }
}

private fun MainActivity.agentPlanCurrentActivity(
    presentation: AgentInteractiveProgressPresentation
): View = LinearLayout(this).apply {
    orientation = LinearLayout.VERTICAL
    setPadding(dp(11), dp(10), dp(11), dp(10))
    background = GradientDrawable().apply {
        cornerRadius = dp(6).toFloat()
        setColor(getColorCompat(R.color.page_bg))
    }
    layoutParams = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT
    ).apply { topMargin = dp(12) }
    addView(LinearLayout(this@agentPlanCurrentActivity).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        addView(TextView(this@agentPlanCurrentActivity).apply {
            text = getString(R.string.agent_plan_progress_current_activity)
            setTextColor(getColorCompat(R.color.text_primary))
            textSize = 11f
            includeFontPadding = false
        }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        addView(TextView(this@agentPlanCurrentActivity).apply {
            text = presentation.agentLabel
            setTextColor(getColorCompat(R.color.text_secondary))
            textSize = 10.5f
            includeFontPadding = false
            maxLines = 1
            ellipsize = android.text.TextUtils.TruncateAt.END
        }, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        ))
    })
    presentation.recentActivity.forEach { activity ->
        addView(LinearLayout(this@agentPlanCurrentActivity).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.TOP
            setPadding(0, dp(6), 0, 0)
            addView(View(this@agentPlanCurrentActivity).apply {
                background = GradientDrawable().apply {
                    shape = GradientDrawable.OVAL
                    setColor(getColorCompat(R.color.text_secondary))
                }
            }, LinearLayout.LayoutParams(dp(4), dp(4)).apply {
                topMargin = dp(6)
                marginEnd = dp(8)
            })
            addView(TextView(this@agentPlanCurrentActivity).apply {
                text = localizedAgentProcessText(activity)
                setTextColor(getColorCompat(R.color.text_secondary))
                textSize = 11f
                includeFontPadding = false
                maxLines = 2
                ellipsize = android.text.TextUtils.TruncateAt.END
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        })
    }
}

private fun MainActivity.agentPlanProgressControls(
    entry: AgentTranscriptEntry,
    runtime: MobileNativeAgent,
    actions: List<AgentExecutionLoopTimelineAction>
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    setPadding(0, dp(11), 0, 0)
    val pauseAction = when {
        AgentExecutionLoopTimelineAction.PAUSE in actions -> AgentExecutionLoopTimelineAction.PAUSE
        AgentExecutionLoopTimelineAction.RESUME in actions -> AgentExecutionLoopTimelineAction.RESUME
        else -> null
    }
    addView(agentPlanProgressControlButton(
        icon = if (pauseAction == AgentExecutionLoopTimelineAction.RESUME) {
            R.drawable.ic_rich_play
        } else {
            R.drawable.ic_rich_pause
        },
        label = getString(
            if (pauseAction == AgentExecutionLoopTimelineAction.RESUME) {
                R.string.agent_resume_button
            } else {
                R.string.agent_pause_button
            }
        ),
        enabled = pauseAction != null
    ) {
        pauseAction?.let { action -> runAgentTimelineAction(entry, runtime, action) }
    }, LinearLayout.LayoutParams(0, dp(42), 1f))
    addView(agentPlanProgressControlButton(
        icon = R.drawable.ic_process_analysis,
        label = getString(R.string.agent_plan_progress_adjust),
        enabled = AgentExecutionLoopTimelineAction.REPLAN in actions
    ) {
        if (AgentExecutionLoopTimelineAction.REPLAN in actions) {
            runAgentTimelineAction(entry, runtime, AgentExecutionLoopTimelineAction.REPLAN)
        }
    }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginStart = dp(8) })
    addView(agentPlanProgressControlButton(
        icon = R.drawable.ic_group,
        label = getString(R.string.agent_plan_progress_change_agent),
        enabled = true
    ) {
        dismissAgentPlanProgressOverlay()
        showAgentModelSelectionPage()
    }, LinearLayout.LayoutParams(0, dp(42), 1f).apply { marginStart = dp(8) })
}

private fun MainActivity.agentPlanProgressControlButton(
    icon: Int,
    label: String,
    enabled: Boolean,
    onClick: () -> Unit
): View = LinearLayout(this).apply {
    orientation = LinearLayout.HORIZONTAL
    gravity = Gravity.CENTER
    isEnabled = enabled
    isClickable = enabled
    isFocusable = enabled
    alpha = if (enabled) 1f else 0.42f
    background = GradientDrawable().apply {
        cornerRadius = dp(6).toFloat()
        setColor(getColorCompat(R.color.surface_bg))
        setStroke(dp(1), getColorCompat(R.color.separator))
    }
    addView(ImageView(this@agentPlanProgressControlButton).apply {
        setImageResource(icon)
        imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_primary))
        scaleType = ImageView.ScaleType.CENTER_INSIDE
    }, LinearLayout.LayoutParams(dp(15), dp(15)).apply { marginEnd = dp(5) })
    addView(TextView(this@agentPlanProgressControlButton).apply {
        text = label
        setTextColor(getColorCompat(R.color.text_primary))
        textSize = 11f
        includeFontPadding = false
        maxLines = 1
        ellipsize = android.text.TextUtils.TruncateAt.END
    })
    setOnClickListener { onClick() }
}

private fun MainActivity.agentPlanProgressSpinner(running: Boolean): ImageView = ImageView(this).apply {
    setImageResource(R.drawable.ic_agent_plan_progress)
    imageTintList = ColorStateList.valueOf(getColorCompat(R.color.text_secondary))
    scaleType = ImageView.ScaleType.CENTER_INSIDE
    if (running) startAttachedRotation()
}

private fun ImageView.startAttachedRotation() {
    var animator: ObjectAnimator? = null
    val lifecycle = AttachedAnimationLifecycle(
        startAnimation = {
            animator?.cancel()
            animator = ObjectAnimator.ofFloat(this, View.ROTATION, rotation, rotation + 360f).also { animation ->
                animation.duration = 1_000L
                animation.interpolator = LinearInterpolator()
                animation.repeatCount = ValueAnimator.INFINITE
                animation.start()
            }
        },
        stopAnimation = {
            animator?.cancel()
            animator = null
        }
    )
    addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
        override fun onViewAttachedToWindow(view: View) = lifecycle.updateAttached(true)

        override fun onViewDetachedFromWindow(view: View) = lifecycle.updateAttached(false)
    })
    lifecycle.updateAttached(isAttachedToWindow)
}

private fun MainActivity.progressRingDrawable(color: Int): GradientDrawable = GradientDrawable().apply {
    shape = GradientDrawable.OVAL
    setColor(Color.TRANSPARENT)
    setStroke(dp(1), color)
}

private fun AgentInteractiveProgressStepState.labelResource(): Int = when (this) {
    AgentInteractiveProgressStepState.PENDING -> R.string.agent_plan_progress_pending
    AgentInteractiveProgressStepState.ACTIVE -> R.string.agent_plan_progress_running
    AgentInteractiveProgressStepState.COMPLETED -> R.string.agent_plan_progress_complete
    AgentInteractiveProgressStepState.SUPERSEDED -> R.string.agent_plan_progress_revised
    AgentInteractiveProgressStepState.FAILED -> R.string.agent_plan_progress_failed
}

private class AgentPlanProgressScrollView(context: Context) : ScrollView(context) {
    var maximumHeight: Int = Int.MAX_VALUE

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val available = MeasureSpec.getSize(heightMeasureSpec).takeIf { size -> size > 0 }
            ?: maximumHeight
        val cappedHeight = minOf(available, maximumHeight)
        super.onMeasure(
            widthMeasureSpec,
            MeasureSpec.makeMeasureSpec(cappedHeight, MeasureSpec.AT_MOST)
        )
    }
}
