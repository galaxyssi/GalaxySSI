package com.galaxyssi.chat

import android.app.Activity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal class HealthAtlasPancreaticRoutes(private val activity: Activity, private val atlas: HealthBodyAtlas,
    private val selected: (HealthAtlasItem) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val exocrine = route("duct", R.drawable.health_atlas_digestive_pancreatic_acinar,
        R.string.health_atlas_digestive_routes_exocrine, R.string.health_atlas_digestive_routes_exocrine_chain, "pancreatic-duct")
    private val endocrine = route("blood", R.drawable.health_atlas_digestive_islet,
        R.string.health_atlas_digestive_routes_endo, R.string.health_atlas_digestive_routes_endo_chain, "pancreatic-islets")
    var stage = 0
        set(value) {
            require(value in 0..3)
            field = value
            style(exocrine, value in 0..2)
            style(endocrine, value == 0 || value == 3)
        }

    init {
        orientation = VERTICAL
        tag = "atlas-pancreatic-routes"
        ui.add(this, exocrine)
        ui.add(this, endocrine, 6)
        stage = 0
    }
    private fun route(key: String, picture: Int, title: Int, path: Int, id: String) =
        ui.row(activity.getString(title), activity.getString(path)) { atlas[id]?.let(selected) }.apply {
            tag = "atlas-pancreatic-route-$key"
            addView(ImageView(activity).apply {
                setImageResource(picture)
                scaleType = ImageView.ScaleType.FIT_CENTER
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, 0, LayoutParams(ui.dp(72), ui.dp(58)).apply { marginEnd = ui.dp(8) })
        }
    private fun style(view: View, active: Boolean) {
        view.isSelected = active
        val color = if (active) R.color.health_overview_green else R.color.separator
        view.background = ui.background(stroke = activity.getColor(color))
    }

    companion object {
        const val OWNER = "pancreas"
        const val SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/17-9-the-endocrine-pancreas"
    }
}

internal class HealthAtlasIsletStages(private val activity: Activity, private val atlas: HealthBodyAtlas,
    private val selected: (HealthAtlasItem) -> Unit) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private val illustration = ImageView(activity).apply {
        scaleType = ImageView.ScaleType.FIT_CENTER
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val title: TextView = ui.text("", 16f, bold = true)
    private val description: TextView = ui.text("", 13f, muted = true)
    var stage = 0
        set(value) {
            require(value in CELL_IDS.indices)
            field = value
            val item = requireNotNull(atlas[CELL_IDS[value]])
            illustration.setImageResource(requireNotNull(HealthAtlasPlates.forId(item.id)).drawable)
            title.text = item.name
            description.text = atlas.mechanism(requireNotNull(atlas[OWNER])).stages[value]
        }

    init {
        orientation = VERTICAL
        tag = "atlas-islet-stages"
        ui.add(this, ui.line().apply {
            tag = "atlas-islet-selected-cell"
            val padding = ui.dp(8)
            setPadding(padding, padding, padding, padding)
            background = ui.background(stroke = activity.getColor(R.color.separator))
            isFocusable = true
            setOnClickListener { selected(requireNotNull(atlas[CELL_IDS[stage]])) }
            addView(illustration, LayoutParams(ui.dp(96), ui.dp(76)).apply { marginEnd = ui.dp(10) })
            addView(ui.column().apply { addView(title); addView(description) }, LayoutParams(0, -2, 1f))
            addView(ImageView(activity).apply {
                setImageResource(R.drawable.ic_navigation_back)
                rotation = 180f
                imageTintList = android.content.res.ColorStateList.valueOf(activity.getColor(R.color.text_secondary))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, LayoutParams(ui.dp(20), ui.dp(20)).apply { marginStart = ui.dp(8) })
        })
        stage = 0
    }
    companion object {
        const val OWNER = "pancreatic-islets"
        val CELL_IDS = listOf("cell-pancreatic-beta-cell", "cell-pancreatic-alpha-cell",
            "cell-pancreatic-delta-cell", "cell-pancreatic-pp-cell")
    }
}
