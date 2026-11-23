package com.galaxyssi.chat

import android.app.Activity
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.PointF
import android.graphics.Typeface
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

internal object HealthAtlasUi {
    fun tabs(activity: Activity, labels: List<Int>, selected: Int, tagPrefix: String = "atlas-tab",
        tagKey: (Int) -> String = { it.toString() }, compact: Boolean = false,
        action: (Int) -> Unit): LinearLayout {
        val ui = HealthCenterViews(activity)
        return ui.line().apply {
            setBackgroundColor(activity.getColor(if (compact) R.color.page_bg else R.color.surface_bg))
            labels.forEachIndexed { index, label -> addView(ui.column().apply {
                addView(ui.text(activity.getString(label), 14f, bold = index == selected).apply {
                    tag = "$tagPrefix-${tagKey(index)}"; gravity = Gravity.CENTER; minimumHeight = ui.dp(if (compact) 44 else 48)
                    isSelected = index == selected; isFocusable = true; setOnClickListener { action(index) }
                    setTextColor(activity.getColor(if (index == selected) R.color.health_overview_green else R.color.text_primary))
                }, LinearLayout.LayoutParams(-1, -2))
                addView(View(activity).apply { setBackgroundColor(if (index == selected) activity.getColor(R.color.health_overview_green) else Color.TRANSPARENT) },
                    LinearLayout.LayoutParams(-1, ui.dp(if (compact) 2 else 3)).apply {
                        marginStart = ui.dp(if (compact) 24 else 18); marginEnd = marginStart
                    })
            }, LinearLayout.LayoutParams(0, -2, 1f)) }
        }
    }
    fun disclosure(activity: Activity, title: String, key: String, initial: Boolean = false,
        changed: (Boolean) -> Unit): LinearLayout {
        lateinit var row: LinearLayout
        fun update(open: Boolean) {
            row.isSelected = open
            row.getChildAt(row.childCount - 1).rotation = if (open) 90f else 270f
            if (android.os.Build.VERSION.SDK_INT >= 30) row.stateDescription = activity.getString(
                if (open) R.string.health_sources_devices_expanded else R.string.health_sources_devices_collapsed)
        }
        row = HealthCenterViews(activity).row(title) {
            val open = !row.isSelected
            update(open); changed(open)
        }.apply { tag = key }
        update(initial)
        return row
    }
    fun icon(item: HealthAtlasItem): Int = if (item.kind == HealthAtlasKind.TISSUE) R.drawable.ic_input_menu_layers
        else if (item.kind == HealthAtlasKind.CELL || item.kind == HealthAtlasKind.FRAGMENT)
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
    fun illustrationNotes(activity: Activity, legend: LinearLayout, caption: String, item: HealthAtlasItem?,
        note: Int = R.string.health_atlas_illustration) {
        val ui = HealthCenterViews(activity)
        ui.add(legend, ui.text(caption, 14f, bold = true).apply {
            tag = "atlas-art-caption"
            setTextColor(activity.getColor(R.color.health_overview_green))
        })
        item?.let { ui.add(legend, ui.text(it.description, 14f).apply { tag = "atlas-art-explanation" }, 3) }
        ui.add(legend, ui.text(activity.getString(note), 11f, muted = true), 5)
    }
    fun row(activity: Activity, item: HealthAtlasItem, data: HealthBodyAtlas, action: () -> Unit): LinearLayout {
        val ui = HealthCenterViews(activity)
        val system = data[item.systems.first()]
        return ui.row(item.name, if (item.kind == HealthAtlasKind.SYSTEM) item.description else
            if (item.kind == HealthAtlasKind.TISSUE) activity.getString(R.string.health_atlas_tissues)
            else item.systems.mapNotNull(data::get).joinToString(" · ") { it.name }, action).apply {
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
    fun art(item: HealthAtlasItem?): Int? = HealthAtlasPlates.forId(item?.id)?.drawable

    fun wholeBodyActions(activity: Activity, data: HealthBodyAtlas, item: HealthAtlasItem,
        structure: () -> Unit, metrics: () -> Unit, trend: () -> Unit): LinearLayout {
        val ui = HealthCenterViews(activity)
        val card = ui.card().apply {
            tag = "atlas-whole-selection"
            setPadding(ui.dp(6), ui.dp(4), ui.dp(6), ui.dp(4))
        }
        val context = item.systems.mapNotNull(data::get).filterNot { it.id == item.id }.joinToString(" · ") { it.name }
        ui.add(card, ui.row(item.name, context, structure).apply {
            tag = "atlas-whole-structure-${item.id}"
            addView(ImageView(activity).apply {
                val artwork = art(item)
                setImageResource(artwork ?: icon(item))
                scaleType = ImageView.ScaleType.FIT_CENTER
                if (artwork == null) imageTintList = ColorStateList.valueOf(activity.getColor(R.color.health_overview_green))
                importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
            }, 0, LinearLayout.LayoutParams(ui.dp(38), ui.dp(38)).apply { marginEnd = ui.dp(10) })
        })
        card.addView(View(activity).apply { setBackgroundColor(activity.getColor(R.color.separator)) },
            LinearLayout.LayoutParams(-1, ui.dp(1)))
        val actions = ui.line().apply { gravity = Gravity.TOP; tag = "atlas-whole-actions" }
        fun action(id: String, label: Int, drawable: Int, enabled: Boolean = true, click: () -> Unit) {
            val accent = activity.getColor(R.color.health_overview_green)
            actions.addView(Button(activity, null, android.R.attr.borderlessButtonStyle).apply {
                tag = "atlas-whole-action-$id"
                text = activity.getString(label); isAllCaps = false; textSize = 13f; letterSpacing = 0f
                setTextColor(activity.getColor(if (enabled) R.color.text_primary else R.color.text_secondary))
                setPadding(ui.dp(2), ui.dp(5), ui.dp(2), ui.dp(5)); minimumWidth = 0; minimumHeight = ui.dp(48)
                compoundDrawablePadding = ui.dp(3)
                val image = activity.getDrawable(drawable)?.mutate()?.apply {
                    setTint(if (enabled) accent else activity.getColor(R.color.text_secondary))
                    setBounds(0, 0, ui.dp(16), ui.dp(16))
                }
                setCompoundDrawablesRelative(null, image, null, null)
                isEnabled = enabled
                if (enabled) setOnClickListener { click() }
            }, LinearLayout.LayoutParams(0, -2, 1f))
        }
        action("structure", R.string.health_atlas_structure, R.drawable.ic_input_menu_layers, click = structure)
        action("metrics", R.string.health_atlas_quick_metrics, R.drawable.ic_health_profile, click = metrics)
        action("trend", R.string.health_atlas_quick_trend, R.drawable.ic_health_data_chart,
            enabled = HealthAtlasMetrics.forItem(item).isNotEmpty(), click = trend)
        ui.add(card, actions)
        return card
    }
}

internal class HealthAtlasArtwork(
    private val activity: Activity, private val data: HealthBodyAtlas, private val item: HealthAtlasItem?,
    private val selected: (HealthAtlasItem) -> Unit, private val zoom: (HealthAtlasPlate, String) -> Unit,
    private val openSource: (String) -> Unit, initialView: String? = null,
    private val steps: MutableMap<String, Int> = mutableMapOf(),
    private val viewChanged: (String) -> Unit = {},
) : LinearLayout(activity) {
    private val ui = HealthCenterViews(activity)
    private var layers: android.app.AlertDialog? = null
    private var currentView = HealthAtlasPlates.forId(item?.id, initialView)?.viewKey
    init {
        orientation = VERTICAL
        renderPlate()
    }
    private fun renderPlate() {
        layers?.dismiss(); layers = null
        removeAllViews()
        val views = HealthAtlasPlates.viewsForId(item?.id)
        val plate = HealthAtlasPlates.forId(item?.id, currentView)
        if (plate != null) {
            if (views.size > 1) addView(HealthAtlasUi.tabs(activity,
                views.mapIndexed { index, view -> view.selectorLabel ?:
                    if (index == 0) R.string.health_atlas_view_front else R.string.health_atlas_view_back },
                views.indexOf(plate), "atlas-view") { index ->
                currentView = views[index].viewKey
                currentView?.let(viewChanged)
                renderPlate()
            })
            val resource = plate.drawable
            val caption = plate.caption(activity, data, item)
            val description = (item?.name ?: activity.getString(R.string.health_atlas_whole)) + " · " + caption
            val labeled = if (plate.hasLabels) HealthAtlasLabeledImage(activity, plate,
                description, data, item?.id, numbered = true, selected = selected) else null
            val art = object : FrameLayout(activity) {
                override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
                    labeled?.measure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED))
                    val required = maxOf(ui.dp(if (item == null) 366 else 266), labeled?.measuredHeight ?: 0)
                    super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(resolveSize(required, heightMeasureSpec), MeasureSpec.EXACTLY))
                }
            }
            val picture = labeled?.image ?: ImageView(activity).apply {
                setImageResource(resource); scaleType = ImageView.ScaleType.FIT_CENTER
                contentDescription = description
                tag = "atlas-art-image"
            }
            val target = labeled ?: picture
            val viewport = GalaxySSIPinchZoomViewport(activity).apply { attach(target) }
            art.addView(viewport, FrameLayout.LayoutParams(-1, -1))
            val controls = ui.line().apply {
                gravity = Gravity.END
                val choices = if (item == null) data.systems else plate.markers.mapNotNull { data[it.id] }
                    .filter { it.id != item.id }.distinctBy { it.id }
                if (choices.isNotEmpty() || plate.features.isNotEmpty()) addView(ui.icon(R.drawable.ic_input_menu_layers, R.string.health_atlas_layers) {
                    val labels = choices.map { it.name } + plate.features.map { activity.getString(it.title) }
                    layers = android.app.AlertDialog.Builder(activity).setTitle(R.string.health_atlas_layers)
                        .setItems(labels.toTypedArray()) { _, index ->
                            if (index < choices.size) selected(choices[index])
                            else labeled?.showFeature(plate.features[index - choices.size])
                        }
                        .setNegativeButton(android.R.string.cancel, null).show()
                }.apply { tag = "atlas-layers" })
                addView(ui.icon(R.drawable.ic_reset_data, R.string.health_atlas_reset) {
                    viewport.resetZoom()
                }.apply { tag = "atlas-art-reset" })
                addView(ui.icon(R.drawable.ic_screen_assistant_expand, R.string.health_body_zoom) {
                    zoom(plate, description)
                }.apply { tag = "atlas-fullscreen" })
                plate.source?.let { url ->
                    addView(ui.icon(R.drawable.ic_rich_file, R.string.health_atlas_plate_source) {
                        openSource(url)
                    }.apply { tag = "atlas-source-structure" })
                }
            }
            val focus = plate.markers.firstOrNull { it.id == item?.id }?.let { PointF(it.x, it.y) }
                ?: if (plate.owner == "cell-pancreatic-beta-cell") PointF(.82f, .44f) else null
            var subjectPoint = focus
            addView(HealthAtlasFigureFrame(activity, art, "atlas-structure-figure", controls,
                subject = picture, subjectPoint = { subjectPoint }).apply {
                HealthAtlasUi.illustrationNotes(activity, legend, if (item == null) description else caption, item)
                if (labeled != null) bindSteps(this, plate, labeled, focus) { subjectPoint = it }
            }, LayoutParams(-1, -2))
        } else {
            val entry = requireNotNull(item)
            val symbol = ImageView(activity).apply {
                setImageResource(HealthAtlasUi.icon(entry))
                imageTintList = ColorStateList.valueOf(activity.getColor(R.color.health_overview_green))
                scaleType = ImageView.ScaleType.FIT_CENTER
                minimumHeight = ui.dp(132)
                setPadding(ui.dp(36), ui.dp(22), ui.dp(36), ui.dp(30))
                importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
            }
            addView(HealthAtlasFigureFrame(activity, symbol, "atlas-structure-figure", subject = symbol).apply {
                HealthAtlasUi.illustrationNotes(activity, legend, entry.name, entry, R.string.health_atlas_symbol_only)
            }, LayoutParams(-1, -2))
        }
    }

    private fun bindSteps(figure: HealthAtlasFigureFrame, plate: HealthAtlasPlate, labeled: HealthAtlasLabeledImage,
        overviewPoint: PointF?, setPoint: (PointF?) -> Unit) {
        val key = "${item?.id.orEmpty()}|${plate.viewKey.orEmpty()}"
        val landmarks = (plate.markers.mapNotNull { marker ->
            data[marker.id]?.let { Triple(marker, it.name, it.description) }
        } + plate.features.map { Triple(it.marker, activity.getString(it.title), activity.getString(it.explanation)) })
            .sortedBy { it.first.y }
        if (landmarks.isEmpty()) return
        val title = figure.findViewWithTag<TextView>("atlas-art-caption")
        val body = figure.findViewWithTag<TextView>("atlas-art-explanation") ?: ui.text(
            activity.getString(R.string.health_atlas_body_overview), 14f,
        ).apply {
            figure.legend.addView(this, 1, LayoutParams(-1, -2).apply { topMargin = ui.dp(3) })
        }
        val titles = listOf(title.text.toString()) + landmarks.map { it.second }
        val descriptions = listOf(body.text.toString()) + landmarks.map { it.third }
        body.maxLines = 5
        body.ellipsize = TextUtils.TruncateAt.END
        figure.reserveCaption(title, titles)
        figure.reserveCaption(body, descriptions)
        var step = (steps[key] ?: 0).coerceIn(0, landmarks.size)
        val position = ui.text("", 11f, muted = true).apply {
            gravity = Gravity.CENTER
            tag = "atlas-structure-step"
            accessibilityLiveRegion = ACCESSIBILITY_LIVE_REGION_POLITE
        }
        lateinit var previous: View
        lateinit var next: View
        fun show(index: Int) {
            step = index.coerceIn(0, landmarks.size)
            if (step == 0) steps.remove(key) else steps[key] = step
            val mark = landmarks.getOrNull(step - 1)?.first
            setPoint(mark?.let { PointF(it.x, it.y) } ?: overviewPoint)
            labeled.highlightedId = mark?.id
            title.text = titles[step]
            body.text = descriptions[step]
            position.text = if (step == 0) activity.getString(R.string.health_atlas_step_overview)
                else activity.getString(R.string.health_atlas_step_position, step, landmarks.size)
            previous.isEnabled = step > 0
            next.isEnabled = step < landmarks.size
            previous.alpha = if (previous.isEnabled) 1f else .4f
            next.alpha = if (next.isEnabled) 1f else .4f
            figure.invalidate()
        }
        ui.add(figure.legend, position, 5)
        figure.legend.addView(ui.line().apply {
            previous = ui.icon(R.drawable.ic_navigation_back, R.string.health_body_previous_step) { show(step - 1) }
                .apply { tag = "atlas-structure-previous" }
            next = ui.icon(R.drawable.ic_navigation_back, R.string.health_body_next_step) { show(step + 1) }
                .apply { tag = "atlas-structure-next"; rotation = 180f }
            addView(previous, LayoutParams(0, ui.dp(48), 1f))
            addView(next, LayoutParams(0, ui.dp(48), 1f))
        }, LayoutParams(-1, -2))
        body.setOnClickListener {
            android.app.AlertDialog.Builder(activity).setTitle(titles[step]).setMessage(descriptions[step])
                .setPositiveButton(android.R.string.ok, null).show()
        }
        show(step)
    }

    override fun onDetachedFromWindow() { layers?.dismiss(); layers = null; super.onDetachedFromWindow() }
}
