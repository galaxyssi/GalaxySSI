package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.drawable.RippleDrawable
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

/** Representative mammalian ON routes, not an exhaustive circuit diagram. */
internal class HealthAtlasRetinaPath(activity: Activity, atlas: HealthBodyAtlas, mechanism: HealthAtlasMechanism,
    phase: (Int) -> Unit, select: (HealthAtlasItem) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val accent = activity.getColor(R.color.health_overview_green)
    private val border = activity.getColor(R.color.separator)
    private val nodes = listOf(
        R.string.health_atlas_sensory_retinal_rod_label,
        R.string.health_atlas_sensory_retinal_relay_rod,
        R.string.health_atlas_sensory_retinal_cone_label,
        R.string.health_atlas_sensory_retinal_ganglion,
    ).mapIndexed { index, key ->
        val label = activity.getString(key)
        val caption = if (index == 2) label + "\n\u2193\n" +
            activity.getString(R.string.health_atlas_sensory_retinal_relay_cone) else label
        ui.text(caption, 14f, bold = true).apply {
            gravity = Gravity.CENTER
            setPadding(ui.dp(8), ui.dp(8), ui.dp(8), ui.dp(8))
            minimumHeight = ui.dp(48)
            tag = "atlas-retina-node-$index"
            isFocusable = true
            contentDescription = mechanism.stages[index]
            setOnClickListener { phase(index) }
        }
    }
    private val description = ui.text("", 15f, bold = true).apply { tag = "atlas-retina-step-text" }
    private val actions = ui.column()
    private val destinations = listOf(
        listOf("cell-rod-photoreceptor"),
        listOf("cell-retinal-bipolar-cell", "cell-retinal-aii-amacrine-cell"),
        listOf("cell-cone-photoreceptor"),
        listOf("cell-retinal-ganglion-cell"),
    ).map { ids -> ids.map { id ->
        val item = requireNotNull(atlas[id])
        ui.row(item.name) { select(item) }.apply { tag = "atlas-retina-open-$id" }
    } }
    var stage = 0
        set(value) {
            require(value in nodes.indices)
            field = value
            bind()
        }

    init {
        orientation = VERTICAL
        tag = "atlas-retinal-path"
        val dim = ui.column().apply {
            ui.add(this, heading(R.string.health_atlas_sensory_retinal_rod_route))
            ui.add(this, nodes[0], 4)
            ui.add(this, arrow("\u2193"))
            ui.add(this, nodes[1])
        }
        val bright = ui.column().apply {
            ui.add(this, heading(R.string.health_atlas_sensory_retinal_cone_route))
            ui.add(this, nodes[2], 4)
        }
        val route = ui.column().apply {
            ui.add(this, ui.line().apply {
                gravity = Gravity.TOP
                addView(dim, LayoutParams(0, -2, 1f).apply { marginEnd = ui.dp(6) })
                addView(bright, LayoutParams(0, -2, 1f).apply { marginStart = ui.dp(6) })
            })
            ui.add(this, arrow("\u2198    \u2199"))
            ui.add(this, nodes[3])
        }
        ui.add(this, HealthAtlasFigureFrame(activity, route, "atlas-retina-figure",
            activeNode = { nodes[stage] }).apply {
            reserveCaption(description, mechanism.stages)
            ui.add(legend, description)
            ui.add(legend, ui.text(context.getString(R.string.health_atlas_sensory_retinal_scope), 11f, muted = true), 5)
        })
        ui.add(this, actions, 2)
        bind()
    }
    private fun heading(label: Int) = ui.text(context.getString(label), 13f, muted = true).apply { gravity = Gravity.CENTER }
    private fun arrow(symbol: String) = ui.text(symbol, 17f, muted = true).apply {
        gravity = Gravity.CENTER
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private fun bind() {
        for ((index, node) in nodes.withIndex()) {
            val active = index == stage
            node.isSelected = active
            node.background = RippleDrawable(ColorStateList.valueOf((accent and 0x00ffffff) or 0x18000000),
                ui.background(stroke = if (active) accent else border), null)
            node.setTextColor(if (active) accent else context.getColor(R.color.text_primary))
        }
        description.text = nodes[stage].contentDescription
        (description.parent?.parent as? HealthAtlasFigureFrame)?.invalidate()
        actions.removeAllViews()
        destinations[stage].forEach { ui.add(actions, it) }
    }

    companion object {
        const val OWNER = "retina"
        const val SOURCE = "https://pubmed.ncbi.nlm.nih.gov/28856684/"
    }
}
