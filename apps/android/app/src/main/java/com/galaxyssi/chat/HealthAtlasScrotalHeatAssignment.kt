package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasScrotalHeatAssignment {
    const val OWNER = "scrotum"
    const val VIEW_KEY = "scrotal-heat-exchange-section"
    const val COMPARTMENTS = 0
    const val COVERINGS = 1
    const val EXCHANGE = 2
    const val durationMs = 15_000L

    private const val ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system"
    private const val HUMAN_VESSELS = "https://pubmed.ncbi.nlm.nih.gov/14507047/"
    private const val THERMAL_PHYSIOLOGY = "https://www.ncbi.nlm.nih.gov/books/NBK279031/"

    val owners = setOf(OWNER)
    val title = string.health_atlas_scrotal_heat_title
    val scope = string.health_atlas_scrotal_heat_scope
    val choice = string.health_atlas_scrotal_heat_choice
    val chapterIds = listOf("scrotal-compartments", "scrotal-coverings", "scrotal-countercurrent-exchange")
    val chapters = listOf(
        string.health_atlas_scrotal_heat_compartments to string.health_atlas_scrotal_heat_compartments_caption,
        string.health_atlas_scrotal_heat_coverings to string.health_atlas_scrotal_heat_coverings_caption,
        string.health_atlas_scrotal_heat_exchange to string.health_atlas_scrotal_heat_exchange_caption,
    )
    val references = listOf(
        string.health_atlas_scrotal_heat_ref_anatomy to ANATOMY,
        string.health_atlas_scrotal_heat_ref_vessels to HUMAN_VESSELS,
        string.health_atlas_scrotal_heat_ref_physiology to THERMAL_PHYSIOLOGY,
    )

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_scrotal_heat_plate,
        owner = OWNER,
        viewLabel = string.health_atlas_scrotal_heat_plate_caption,
        markers = listOf(anchor("testes", 79, 169)),
        source = ANATOMY,
        viewKey = VIEW_KEY,
        selectorLabel = string.health_atlas_scrotal_heat_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("scrotal-dartos", 29, 193),
                string.health_atlas_scrotal_heat_dartos, string.health_atlas_scrotal_heat_dartos_detail),
            HealthAtlasFeature(anchor("scrotal-tunica-vaginalis", 169, 173),
                string.health_atlas_scrotal_heat_tunica, string.health_atlas_scrotal_heat_tunica_detail),
            HealthAtlasFeature(anchor("scrotal-spermatic-cord", 229, 93),
                string.health_atlas_scrotal_heat_cord, string.health_atlas_scrotal_heat_cord_detail),
            HealthAtlasFeature(anchor("scrotal-pampiniform-plexus", 302, 146),
                string.health_atlas_scrotal_heat_plexus, string.health_atlas_scrotal_heat_plexus_detail),
        ),
        splitCallouts = true,
    )

    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
}
