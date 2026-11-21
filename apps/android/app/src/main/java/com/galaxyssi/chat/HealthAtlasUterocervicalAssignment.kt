package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasUterocervicalAssignment {
    const val UTERUS = "uterus"
    const val CERVIX = "cervix"
    const val VAGINA = "vagina"
    const val UTERUS_WALL = 0
    const val CERVICAL_CANAL = 1
    const val VAGINAL_WALL = 2
    const val durationMs = 18_000L

    const val ANATOMY_SOURCE =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system"
    const val CERVIX_SOURCE = "https://training.seer.cancer.gov/cervical-uterine/anatomy/"
    const val WALL_SOURCE = "https://www.medcell.org/histology/female_reproductive_system_lab.php"

    val chapterIds = listOf(UTERUS, CERVIX, VAGINA)
    val owners = chapterIds.toSet()
    val title = string.health_atlas_uterocervical_title
    val scope = string.health_atlas_uterocervical_scope
    val choice = string.health_atlas_uterocervical_choice
    val chapters = listOf(
        string.health_atlas_uterocervical_uterus to string.health_atlas_uterocervical_uterus_caption,
        string.health_atlas_uterocervical_cervix to string.health_atlas_uterocervical_cervix_caption,
        string.health_atlas_uterocervical_vagina to string.health_atlas_uterocervical_vagina_caption,
    )
    val references = listOf(
        string.health_atlas_uterocervical_ref_anatomy to ANATOMY_SOURCE,
        string.health_atlas_uterocervical_ref_cervix to CERVIX_SOURCE,
        string.health_atlas_uterocervical_ref_wall to WALL_SOURCE,
    )

    fun entryChapter(id: String) = chapterIds.indexOf(id).coerceAtLeast(UTERUS_WALL)
}
