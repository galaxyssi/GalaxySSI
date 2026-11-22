package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

private const val SMALL_INTESTINE_HISTOLOGY = "https://histology.oit.duke.edu/NormalBody/GItract/GItract_answers.html"

internal object HealthAtlasPanethBarrierAssignment : HealthAtlasCellLesson {
    const val storyKey = "PANETH_CRYPT_BARRIER"
    const val owner = "cell-paneth-cell"
    const val AT_BASE = 0
    const val GRANULES = 1
    const val RELEASE = 2
    const val LOCAL_BARRIER = 3
    override val durationMs = 16_000L
    const val entryChapter = AT_BASE
    override val showStructurePreview = true
    const val artTag = "atlas-function-paneth-crypt-barrier-art"

    override val owners = setOf(owner)
    override val title = string.health_atlas_paneth_barrier_title
    override val scope = string.health_atlas_paneth_barrier_scope
    override val choice = string.health_atlas_paneth_barrier_choice
    val chapterIds = listOf("crypt-base", "apical-granules", "luminal-release", "local-barrier")
    override val chapters = listOf(
        string.health_atlas_paneth_barrier_base to string.health_atlas_paneth_barrier_base_caption,
        string.health_atlas_paneth_barrier_granules to string.health_atlas_paneth_barrier_granules_caption,
        string.health_atlas_paneth_barrier_release to string.health_atlas_paneth_barrier_release_caption,
        string.health_atlas_paneth_barrier_local to string.health_atlas_paneth_barrier_local_caption,
    )
    override val references = listOf(
        string.health_atlas_crypt_ref_histology to SMALL_INTESTINE_HISTOLOGY,
        string.health_atlas_paneth_barrier_ref_tissue to "https://pubmed.ncbi.nlm.nih.gov/16989824/",
    )
}

internal object HealthAtlasEnteroendocrineSignalAssignment : HealthAtlasCellLesson {
    const val storyKey = "ENTEROENDOCRINE_LUMEN_SIGNAL"
    const val owner = "cell-enteroendocrine-cell"
    const val SENSE = 0
    const val BASAL_VESICLES = 1
    const val TISSUE_RELEASE = 2
    const val BLOOD_SIGNAL = 3
    override val durationMs = 16_000L
    const val entryChapter = SENSE
    override val showStructurePreview = true
    const val artTag = "atlas-function-enteroendocrine-lumen-signal-art"

    override val owners = setOf(owner)
    override val title = string.health_atlas_enteroendocrine_signal_title
    override val scope = string.health_atlas_enteroendocrine_signal_scope
    override val choice = string.health_atlas_enteroendocrine_signal_choice
    val chapterIds = listOf("luminal-cue", "basal-vesicles", "tissue-release", "blood-signal")
    override val chapters = listOf(
        string.health_atlas_enteroendocrine_signal_sense to string.health_atlas_enteroendocrine_signal_sense_caption,
        string.health_atlas_enteroendocrine_signal_vesicles to string.health_atlas_enteroendocrine_signal_vesicles_caption,
        string.health_atlas_enteroendocrine_signal_release to string.health_atlas_enteroendocrine_signal_release_caption,
        string.health_atlas_enteroendocrine_signal_blood to string.health_atlas_enteroendocrine_signal_blood_caption,
    )
    override val references = listOf(
        string.health_atlas_enteroendocrine_signal_ref_open to
            "https://open.umich.edu/sites/default/files/downloads/01.07.09-hist-velkey-esophstom.pdf",
        string.health_atlas_enteroendocrine_signal_ref_capillary to
            "https://biomedizin.unibas.ch/fileadmin/user_upload/biomedizin/core_facilities/histology/Guides/HistologyLabManual.pdf",
    )
}

internal object HealthAtlasIntestinalStemRenewalAssignment : HealthAtlasCellLesson {
    const val storyKey = "INTESTINAL_STEM_RENEWAL"
    const val owner = "cell-intestinal-stem-cell"
    const val NICHE = 0
    const val DIVISION = 1
    const val UPWARD = 2
    const val VILLUS_LINING = 3
    override val durationMs = 16_000L
    const val entryChapter = NICHE
    override val showStructurePreview = true
    const val artTag = "atlas-function-intestinal-stem-renewal-art"

    override val owners = setOf(owner)
    override val title = string.health_atlas_intestinal_stem_renewal_title
    override val scope = string.health_atlas_intestinal_stem_renewal_scope
    override val choice = string.health_atlas_intestinal_stem_renewal_choice
    val chapterIds = listOf("base-niche", "renewal-division", "up-the-crypt", "villus-lining")
    override val chapters = listOf(
        string.health_atlas_intestinal_stem_renewal_niche to string.health_atlas_intestinal_stem_renewal_niche_caption,
        string.health_atlas_intestinal_stem_renewal_division to string.health_atlas_intestinal_stem_renewal_division_caption,
        string.health_atlas_intestinal_stem_renewal_upward to string.health_atlas_intestinal_stem_renewal_upward_caption,
        string.health_atlas_intestinal_stem_renewal_villus to string.health_atlas_intestinal_stem_renewal_villus_caption,
    )
    override val references = listOf(
        string.health_atlas_crypt_ref_histology to SMALL_INTESTINE_HISTOLOGY,
        string.health_atlas_intestinal_stem_renewal_ref_lineage to "https://pubmed.ncbi.nlm.nih.gov/19156773/",
        string.health_atlas_intestinal_stem_renewal_ref_migration to "https://www.medcell.org/tbl/histology_of_the_gi_tract/reading.php",
    )
}
