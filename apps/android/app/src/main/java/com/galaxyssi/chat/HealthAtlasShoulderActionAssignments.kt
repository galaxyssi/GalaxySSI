package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasPectoralActionAssignment {
    const val OWNER_ID = "pectoralis-major"
    const val ORIGINS = 0
    const val INSERTION = 1
    const val SWEEP = 2
    const val ACROSS = 3
    const val RETURN = 4
    const val ENTRY_CHAPTER = ORIGINS
    const val durationMs = 18_000L
    const val ANATOMY = "https://rad.washington.edu/muscle-atlas/pectoralis-major/"

    val owners = setOf(OWNER_ID)
    val title = string.health_atlas_pectoral_action_title
    val scope = string.health_atlas_pectoral_action_scope
    val chapters = listOf(
        string.health_atlas_pectoral_action_origins to string.health_atlas_pectoral_action_origins_caption,
        string.health_atlas_pectoral_action_insertion to string.health_atlas_pectoral_action_insertion_caption,
        string.health_atlas_pectoral_action_sweep to string.health_atlas_pectoral_action_sweep_caption,
        string.health_atlas_pectoral_action_across to string.health_atlas_pectoral_action_across_caption,
        string.health_atlas_pectoral_action_return to string.health_atlas_pectoral_action_return_caption,
    )
    val references = listOf(
        string.health_atlas_pectoral_action_ref_anatomy to ANATOMY,
        string.health_atlas_pectoral_action_ref_sweep to "https://pubmed.ncbi.nlm.nih.gov/9356931/",
    )
}

internal object HealthAtlasLatissimusActionAssignment {
    const val OWNER_ID = "latissimus-dorsi"
    const val ORIGINS = 0
    const val INSERTION = 1
    const val EXTEND = 2
    const val ADDUCT = 3
    const val RETURN = 4
    const val ENTRY_CHAPTER = ORIGINS
    const val durationMs = 18_000L
    const val ANATOMY = "https://rad.washington.edu/muscle-atlas/latissimus-dorsi/"

    val owners = setOf(OWNER_ID)
    val title = string.health_atlas_latissimus_action_title
    val scope = string.health_atlas_latissimus_action_scope
    val chapters = listOf(
        string.health_atlas_latissimus_action_origins to string.health_atlas_latissimus_action_origins_caption,
        string.health_atlas_latissimus_action_insertion to string.health_atlas_latissimus_action_insertion_caption,
        string.health_atlas_latissimus_action_extend to string.health_atlas_latissimus_action_extend_caption,
        string.health_atlas_latissimus_action_adduct to string.health_atlas_latissimus_action_adduct_caption,
        string.health_atlas_latissimus_action_return to string.health_atlas_latissimus_action_return_caption,
    )
    val references = listOf(
        string.health_atlas_latissimus_action_ref_anatomy to ANATOMY,
        string.health_atlas_latissimus_action_ref_route to "https://www.ncbi.nlm.nih.gov/books/NBK448120/",
        string.health_atlas_latissimus_action_ref_moment to "https://pubmed.ncbi.nlm.nih.gov/18691376/",
    )
}
