package com.galaxyssi.chat

import android.app.Activity
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.PopupMenu

/** Public research only; interaction changes the selected concept, never a biological age or record. */
internal class HealthAtlasAgingPanel(private val activity: Activity, body: LinearLayout,
    private val atlas: HealthBodyAtlas, private val item: HealthAtlasItem, initial: HealthAtlasAgingSelection?,
    private val select: (HealthAtlasItem) -> Unit, private val source: (String) -> Unit) {
    private val ui = HealthCenterViews(activity)
    private val topicContent = ui.column().apply { tag = "atlas-aging-topic-content" }
    private val pickerValue = ui.text("", 16f, bold = true)
    var selection = initial ?: HealthAtlasAgingSelection(HealthAtlasAgingTopic.forItem(item.id))
        private set

    init {
        ui.add(body, ui.text(item.name, 18f, bold = true), 8)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_aging_scope), 13f, muted = true), 6)
        val picker = ui.row(activity.getString(R.string.health_atlas_aging_picker)) {}.apply {
            tag = "atlas-aging-picker"
            (getChildAt(0) as LinearLayout).addView(pickerValue)
            (getChildAt(1) as ImageView).rotation = -90f
            setOnClickListener(::showTopics)
        }
        ui.add(body, picker, 12)
        ui.add(body, topicContent, 10)
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_evidence), 18f, bold = true), 20)
        addSource(body, R.string.health_atlas_aging_source, HealthAtlasResearchSources.AGING, "aging")
        addSource(body, R.string.health_atlas_structure_source, atlas.mechanism(item).source, "structure")
        renderTopic()
    }

    private fun showTopics(anchor: View) {
        PopupMenu(activity, anchor).apply {
            HealthAtlasAgingTopic.entries.forEach { topic ->
                menu.add(0, topic.ordinal, topic.ordinal, topic.title).isChecked = topic == selection.topic
            }
            menu.setGroupCheckable(0, true, true)
            setOnMenuItemClickListener { value ->
                val topic = HealthAtlasAgingTopic.entries[value.itemId]
                if (topic != selection.topic) {
                    selection = HealthAtlasAgingSelection(topic)
                    renderTopic()
                }
                true
            }
            show()
        }
    }

    private fun renderTopic() {
        val topic = selection.topic
        val body = topicContent
        pickerValue.text = activity.getString(topic.title)
        body.removeAllViews()
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_aging_diagram_scope), 13f, muted = true))
        val steps = topic.steps(activity)
        val stage = ui.text(selection.stageLabel(activity, steps), 15f, bold = true).apply {
            tag = "atlas-aging-stage"
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        val mechanism = HealthAtlasMechanism("aging-${topic.name}", "teaching", activity.getString(topic.title),
            steps, chapter = "", reference = HealthAtlasResearchSources.AGING)
        ui.add(body, HealthAtlasProcessView(activity, mechanism) { index ->
            selection = selection.copy(step = index)
            stage.text = selection.stageLabel(activity, steps)
        }.apply { phase = selection.step / HealthAtlasAgingSelection.STEP_COUNT.toFloat() }, 4)
        ui.add(body, stage)
        ui.add(body, ui.text(activity.getString(topic.explanation), 15f), 8)
        topic.study?.let { study ->
            val card = ui.card().apply { tag = "atlas-aging-study" }
            ui.add(card, ui.text(activity.getString(R.string.health_atlas_aging_human_study), 14f, bold = true))
            ui.add(card, ui.text(activity.getString(study.sample), 18f, bold = true), 6)
            ui.add(card, ui.text(activity.getString(study.result), 15f), 8)
            ui.add(card, ui.text(activity.getString(study.limits), 13f, muted = true), 8)
            addSource(card, study.label, study.source, "aging-study")
            ui.add(body, card, 16)
        }
        ui.add(body, ui.text(activity.getString(R.string.health_atlas_aging_evidence), 13f, muted = true), 16)
        atlas[topic.exampleId]?.takeIf { it.id != item.id }?.let { target ->
            ui.add(body, ui.row(target.name, activity.getString(R.string.health_atlas_aging_related)) { select(target) }
                .apply { tag = "atlas-aging-related" }, 10)
        }
    }

    private fun addSource(body: LinearLayout, label: Int, url: String, key: String) {
        ui.add(body, ui.row(activity.getString(label)) { source(url) }.apply { tag = "atlas-source-$key" }, 8)
    }
}
