package com.galaxyssi.chat

internal enum class HealthBodyLayer(val label: Int) {
    ORGAN(R.string.health_body_organ), TISSUE(R.string.health_body_tissue),
    CELL(R.string.health_body_cell), MOLECULE(R.string.health_body_molecule)
}

internal enum class HealthBodyTopic(val label: Int) {
    CIRCULATION(R.string.health_body_circulation), BREATHING(R.string.health_body_breathing),
    METABOLISM(R.string.health_body_metabolism), NERVES(R.string.health_body_nerves),
    DIGESTION(R.string.health_body_digestion), KIDNEYS(R.string.health_body_kidneys)
}

internal enum class HealthBodyGlyph { HEART, LUNG, TISSUE, AIR, CELL, MOLECULE, NEURON, FOOD, FILTER }
internal enum class HealthBodyTone { FLOW, OXYGEN, RETURN, SIGNAL, ENERGY }
internal data class HealthBodyNode(val label: Int, val glyph: HealthBodyGlyph)
internal data class HealthBodyStep(val from: Int, val to: Int, val title: Int, val detail: Int, val tone: HealthBodyTone)
internal data class HealthBodyLesson(
    val title: Int, val summary: Int, val nodes: List<HealthBodyNode>, val steps: List<HealthBodyStep>,
    val source: Int, val url: String
) {
    init {
        require(nodes.size in 3..4 && steps.isNotEmpty() && steps.all { it.from in nodes.indices && it.to in nodes.indices && it.from != it.to })
        require(url.startsWith("https://"))
    }
}

internal data class HealthBodyTopicInfo(val layers: List<Int>, val lesson: HealthBodyLesson, val reference: Int)

internal object HealthBodyLessons {
    private fun node(label: Int, glyph: HealthBodyGlyph) = HealthBodyNode(label, glyph)
    private fun step(from: Int, to: Int, title: Int, detail: Int, tone: HealthBodyTone) = HealthBodyStep(from, to, title, detail, tone)

    private val circulation = HealthBodyTopicInfo(
        listOf(R.string.health_body_circ_organ, R.string.health_body_circ_tissue, R.string.health_body_circ_cell, R.string.health_body_circ_molecule),
        HealthBodyLesson(R.string.health_body_circ_title, R.string.health_body_circ_summary,
            listOf(node(R.string.health_body_right_heart, HealthBodyGlyph.HEART), node(R.string.health_body_lungs, HealthBodyGlyph.LUNG),
                node(R.string.health_body_left_heart, HealthBodyGlyph.HEART), node(R.string.health_body_body_tissues, HealthBodyGlyph.TISSUE)),
            listOf(step(0, 1, R.string.health_body_circ_s1, R.string.health_body_circ_d1, HealthBodyTone.RETURN),
                step(1, 2, R.string.health_body_circ_s2, R.string.health_body_circ_d2, HealthBodyTone.OXYGEN),
                step(2, 3, R.string.health_body_circ_s3, R.string.health_body_circ_d3, HealthBodyTone.OXYGEN),
                step(3, 0, R.string.health_body_circ_s4, R.string.health_body_circ_d4, HealthBodyTone.RETURN)),
            R.string.health_body_source_heart, "https://www.nhlbi.nih.gov/health/heart/blood-flow"),
        R.string.health_body_circ_reference
    )
    private val breathing = HealthBodyTopicInfo(
        listOf(R.string.health_body_breath_organ, R.string.health_body_breath_tissue, R.string.health_body_breath_cell, R.string.health_body_breath_molecule),
        HealthBodyLesson(R.string.health_body_breath_title, R.string.health_body_breath_summary,
            listOf(node(R.string.health_body_air, HealthBodyGlyph.AIR), node(R.string.health_body_alveoli, HealthBodyGlyph.LUNG),
                node(R.string.health_body_blood, HealthBodyGlyph.CELL), node(R.string.health_body_breath_out, HealthBodyGlyph.AIR)),
            listOf(step(0, 1, R.string.health_body_breath_s1, R.string.health_body_breath_d1, HealthBodyTone.FLOW),
                step(1, 2, R.string.health_body_breath_s2, R.string.health_body_breath_d2, HealthBodyTone.OXYGEN),
                step(2, 1, R.string.health_body_breath_s3, R.string.health_body_breath_d3, HealthBodyTone.RETURN),
                step(1, 3, R.string.health_body_breath_s4, R.string.health_body_breath_d4, HealthBodyTone.RETURN)),
            R.string.health_body_source_lung, "https://www.nhlbi.nih.gov/health/lungs/respiratory-system"),
        R.string.health_body_breath_reference
    )
    private val metabolism = HealthBodyTopicInfo(
        listOf(R.string.health_body_metabolic_organ, R.string.health_body_metabolic_tissue, R.string.health_body_metabolic_cell, R.string.health_body_metabolic_molecule),
        HealthBodyLesson(R.string.health_body_metabolic_title, R.string.health_body_metabolic_summary,
            listOf(node(R.string.health_body_nutrients, HealthBodyGlyph.FOOD), node(R.string.health_body_mitochondria, HealthBodyGlyph.CELL),
                node(R.string.health_body_atp, HealthBodyGlyph.MOLECULE), node(R.string.health_body_cell_work, HealthBodyGlyph.TISSUE)),
            listOf(step(0, 1, R.string.health_body_metabolic_s1, R.string.health_body_metabolic_d1, HealthBodyTone.FLOW),
                step(1, 2, R.string.health_body_metabolic_s2, R.string.health_body_metabolic_d2, HealthBodyTone.ENERGY),
                step(2, 3, R.string.health_body_metabolic_s3, R.string.health_body_metabolic_d3, HealthBodyTone.ENERGY)),
            R.string.health_body_source_metabolism, "https://openstax.org/books/anatomy-and-physiology/pages/24-1-overview-of-metabolic-reactions"),
        R.string.health_body_metabolic_reference
    )
    private val nerves = HealthBodyTopicInfo(
        listOf(R.string.health_body_nerve_organ, R.string.health_body_nerve_tissue, R.string.health_body_nerve_cell, R.string.health_body_nerve_molecule),
        HealthBodyLesson(R.string.health_body_nerve_title, R.string.health_body_nerve_summary,
            listOf(node(R.string.health_body_cell_body, HealthBodyGlyph.NEURON), node(R.string.health_body_axon, HealthBodyGlyph.NEURON),
                node(R.string.health_body_synapse, HealthBodyGlyph.MOLECULE), node(R.string.health_body_target_cell, HealthBodyGlyph.CELL)),
            listOf(step(0, 1, R.string.health_body_nerve_s1, R.string.health_body_nerve_d1, HealthBodyTone.SIGNAL),
                step(1, 2, R.string.health_body_nerve_s2, R.string.health_body_nerve_d2, HealthBodyTone.SIGNAL),
                step(2, 3, R.string.health_body_nerve_s3, R.string.health_body_nerve_d3, HealthBodyTone.ENERGY)),
            R.string.health_body_source_nerves, "https://openstax.org/books/anatomy-and-physiology/pages/12-5-communication-between-neurons"),
        R.string.health_body_nerve_reference
    )
    private val digestion = HealthBodyTopicInfo(
        listOf(R.string.health_body_digest_organ, R.string.health_body_digest_tissue, R.string.health_body_digest_cell, R.string.health_body_digest_molecule),
        HealthBodyLesson(R.string.health_body_digest_title, R.string.health_body_digest_summary,
            listOf(node(R.string.health_body_mouth, HealthBodyGlyph.FOOD), node(R.string.health_body_stomach, HealthBodyGlyph.FILTER),
                node(R.string.health_body_intestine, HealthBodyGlyph.FILTER), node(R.string.health_body_circulation, HealthBodyGlyph.TISSUE)),
            listOf(step(0, 1, R.string.health_body_digest_s1, R.string.health_body_digest_d1, HealthBodyTone.FLOW),
                step(1, 2, R.string.health_body_digest_s2, R.string.health_body_digest_d2, HealthBodyTone.ENERGY),
                step(2, 3, R.string.health_body_digest_s3, R.string.health_body_digest_d3, HealthBodyTone.OXYGEN)),
            R.string.health_body_source_digestion, "https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works"),
        R.string.health_body_digest_reference
    )
    private val kidneys = HealthBodyTopicInfo(
        listOf(R.string.health_body_kidney_organ, R.string.health_body_kidney_tissue, R.string.health_body_kidney_cell, R.string.health_body_kidney_molecule),
        HealthBodyLesson(R.string.health_body_kidney_title, R.string.health_body_kidney_summary,
            listOf(node(R.string.health_body_blood, HealthBodyGlyph.CELL), node(R.string.health_body_glomerulus, HealthBodyGlyph.FILTER),
                node(R.string.health_body_tubule, HealthBodyGlyph.TISSUE), node(R.string.health_body_urine, HealthBodyGlyph.FILTER)),
            listOf(step(0, 1, R.string.health_body_kidney_s1, R.string.health_body_kidney_d1, HealthBodyTone.FLOW),
                step(1, 2, R.string.health_body_kidney_s2, R.string.health_body_kidney_d2, HealthBodyTone.OXYGEN),
                step(2, 0, R.string.health_body_kidney_s3, R.string.health_body_kidney_d3, HealthBodyTone.OXYGEN),
                step(2, 3, R.string.health_body_kidney_s4, R.string.health_body_kidney_d4, HealthBodyTone.RETURN)),
            R.string.health_body_source_kidneys, "https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work"),
        R.string.health_body_kidney_reference
    )
    private val oxygen = HealthBodyLesson(R.string.health_body_oxygen_title, R.string.health_body_oxygen_summary,
        listOf(node(R.string.health_body_alveoli, HealthBodyGlyph.LUNG), node(R.string.health_body_hemoglobin, HealthBodyGlyph.MOLECULE),
            node(R.string.health_body_body_tissues, HealthBodyGlyph.TISSUE)),
        listOf(step(0, 1, R.string.health_body_oxygen_s1, R.string.health_body_oxygen_d1, HealthBodyTone.OXYGEN),
            step(1, 2, R.string.health_body_oxygen_s2, R.string.health_body_oxygen_d2, HealthBodyTone.OXYGEN)),
        R.string.health_body_source_oxygen, "https://openstax.org/books/anatomy-and-physiology/pages/22-5-transport-of-gases")

    fun info(topic: HealthBodyTopic) = when (topic) {
        HealthBodyTopic.CIRCULATION -> circulation
        HealthBodyTopic.BREATHING -> breathing
        HealthBodyTopic.METABOLISM -> metabolism
        HealthBodyTopic.NERVES -> nerves
        HealthBodyTopic.DIGESTION -> digestion
        HealthBodyTopic.KIDNEYS -> kidneys
    }

    fun lesson(topic: HealthBodyTopic, layer: HealthBodyLayer): HealthBodyLesson =
        if (layer == HealthBodyLayer.MOLECULE && (topic == HealthBodyTopic.CIRCULATION || topic == HealthBodyTopic.BREATHING)) oxygen
        else info(topic).lesson
}

internal data class HealthBodyFrame(val step: Int, val fraction: Float)
internal object HealthBodyTimeline {
    private const val STEP_MILLIS = 2350L

    fun frame(position: Float, steps: Int): HealthBodyFrame {
        require(steps > 0)
        val progress = position.takeIf(Float::isFinite)?.coerceIn(0f, steps.toFloat()) ?: 0f
        val index = progress.toInt().coerceAtMost(steps - 1)
        return HealthBodyFrame(index, progress - index)
    }

    fun duration(steps: Int, slow: Boolean): Long {
        require(steps > 0)
        return steps * STEP_MILLIS * if (slow) 2 else 1
    }

    fun jump(position: Float, steps: Int, delta: Int): Float =
        (frame(position, steps).step + delta).coerceIn(0, steps - 1).toFloat() + .25f
}

internal data class HealthBodyPumpExperiment(val beats: Int = 75, val strokeMl: Int = 60) {
    init { require(beats in BEATS && strokeMl in STROKE_ML) }
    val outputMlPerMinute get() = beats * strokeMl
    companion object {
        val BEATS = 40..140
        val STROKE_ML = 20..120
    }
}
