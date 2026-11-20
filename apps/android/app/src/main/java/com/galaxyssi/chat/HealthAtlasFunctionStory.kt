package com.galaxyssi.chat

import android.content.Context

/** Visual chapters are independent of the catalogue's quantitative simulations. */
internal enum class HealthAtlasFunctionStory(
    private val owners: Set<String>,
    val title: Int,
    val scope: Int,
    val chapters: List<Pair<Int, Int>>,
    val references: List<Pair<Int, String>>,
    val durationMs: Long,
) {
    GLUCOSE(
        setOf("tissue-skeletal-muscle", "cell-adipocyte"),
        R.string.health_atlas_uptake_title,
        R.string.health_atlas_uptake_scope,
        listOf(
            R.string.health_atlas_uptake_bind to R.string.health_atlas_uptake_bind_caption,
            R.string.health_atlas_uptake_irs to R.string.health_atlas_uptake_irs_caption,
            R.string.health_atlas_uptake_akt to R.string.health_atlas_uptake_akt_caption,
            R.string.health_atlas_uptake_fuse to R.string.health_atlas_uptake_fuse_caption,
            R.string.health_atlas_uptake_transport to R.string.health_atlas_uptake_transport_caption,
        ),
        listOf(
            R.string.health_atlas_uptake_reference to "https://pubmed.ncbi.nlm.nih.gov/19188436/",
            R.string.health_atlas_uptake_pathway_reference to "https://pmc.ncbi.nlm.nih.gov/articles/PMC507006/",
        ),
        15_000L,
    ),
    HEARTBEAT(
        setOf("heart", "cardio", "atria", "ventricles", "heart-valves", "left-atrium", "right-atrium",
            "left-ventricle", "right-ventricle", "tricuspid-valve", "mitral-valve", "pulmonary-valve", "aortic-valve"),
        R.string.health_atlas_beat_title,
        R.string.health_atlas_beat_scope,
        HealthAtlasBeatStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_beat_cycle_reference to HealthAtlasHeartSection.CYCLE_SOURCE,
            R.string.health_atlas_beat_flow_reference to "https://www.nhlbi.nih.gov/health/heart/blood-flow",
        ),
        17_500L,
    ),
    BREATHING(
        setOf("respiratory", "trachea", "bronchi", "bronchioles", "lungs", "diaphragm",
            "alveoli", "respiratory-membrane", "pulmonary-capillaries"),
        R.string.health_atlas_breathe_title,
        R.string.health_atlas_breathe_scope,
        HealthAtlasBreathingStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_breathe_air_source to "https://www.nhlbi.nih.gov/health/lungs/breathing-benefits",
            R.string.health_atlas_breathe_gas_source to HealthAtlasGasExchange.SOURCE,
        ),
        18_000L,
    ),
    HEARING(
        setOf("ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "cell-inner-ear-hair-cell"),
        R.string.health_atlas_hear_title,
        R.string.health_atlas_hear_scope,
        HealthAtlasSoundStage.entries.map { it.title to it.caption },
        listOf(
            R.string.health_atlas_hear_path_source to "https://www.nidcd.nih.gov/health/how-do-we-hear",
            R.string.health_atlas_hear_cells_source to "https://pmc.ncbi.nlm.nih.gov/articles/PMC1413628/",
        ),
        19_000L,
    );

    fun chapter(value: Float) = (safePhase(value) * chapters.size).toInt().coerceAtMost(chapters.lastIndex)
    fun fraction(value: Float) = (safePhase(value) * chapters.size - chapter(value)).coerceIn(0f, 1f)
    fun startOf(chapter: Int) = chapter.coerceIn(chapters.indices) / chapters.size.toFloat()
    fun createArt(context: Context): HealthAtlasFunctionArt = when (this) {
        GLUCOSE -> HealthAtlasUptakeView(context)
        HEARTBEAT -> HealthAtlasHeartbeatView(context)
        BREATHING -> HealthAtlasBreathingView(context)
        HEARING -> HealthAtlasHearingStoryView(context)
    }

    companion object {
        fun forId(id: String?) = if (id == null) null else entries.firstOrNull { id in it.owners }
        fun safePhase(value: Float) = if (value.isFinite()) value.coerceIn(0f, 1f) else 0f
    }
}
