package com.galaxyssi.chat

import android.content.Context

/** Public catalogue and synthetic teaching state only. Personal values use the scoped consent flow. */
internal object HealthAtlasAgentContext {
    fun prompt(context: Context, atlas: HealthBodyAtlas, item: HealthAtlasItem?,
        simulation: HealthAtlasSimulation? = null, quantitative: HealthAtlasPhysiology? = null,
        topic: HealthAtlasResearchTopic? = null, elimination: HealthAtlasElimination? = null,
        drugs: HealthAtlasDrugState? = null, artworkView: String? = null,
        aging: HealthAtlasAgingSelection? = null): String = buildString {
        if (item == null) {
            append(context.getString(R.string.health_atlas_ask_whole_context))
            return@buildString
        }
        val mechanism = atlas.mechanism(item)
        append(context.getString(R.string.health_atlas_ask_context, item.name, item.description, mechanism.title, mechanism.source))
        HealthAtlasPlates.forId(item.id, artworkView)?.let { plate ->
            appendLine(); appendLine(plate.caption(context, atlas, item))
            appendLine(context.getString(R.string.health_atlas_art_note))
            plate.source?.let { appendLine(it) }
            if (plate.features.isNotEmpty()) appendLine(context.getString(R.string.health_atlas_feature_context,
                plate.features.joinToString(", ") { context.getString(it.title) }))
        }
        if (item.kind == HealthAtlasKind.TISSUE) {
            appendLine(context.getString(R.string.health_atlas_tissue_locations) + ": " +
                item.locatedIn.mapNotNull(atlas::get).joinToString(", ") { it.name })
            appendLine(context.getString(R.string.health_atlas_tissue_cell_examples) + ": " +
                atlas.cells(item).joinToString(", ") { it.name })
        }
        val physiology = topic == null || topic == HealthAtlasResearchTopic.PHYSIOLOGY
        if (physiology && simulation != null) {
            appendLine(); appendLine(context.getString(R.string.health_atlas_teaching_note))
            if (HealthAtlasCirculation.supports(item.id)) {
                appendLine(context.getString(R.string.health_atlas_circuit_scope))
                appendLine(context.getString(R.string.health_atlas_circuit_path))
                appendLine(HealthAtlasCirculation.SOURCE)
            }
            if (HealthAtlasGasExchange.supports(item.id)) {
                appendLine(context.getString(R.string.health_atlas_gas_scope))
                HealthAtlasGasExchange.gradients.forEach { appendLine(HealthAtlasGasExchangeText.summary(context, it)) }
                appendLine(HealthAtlasGasExchange.SOURCE)
            }
            appendLine(context.getString(R.string.health_atlas_stage, simulation.stage + 1,
                mechanism.stages.size, mechanism.stages[simulation.stage]))
            HealthAtlasGermlineText.context(context, item.id, simulation.stage)?.let { appendLine(it) }
            if (HealthAtlasValve.supports(item.id)) appendLine(HealthAtlasValveText.publicContext(context, atlas, item.id, simulation.stage))
            if (item.id == HealthAtlasPhagocytosisView.OWNER)
                appendLine(context.getString(R.string.health_atlas_phagocytosis_scope))
            if (item.id == HealthAtlasPodocyteView.OWNER)
                appendLine(context.getString(R.string.health_atlas_podocyte_scope))
            if (item.id == HealthAtlasPancreaticRoutes.OWNER) {
                appendLine(context.getString(R.string.health_atlas_digestive_routes_scope))
                appendLine(context.getString(R.string.health_atlas_digestive_routes_exocrine_chain))
                appendLine(context.getString(R.string.health_atlas_digestive_routes_endo_chain))
                appendLine(HealthAtlasPancreaticRoutes.SOURCE)
            }
            if (item.id == HealthAtlasIsletStages.OWNER)
                appendLine(context.getString(R.string.health_atlas_digestive_islets_scope))
            HealthAtlasEndocrinePath.all[item.id]?.let { appendLine(context.getString(it.scope)) }
            if (item.id == HealthAtlasRetinaPath.OWNER) {
                appendLine(context.getString(R.string.health_atlas_sensory_retinal_scope))
                appendLine(context.getString(R.string.health_atlas_sensory_retinal_relay_rod))
                appendLine(HealthAtlasRetinaPath.SOURCE)
            }
            if (item.id == HealthAtlasSweatView.OWNER) appendLine(context.getString(R.string.health_atlas_context_sweat_scope))
            if (item.id == "hair-follicles") appendLine(context.getString(R.string.health_atlas_context_hair_scope))
            HealthAtlasLymphOrgans[item.id]?.let { lesson ->
                appendLine(context.getString(R.string.health_atlas_lymph_illustration_scope))
                appendLine(context.getString(lesson.plate.features[lesson.stageFeatures[simulation.stage]].title))
                if (item.id == "thoracic-duct") appendLine(context.getString(R.string.health_atlas_lymph_duct_orientation))
            }
            if (item.id == HealthAtlasSarcomere.OWNER) {
                appendLine(context.getString(R.string.health_atlas_sarcomere_ratio,
                    HealthAtlasSarcomere(simulation.stage).relativeLengthPercent))
                appendLine(context.getString(R.string.health_atlas_sarcomere_scope))
            }
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
                HealthAtlasResearchTopic.DRUGS -> if (drugs?.mode == HealthAtlasDrugMode.TWO)
                    R.string.health_atlas_drug_models else R.string.health_atlas_elimination_assumptions
                HealthAtlasResearchTopic.AGING -> R.string.health_atlas_aging_evidence
            }))
            if (topic == HealthAtlasResearchTopic.DRUGS) {
                if (drugs?.mode == HealthAtlasDrugMode.TWO) appendLine(HealthAtlasDistributionText.prompt(context, drugs.distribution))
                else {
                    val values = elimination ?: HealthAtlasElimination()
                    appendLine(context.getString(R.string.health_atlas_elimination_summary, values.halfLifeHours,
                        values.elapsedHours, HealthAtlasPhysiologyText.number(values.percent)))
                }
            }
            if (topic == HealthAtlasResearchTopic.AGING && aging != null) appendLine(aging.publicContext(context))
            append(HealthAtlasResearchSources.forTopic(topic, mechanism).joinToString("\n"))
        }
    }.trim()
}
