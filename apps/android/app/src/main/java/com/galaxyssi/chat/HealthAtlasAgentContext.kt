package com.galaxyssi.chat

import android.content.Context

/** Public catalogue and synthetic teaching state only. Personal values use the scoped consent flow. */
internal object HealthAtlasAgentContext {
    fun prompt(context: Context, atlas: HealthBodyAtlas, item: HealthAtlasItem?,
        simulation: HealthAtlasSimulation? = null, quantitative: HealthAtlasPhysiology? = null,
        topic: HealthAtlasResearchTopic? = null, elimination: HealthAtlasElimination? = null): String = buildString {
        if (item == null) {
            append(context.getString(R.string.health_atlas_ask_whole_context))
            return@buildString
        }
        val mechanism = atlas.mechanism(item)
        append(context.getString(R.string.health_atlas_ask_context, item.name, item.description, mechanism.title, mechanism.source))
        HealthAtlasPlates.forId(item.id)?.let { plate ->
            appendLine(); appendLine(plate.caption(context, atlas, item))
            appendLine(context.getString(R.string.health_atlas_art_note))
            plate.source?.let { appendLine(it) }
        }
        val physiology = topic == null || topic == HealthAtlasResearchTopic.PHYSIOLOGY
        if (physiology && simulation != null) {
            appendLine(); appendLine(context.getString(R.string.health_atlas_teaching_note))
            if (HealthAtlasCirculation.supports(item.id)) {
                appendLine(context.getString(R.string.health_atlas_circuit_scope))
                appendLine(context.getString(R.string.health_atlas_circuit_path))
                appendLine(HealthAtlasCirculation.SOURCE)
            }
            appendLine(context.getString(R.string.health_atlas_stage, simulation.stage + 1,
                mechanism.stages.size, mechanism.stages[simulation.stage]))
            if (item.id in setOf("heart", "cardio")) {
                appendLine(context.getString(R.string.health_atlas_heart_rate) + ": ${simulation.first} bpm")
                appendLine(context.getString(R.string.health_atlas_stroke_volume) + ": ${simulation.second} mL")
                appendLine(context.getString(R.string.health_atlas_cardiac_output) + ": " +
                    HealthAtlasPhysiologyText.number(simulation.cardiacOutput()) + " L/min")
                append(context.getString(R.string.health_atlas_cardiac_formula))
            }
        }
        if (physiology && quantitative != null && HealthAtlasPhysiologyKind.forItem(item.id) == quantitative.kind) {
            appendLine(); append(HealthAtlasPhysiologyText.context(context, quantitative))
        }
        if (topic != null) {
            appendLine(); appendLine(context.getString(topic.title))
            appendLine(context.getString(when (topic) {
                HealthAtlasResearchTopic.PHYSIOLOGY -> R.string.health_atlas_teaching_note
                HealthAtlasResearchTopic.DRUGS -> R.string.health_atlas_elimination_assumptions
                HealthAtlasResearchTopic.AGING -> R.string.health_atlas_aging_evidence
            }))
            if (topic == HealthAtlasResearchTopic.DRUGS) {
                val values = elimination ?: HealthAtlasElimination()
                appendLine(context.getString(R.string.health_atlas_elimination_summary, values.halfLifeHours,
                    values.elapsedHours, HealthAtlasPhysiologyText.number(values.percent)))
            }
            append(HealthAtlasResearchSources.forTopic(topic, mechanism).joinToString("\n"))
        }
    }.trim()
}
