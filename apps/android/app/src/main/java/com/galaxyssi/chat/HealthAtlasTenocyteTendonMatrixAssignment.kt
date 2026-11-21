package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasTenocyteTendonMatrixAssignment {
    const val ID = "cell-tenocyte"
    const val ALIGNMENT = 0
    const val MATRIX_PULL = 1
    const val STRAIN_TRANSFER = 2
    const val RECOVERY = 3
    const val MORPHOLOGY_SOURCE = "https://doi.org/10.1111/joa.12164"

    val owners = setOf(ID)
    val title = string.health_atlas_tenocyte_tendon_matrix_title
    val scope = string.health_atlas_tenocyte_tendon_matrix_scope
    val choice = string.health_atlas_tenocyte_tendon_matrix_choice
    val chapterIds = listOf("fiber-alignment", "matrix-pull", "strain-transfer", "mechanical-recovery")
    val chapters = listOf(
        string.health_atlas_tenocyte_tendon_matrix_alignment to string.health_atlas_tenocyte_tendon_matrix_alignment_caption,
        string.health_atlas_tenocyte_tendon_matrix_pull to string.health_atlas_tenocyte_tendon_matrix_pull_caption,
        string.health_atlas_tenocyte_tendon_matrix_transfer to string.health_atlas_tenocyte_tendon_matrix_transfer_caption,
        string.health_atlas_tenocyte_tendon_matrix_recovery to string.health_atlas_tenocyte_tendon_matrix_recovery_caption,
    )
    val references = listOf(
        string.health_atlas_tenocyte_tendon_matrix_ref_morphology to MORPHOLOGY_SOURCE,
        string.health_atlas_tenocyte_tendon_matrix_ref_transfer to "https://pubmed.ncbi.nlm.nih.gov/23237459/",
        string.health_atlas_tenocyte_tendon_matrix_ref_recovery to "https://pubmed.ncbi.nlm.nih.gov/36435426/",
    )
    const val durationMs = 16_000L
    const val entryChapter = ALIGNMENT
}
