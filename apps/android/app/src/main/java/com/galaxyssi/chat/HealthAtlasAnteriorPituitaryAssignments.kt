package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

/** Functional lessons only. The structural plates stay in HealthAtlasEndocrinePlates. */
internal object HealthAtlasAnteriorPituitaryAssignments {
    private const val ANATOMY = "https://www.ncbi.nlm.nih.gov/books/NBK425703/"
    private const val PORTAL = "https://www.ncbi.nlm.nih.gov/books/NBK279126/"

    data class Lesson(
        val owner: String,
        override val title: Int,
        override val scope: Int,
        override val choice: Int,
        override val chapters: List<Pair<Int, Int>>,
        override val references: List<Pair<Int, String>>,
    ) : HealthAtlasCellLesson {
        override val owners = setOf(owner)
        override val durationMs = 16_000L
        override val showStructurePreview = true
    }

    val somatotroph = Lesson(
        "cell-somatotroph",
        string.health_atlas_antsoma_title,
        string.health_atlas_antsoma_scope,
        string.health_atlas_antsoma_choice,
        listOf(
            string.health_atlas_antsoma_pulse to string.health_atlas_antsoma_pulse_caption,
            string.health_atlas_antsoma_branch to string.health_atlas_antsoma_branch_caption,
            string.health_atlas_antsoma_relay to string.health_atlas_antsoma_relay_caption,
            string.health_atlas_antsoma_tissue to string.health_atlas_antsoma_tissue_caption,
        ),
        listOf(
            string.health_atlas_antpit_ref_anatomy to ANATOMY,
            string.health_atlas_antsoma_ref_adult to "https://www.ncbi.nlm.nih.gov/books/NBK279056/",
            string.health_atlas_antsoma_ref_liver to "https://pubmed.ncbi.nlm.nih.gov/10022415/",
            string.health_atlas_antsoma_ref_muscle to "https://pubmed.ncbi.nlm.nih.gov/2003602/",
        ),
    )

    val lactotroph = Lesson(
        "cell-lactotroph",
        string.health_atlas_antlacto_title,
        string.health_atlas_antlacto_scope,
        string.health_atlas_antlacto_choice,
        listOf(
            string.health_atlas_antlacto_brake to string.health_atlas_antlacto_brake_caption,
            string.health_atlas_antlacto_blood to string.health_atlas_antlacto_blood_caption,
            string.health_atlas_antlacto_face to string.health_atlas_antlacto_face_caption,
            string.health_atlas_antlacto_lumen to string.health_atlas_antlacto_lumen_caption,
        ),
        listOf(
            string.health_atlas_antpit_ref_anatomy to ANATOMY,
            string.health_atlas_antpit_ref_portal to PORTAL,
            string.health_atlas_antlacto_ref_lactation to "https://www.ncbi.nlm.nih.gov/books/NBK148970/",
            string.health_atlas_antlacto_ref_breast to "https://pubmed.ncbi.nlm.nih.gov/15960763/",
        ),
    )

    val corticotroph = Lesson(
        "cell-corticotroph",
        string.health_atlas_antcort_title,
        string.health_atlas_antcort_scope,
        string.health_atlas_antcort_choice,
        listOf(
            string.health_atlas_antcort_portal to string.health_atlas_antcort_portal_caption,
            string.health_atlas_antcort_blood to string.health_atlas_antcort_blood_caption,
            string.health_atlas_antcort_layer to string.health_atlas_antcort_layer_caption,
            string.health_atlas_antcort_cortisol to string.health_atlas_antcort_cortisol_caption,
        ),
        listOf(
            string.health_atlas_antpit_ref_portal to PORTAL,
            string.health_atlas_antcort_ref_cortex to "https://www.ncbi.nlm.nih.gov/books/NBK278945/",
            string.health_atlas_antcort_ref_acth to "https://www.ncbi.nlm.nih.gov/books/NBK279118/",
        ),
    )

    val gonadotroph = Lesson(
        "cell-gonadotroph",
        string.health_atlas_antgonad_title,
        string.health_atlas_antgonad_scope,
        string.health_atlas_antgonad_choice,
        listOf(
            string.health_atlas_antgonad_input to string.health_atlas_antgonad_input_caption,
            string.health_atlas_antgonad_pair to string.health_atlas_antgonad_pair_caption,
            string.health_atlas_antgonad_ovary to string.health_atlas_antgonad_ovary_caption,
            string.health_atlas_antgonad_testis to string.health_atlas_antgonad_testis_caption,
        ),
        listOf(
            string.health_atlas_antpit_ref_portal to PORTAL,
            string.health_atlas_antgonad_ref_ovary to "https://www.ncbi.nlm.nih.gov/books/NBK279054/",
            string.health_atlas_antgonad_ref_testis to "https://www.ncbi.nlm.nih.gov/books/NBK279031/",
        ),
    )
}
