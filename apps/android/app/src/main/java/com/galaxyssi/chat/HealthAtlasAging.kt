package com.galaxyssi.chat

import android.content.Context
import androidx.annotation.ArrayRes
import androidx.annotation.StringRes

internal enum class HealthAtlasAgingStudy(val source: String, @StringRes val label: Int,
    @StringRes val sample: Int, @StringRes val result: Int, @StringRes val limits: Int) {
    TELOMERES("https://pmc.ncbi.nlm.nih.gov/articles/PMC3615479/", R.string.health_atlas_aging_study_telomeres,
        R.string.health_atlas_aging_sample_telomeres, R.string.health_atlas_aging_result_telomeres,
        R.string.health_atlas_aging_limits_telomeres),
    T_CELLS("https://pubmed.ncbi.nlm.nih.gov/19485966/", R.string.health_atlas_aging_study_tcells,
        R.string.health_atlas_aging_sample_tcells, R.string.health_atlas_aging_result_tcells,
        R.string.health_atlas_aging_limits_tcells),
}

internal enum class HealthAtlasAgingTopic(@StringRes val title: Int, @ArrayRes private val stages: Int,
    @StringRes val explanation: Int, val exampleId: String, val study: HealthAtlasAgingStudy? = null) {
    GENOME(R.string.health_atlas_aging_topic_genome, R.array.health_atlas_aging_steps_genome,
        R.string.health_atlas_aging_explain_genome, "epidermis"),
    TELOMERES(R.string.health_atlas_aging_topic_telomeres, R.array.health_atlas_aging_steps_telomeres,
        R.string.health_atlas_aging_explain_telomeres, "skin-organ", HealthAtlasAgingStudy.TELOMERES),
    EPIGENETICS(R.string.health_atlas_aging_topic_epigenetics, R.array.health_atlas_aging_steps_epigenetics,
        R.string.health_atlas_aging_explain_epigenetics, "cell-hepatocyte"),
    PROTEINS(R.string.health_atlas_aging_topic_proteins, R.array.health_atlas_aging_steps_proteins,
        R.string.health_atlas_aging_explain_proteins, "cell-neuron"),
    AUTOPHAGY(R.string.health_atlas_aging_topic_autophagy, R.array.health_atlas_aging_steps_autophagy,
        R.string.health_atlas_aging_explain_autophagy, "cell-skeletal-myocyte"),
    NUTRIENTS(R.string.health_atlas_aging_topic_nutrients, R.array.health_atlas_aging_steps_nutrients,
        R.string.health_atlas_aging_explain_nutrients, "pancreatic-islets"),
    MITOCHONDRIA(R.string.health_atlas_aging_topic_mitochondria, R.array.health_atlas_aging_steps_mitochondria,
        R.string.health_atlas_aging_explain_mitochondria, "cell-cardiomyocyte"),
    SENESCENCE(R.string.health_atlas_aging_topic_senescence, R.array.health_atlas_aging_steps_senescence,
        R.string.health_atlas_aging_explain_senescence, "cell-t-cell", HealthAtlasAgingStudy.T_CELLS),
    STEM_CELLS(R.string.health_atlas_aging_topic_stem_cells, R.array.health_atlas_aging_steps_stem_cells,
        R.string.health_atlas_aging_explain_stem_cells, "cell-hematopoietic-stem-cell"),
    SIGNALING(R.string.health_atlas_aging_topic_signaling, R.array.health_atlas_aging_steps_signaling,
        R.string.health_atlas_aging_explain_signaling, "cell-fibroblast"),
    INFLAMMATION(R.string.health_atlas_aging_topic_inflammation, R.array.health_atlas_aging_steps_inflammation,
        R.string.health_atlas_aging_explain_inflammation, "cell-macrophage"),
    DYSBIOSIS(R.string.health_atlas_aging_topic_dysbiosis, R.array.health_atlas_aging_steps_dysbiosis,
        R.string.health_atlas_aging_explain_dysbiosis, "colon");

    fun steps(context: Context): List<String> = context.resources.getStringArray(stages).toList()

    companion object {
        fun forItem(id: String) = entries.firstOrNull { it.exampleId == id } ?: when (id) {
            "heart", "cardio", "muscle" -> MITOCHONDRIA
            "skin" -> TELOMERES
            "endocrine", "pancreas", "cell-pancreatic-beta-cell" -> NUTRIENTS
            "immune", "thymus" -> SENESCENCE
            "bone-marrow" -> STEM_CELLS
            "nervous", "brain" -> PROTEINS
            "gut", "digestive", "large-intestine" -> DYSBIOSIS
            else -> GENOME
        }
    }
}

internal data class HealthAtlasAgingSelection(val topic: HealthAtlasAgingTopic, val step: Int = 0) {
    init { require(step in 0 until STEP_COUNT) }

    fun stageLabel(context: Context, steps: List<String> = topic.steps(context)) =
        context.getString(R.string.health_atlas_stage, step + 1, STEP_COUNT, steps[step])

    fun publicContext(context: Context) = buildString {
        appendLine(context.getString(R.string.health_atlas_aging_scope))
        appendLine(context.getString(topic.title))
        appendLine(context.getString(R.string.health_atlas_aging_diagram_scope))
        appendLine(stageLabel(context))
        appendLine(context.getString(topic.explanation))
        topic.study?.let {
            appendLine(context.getString(it.label))
            appendLine(context.getString(it.sample)); appendLine(context.getString(it.result))
            appendLine(context.getString(it.limits)); appendLine(it.source)
        }
    }.trim()

    companion object {
        const val STEP_COUNT = 4
        fun restore(topicName: String?, step: Int): HealthAtlasAgingSelection? {
            val topic = HealthAtlasAgingTopic.entries.firstOrNull { it.name == topicName } ?: return null
            return if (step in 0 until STEP_COUNT) HealthAtlasAgingSelection(topic, step) else null
        }
    }
}
