package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasLeydigEndocrineAssignment : HealthAtlasCellLesson {
    const val ID = "cell-leydig-cell"
    const val INTERSTITIUM = 0
    const val PITUITARY_SIGNAL = 1
    const val TESTOSTERONE = 2
    const val ENDOCRINE_OUTPUT = 3
    const val entryChapter = INTERSTITIUM
    override val durationMs = 20_000L
    override val showStructurePreview = true

    override val owners = setOf(ID)
    override val title = string.health_atlas_leydig_endocrine_title
    override val scope = string.health_atlas_leydig_endocrine_scope
    override val choice = string.health_atlas_leydig_endocrine_choice
    val chapterIds = listOf("interstitial-location", "pituitary-lh", "testosterone-production", "endocrine-output")
    override val chapters = listOf(
        string.health_atlas_leydig_endocrine_location to string.health_atlas_leydig_endocrine_location_caption,
        string.health_atlas_leydig_endocrine_signal to string.health_atlas_leydig_endocrine_signal_caption,
        string.health_atlas_leydig_endocrine_production to string.health_atlas_leydig_endocrine_production_caption,
        string.health_atlas_leydig_endocrine_output to string.health_atlas_leydig_endocrine_output_caption,
    )
    override val references = listOf(
        string.health_atlas_leydig_endocrine_ref_anatomy to
            "https://tales.nmc.unibas.ch/en/histology-12/fortpflanzungsorgane-mannlich-anatomische-mikroskopie-47/testes-adult-1-287",
        string.health_atlas_leydig_endocrine_ref_physiology to "https://www.ncbi.nlm.nih.gov/books/NBK279031/?report=classic",
    )
}

internal object HealthAtlasThecaCooperationAssignment : HealthAtlasCellLesson {
    const val ID = "cell-theca-cell"
    const val VASCULAR_LAYER = 0
    const val ANDROGEN_SOURCE = 1
    const val FOLLICULAR_HANDOFF = 2
    const val GRANULOSA_CONVERSION = 3
    const val entryChapter = VASCULAR_LAYER
    override val durationMs = 20_000L
    override val showStructurePreview = true

    override val owners = setOf(ID)
    override val title = string.health_atlas_theca_cooperation_title
    override val scope = string.health_atlas_theca_cooperation_scope
    override val choice = string.health_atlas_theca_cooperation_choice
    val chapterIds = listOf("vascular-theca-interna", "androgen-source", "follicular-handoff", "granulosa-conversion")
    override val chapters = listOf(
        string.health_atlas_theca_cooperation_layer to string.health_atlas_theca_cooperation_layer_caption,
        string.health_atlas_theca_cooperation_source to string.health_atlas_theca_cooperation_source_caption,
        string.health_atlas_theca_cooperation_handoff to string.health_atlas_theca_cooperation_handoff_caption,
        string.health_atlas_theca_cooperation_conversion to string.health_atlas_theca_cooperation_conversion_caption,
    )
    override val references = listOf(
        string.health_atlas_theca_cooperation_ref_nomenclature to
            "https://www.nichd.nih.gov/research/atNICHD/Investigators/gomez-lobo/research/nomenclature-workshop-2021",
        string.health_atlas_theca_cooperation_ref_anatomy to "https://www.ncbi.nlm.nih.gov/books/NBK278951/?report=printable",
        string.health_atlas_theca_cooperation_ref_physiology to "https://www.ncbi.nlm.nih.gov/books/NBK279054/?report=reader",
    )
}
