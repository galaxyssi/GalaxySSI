package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal object HealthAtlasUi {
    fun tabs(activity: Activity, labels: List<Int>, selected: Int, tagPrefix: String = "atlas-tab", action: (Int) -> Unit): LinearLayout {
        val ui = HealthCenterViews(activity)
        return ui.line().apply {
            setBackgroundColor(activity.getColor(R.color.surface_bg))
            labels.forEachIndexed { index, label -> addView(ui.column().apply {
                addView(ui.text(activity.getString(label), 14f, bold = index == selected).apply {
                    tag = "$tagPrefix-$index"; gravity = Gravity.CENTER; minimumHeight = ui.dp(48)
                    isSelected = index == selected; isFocusable = true; setOnClickListener { action(index) }
                    setTextColor(activity.getColor(if (index == selected) R.color.health_overview_green else R.color.text_primary))
                }, LinearLayout.LayoutParams(-1, -2))
                addView(View(activity).apply { setBackgroundColor(if (index == selected) activity.getColor(R.color.health_overview_green) else Color.TRANSPARENT) },
                    LinearLayout.LayoutParams(-1, ui.dp(3)).apply { marginStart = ui.dp(18); marginEnd = ui.dp(18) })
            }, LinearLayout.LayoutParams(0, -2, 1f)) }
        }
    }
    fun icon(item: HealthAtlasItem): Int = if (item.kind == HealthAtlasKind.CELL || item.kind == HealthAtlasKind.FRAGMENT)
        R.drawable.ic_atlas_microscope else when (item.systems.first()) {
        "nervous" -> R.drawable.ic_atlas_brain
        "sensory" -> R.drawable.ic_atlas_eye
        "cardio" -> R.drawable.ic_atlas_heart_pulse
        "respiratory" -> R.drawable.ic_atlas_wind
        "gut" -> R.drawable.ic_atlas_route
        "digestive" -> R.drawable.ic_atlas_droplets
        "urinary" -> R.drawable.ic_atlas_droplet
        "endocrine" -> R.drawable.ic_atlas_network
        "immune" -> R.drawable.ic_atlas_shield_plus
        "male" -> R.drawable.ic_atlas_mars
        "female" -> R.drawable.ic_atlas_venus
        "skin" -> R.drawable.ic_atlas_fingerprint_pattern
        "skeletal" -> R.drawable.ic_atlas_bone
        "muscle" -> R.drawable.ic_atlas_biceps_flexed
        else -> R.drawable.ic_health_body
    }
    fun row(activity: Activity, item: HealthAtlasItem, data: HealthBodyAtlas, action: () -> Unit): LinearLayout {
        val ui = HealthCenterViews(activity)
        val system = data[item.systems.first()]
        return ui.row(item.name, if (item.kind == HealthAtlasKind.SYSTEM) item.description else
            item.systems.mapNotNull(data::get).joinToString(" · ") { it.name }, action).apply {
            val text = getChildAt(0) as LinearLayout
            (text.getChildAt(0) as TextView).maxLines = 2
            if (text.childCount > 1) (text.getChildAt(1) as TextView).apply { maxLines = 2; ellipsize = android.text.TextUtils.TruncateAt.END }
            addView(ImageView(activity).apply {
                setImageResource(icon(item)); imageTintList = ColorStateList.valueOf(runCatching { Color.parseColor(system?.color) }
                    .getOrDefault(activity.getColor(R.color.health_overview_green)))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, 0, LinearLayout.LayoutParams(ui.dp(24), ui.dp(24)).apply { marginEnd = ui.dp(12) })
        }
    }
    fun art(item: HealthAtlasItem?): Int? = when (item?.id) {
        null -> R.drawable.health_atlas_body
        "heart", "cardio", "atria", "ventricles", "heart-valves", "coronary-vessels" -> R.drawable.health_atlas_heart
        "cell-pancreatic-beta-cell" -> R.drawable.health_atlas_beta_cell
        else -> null
    }
}

internal class HealthAtlasArtwork(
    private val activity: Activity, data: HealthBodyAtlas, item: HealthAtlasItem?,
    selected: (HealthAtlasItem) -> Unit, zoom: (Int, String) -> Unit,
) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private var layers: android.app.AlertDialog? = null
    init {
        orientation = VERTICAL
        val resource = HealthAtlasUi.art(item)
        if (resource != null) {
            val art = FrameLayout(activity)
            val labeled = if (resource != R.drawable.health_atlas_beta_cell) HealthAtlasLabeledImage(activity, resource,
                item?.name ?: activity.getString(R.string.health_atlas_whole), data, item == null, selected) else null
            val picture = labeled?.image ?: ImageView(activity).apply {
                setImageResource(resource); scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = item?.name ?: activity.getString(R.string.health_atlas_whole)
                tag = "atlas-art-image"
                setPadding(ui.dp(12), ui.dp(8), ui.dp(48), ui.dp(8))
            }
            val target = labeled ?: picture
            var viewport = GalaxySSIPinchZoomViewport(activity).apply { attach(target) }
            art.addView(viewport, FrameLayout.LayoutParams(-1, -1))
            val controls = (if (item == null) ui.column() else ui.line()).apply {
                gravity = Gravity.END
                addView(ui.icon(R.drawable.ic_input_menu_layers, R.string.health_atlas_layers) {
                    val choices = if (item == null) data.systems else (data.children(item) + data.cells(item)).distinctBy { it.id }
                    if (choices.isNotEmpty()) layers = android.app.AlertDialog.Builder(activity).setTitle(R.string.health_atlas_layers)
                        .setItems(choices.map { it.name }.toTypedArray()) { _, index -> selected(choices[index]) }
                        .setNegativeButton(android.R.string.cancel, null).show()
                }.apply { tag = "atlas-layers" })
                addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
                    viewport.removeAllViews(); art.removeView(viewport)
                    target.scaleX = 1f; target.scaleY = 1f; target.translationX = 0f; target.translationY = 0f
                    viewport = GalaxySSIPinchZoomViewport(activity).apply { attach(target) }
                    art.addView(viewport, 0, FrameLayout.LayoutParams(-1, -1))
                }.apply { tag = "atlas-art-reset" })
                addView(ui.icon(R.drawable.ic_screen_assistant_expand, R.string.health_body_zoom) {
                    zoom(resource, item?.name ?: activity.getString(R.string.health_atlas_whole))
                }.apply { tag = "atlas-fullscreen" })
            }
            if (item == null) art.addView(controls, FrameLayout.LayoutParams(ui.dp(48), -2, Gravity.END or Gravity.BOTTOM))
            addView(art, LayoutParams(-1, ui.dp(if (item == null) 400 else 300)))
            if (item != null) addView(controls, LayoutParams(-1, ui.dp(48)))
            addView(ui.text(activity.getString(R.string.health_atlas_illustration), 11f, muted = true))
        } else {
            // Related structures are shown explicitly instead of reusing an unrelated anatomical picture.
            addView(ui.text(item!!.name, 22f, bold = true).apply { setPadding(0, ui.dp(24), 0, ui.dp(8)) })
            val relations = (data.children(item) + if (item.kind == HealthAtlasKind.CELL) data.children(item) else data.parents(item)).distinctBy { it.id }
            relations.take(4).forEach { related -> ui.add(this, ui.row(related.name) { selected(related) }) }
        }
    }
    override fun onDetachedFromWindow() { layers?.dismiss(); layers = null; super.onDetachedFromWindow() }
}
