package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal data class HealthAtlasEndocrineStep(val label: Int, val destination: String? = null)

internal data class HealthAtlasEndocrinePath(val scope: Int, val separateBranches: Boolean,
    val steps: List<HealthAtlasEndocrineStep>) {
    init { require(steps.size == 4) }

    companion object {
        private fun step(label: Int, destination: String? = null) = HealthAtlasEndocrineStep(label, destination)
        val all = mapOf(
            "thyroid-gland" to HealthAtlasEndocrinePath(R.string.health_atlas_endocrine_thyroid_scope, false, listOf(
                step(R.string.health_atlas_endocrine_stage_trh, "hypothalamus"),
                step(R.string.health_atlas_endocrine_stage_tsh, "cell-thyrotroph"),
                step(R.string.health_atlas_endocrine_stage_t3t4, "cell-thyroid-follicular-cell"),
                step(R.string.health_atlas_endocrine_stage_feedback))),
            "parathyroid-glands" to HealthAtlasEndocrinePath(R.string.health_atlas_endocrine_parathyroid_scope, false, listOf(
                step(R.string.health_atlas_endocrine_stage_low_ca),
                step(R.string.health_atlas_endocrine_stage_pth, "cell-parathyroid-chief-cell"),
                step(R.string.health_atlas_endocrine_stage_ca_response, "kidneys"),
                step(R.string.health_atlas_endocrine_stage_feedback))),
            "adrenal-glands" to HealthAtlasEndocrinePath(R.string.health_atlas_endocrine_adrenal_scope, true, listOf(
                step(R.string.health_atlas_endocrine_stage_crh_acth, "cell-corticotroph"),
                step(R.string.health_atlas_endocrine_stage_cortisol, "cell-adrenocortical-cell"),
                step(R.string.health_atlas_endocrine_stage_sympathetic, "nervous"),
                step(R.string.health_atlas_endocrine_stage_catecholamines, "cell-chromaffin-cell"))),
            "pituitary-gland" to HealthAtlasEndocrinePath(R.string.health_atlas_endocrine_pituitary_scope, true, listOf(
                step(R.string.health_atlas_endocrine_stage_activation, "hypothalamus"),
                step(R.string.health_atlas_endocrine_stage_anterior),
                step(R.string.health_atlas_endocrine_stage_activation, "hypothalamus"),
                step(R.string.health_atlas_endocrine_stage_posterior))),
        )
    }
}

/** Highlight one of four explanatory nodes without turning independent branches into a time series. */
internal class HealthAtlasEndocrinePathView(private val activity: Activity, private val atlas: HealthBodyAtlas,
    private val owner: HealthAtlasItem, private val path: HealthAtlasEndocrinePath, onPhase: (Int) -> Unit,
    select: (HealthAtlasItem) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val accent = activity.getColor(R.color.health_overview_green)
    private val mechanism = atlas.mechanism(owner)
    private val art = ImageView(activity).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        adjustViewBounds = true
        maxHeight = ui.dp(110)
        minimumHeight = ui.dp(84)
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val description = ui.text("", 15f, bold = true).apply { tag = "atlas-endocrine-current" }
    private val details = ui.row("") {
        path.steps[stage].destination?.let(atlas::get)?.let(select)
    }.apply { tag = "atlas-endocrine-open-node" }
    private val detailsText = (details.getChildAt(0) as LinearLayout).getChildAt(0) as TextView
    private val rows = path.steps.mapIndexed { index, step ->
        ui.text(activity.getString(step.label), 14f, bold = true).apply {
            gravity = Gravity.CENTER
            minimumHeight = ui.dp(50)
            setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
            tag = "atlas-endocrine-node-$index"
            isFocusable = true
            contentDescription = mechanism.stages[index]
            setOnClickListener { onPhase(index) }
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_NONE
        }
    }
    var stage = 0
        set(value) {
            require(value in path.steps.indices)
            field = value
            bind()
        }

    init {
        orientation = VERTICAL
        tag = "atlas-endocrine-path"
        for (branch in 0..1) {
            val first = branch * 2
            val reverse = !path.separateBranches && branch == 1
            if (reverse) ui.add(this, ui.line().apply {
                addView(View(activity), LayoutParams(0, 0, 1f))
                addView(View(activity), LayoutParams(ui.dp(26), 0))
                addView(arrow("\u2193"), LayoutParams(0, -2, 1f))
            })
            ui.add(this, ui.line().apply {
                addView(rows[first + if (reverse) 1 else 0], LayoutParams(0, -2, 1f))
                addView(arrow(if (reverse) "\u2190" else "\u2192"), LayoutParams(ui.dp(26), -2))
                addView(rows[first + if (reverse) 0 else 1], LayoutParams(0, -2, 1f))
            }, if (path.separateBranches && branch == 1) 6 else 0)
        }
        ui.add(this, HealthAtlasFigureFrame(activity, art, "atlas-endocrine-figure",
            subject = art, preferSideNote = true).apply {
            reserveCaption(description, mechanism.stages)
            ui.add(legend, description)
            ui.add(legend, ui.text(activity.getString(path.scope), 11f, muted = true), 5)
        }, 8)
        ui.add(this, details, 4)
        bind()
    }
    private fun arrow(symbol: String) = ui.text(symbol, 18f, muted = true).apply {
        gravity = Gravity.CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun bind() {
        for ((index, row) in rows.withIndex()) {
            val active = index == stage
            row.isSelected = active
            row.background = RippleDrawable(ColorStateList.valueOf((accent and 0x00ffffff) or 0x18000000),
                ui.background(stroke = if (active) accent else activity.getColor(R.color.separator)), null)
            row.setTextColor(activity.getColor(if (active) R.color.health_overview_green else R.color.text_primary))
        }
        description.text = mechanism.stages[stage]
        val item = path.steps[stage].destination?.let(atlas::get)
        val drawable = HealthAtlasUi.art(item ?: owner) ?: HealthAtlasUi.art(owner)
        art.setImageResource(requireNotNull(drawable))
        details.visibility = if (item != null) View.VISIBLE else View.GONE
        if (item != null) detailsText.text = activity.getString(R.string.health_atlas_endocrine_stage_details, item.name)
    }
}
