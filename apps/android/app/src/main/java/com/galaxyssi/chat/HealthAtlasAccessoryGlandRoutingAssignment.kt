package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasAccessoryGlandRoutingAssignment {
    const val storyKey = "ACCESSORY_GLAND_ROUTING"
    const val LOCATOR = 0
    const val SEMINAL_VESICLES = 1
    const val EJACULATORY_DUCTS = 2
    const val PROSTATE = 3
    const val BULBOURETHRAL_GLANDS = 4

    const val BULBOURETHRAL_GLANDS_ID = "bulbourethral-glands"
    private val entries = mapOf(
        "seminal-vesicles" to SEMINAL_VESICLES,
        "ejaculatory-ducts" to EJACULATORY_DUCTS,
        "prostate" to PROSTATE,
        BULBOURETHRAL_GLANDS_ID to BULBOURETHRAL_GLANDS,
    )
    val owners: Set<String> = entries.keys
    val chapterIds = listOf("locator") + owners
    val title = string.health_atlas_accessory_gland_routing_title
    val scope = string.health_atlas_accessory_gland_routing_scope
    val choice = string.health_atlas_accessory_gland_routing_choice
    val chapters = listOf(
        string.health_atlas_accessory_gland_routing_locator to string.health_atlas_accessory_gland_routing_locator_caption,
        string.health_atlas_accessory_gland_routing_vesicles to string.health_atlas_accessory_gland_routing_vesicles_caption,
        string.health_atlas_accessory_gland_routing_ejaculatory to string.health_atlas_accessory_gland_routing_ejaculatory_caption,
        string.health_atlas_accessory_gland_routing_prostate to string.health_atlas_accessory_gland_routing_prostate_caption,
        string.health_atlas_accessory_gland_routing_bulbourethral to string.health_atlas_accessory_gland_routing_bulbourethral_caption,
    )
    val references = listOf(
        string.health_atlas_accessory_gland_routing_ref_ducts to "https://training.seer.cancer.gov/anatomy/reproductive/male/duct.html",
        string.health_atlas_accessory_gland_routing_ref_anatomy to "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system",
        string.health_atlas_accessory_gland_routing_ref_bulb to HealthAtlasBulbourethralGlandsPlate.SOURCE,
    )
    const val durationMs = 20_000L
    const val showStructurePreview = true

    fun entryChapter(id: String) = entries[id] ?: LOCATOR

    fun relatedLessons() = listOf("vas-deferens" to HealthAtlasFunctionStory.SPERM_TRANSPORT)
}

internal object HealthAtlasBulbourethralGlandsPlate {
    const val SOURCE = "https://pmc.ncbi.nlm.nih.gov/articles/PMC8373982/"
    const val VIEW_KEY = "bulbourethral-glands-section"

    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_bulbourethral_glands_plate,
        owner = HealthAtlasAccessoryGlandRoutingAssignment.BULBOURETHRAL_GLANDS_ID,
        viewLabel = string.health_atlas_bulbourethral_glands_plate_caption,
        markers = emptyList(),
        source = SOURCE,
        viewKey = VIEW_KEY,
        selectorLabel = string.health_atlas_bulbourethral_glands_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("bulbourethral-plate-prostate", 143, 71),
                string.health_atlas_accessory_gland_routing_prostate,
                string.health_atlas_bulbourethral_glands_plate_prostate_detail),
            HealthAtlasFeature(anchor("bulbourethral-plate-membranous-urethra", 185, 134),
                string.health_atlas_accessory_gland_routing_label_membranous,
                string.health_atlas_bulbourethral_glands_plate_membranous_detail),
            HealthAtlasFeature(anchor("bulbourethral-plate-gland", 141, 126),
                string.health_atlas_accessory_gland_routing_bulbourethral,
                string.health_atlas_bulbourethral_glands_plate_gland_detail),
            HealthAtlasFeature(anchor("bulbourethral-plate-duct", 193, 208),
                string.health_atlas_accessory_gland_routing_label_long_duct,
                string.health_atlas_bulbourethral_glands_plate_duct_detail),
            HealthAtlasFeature(anchor("bulbourethral-plate-proximal-spongy-urethra", 248, 196),
                string.health_atlas_bulbourethral_glands_plate_destination,
                string.health_atlas_bulbourethral_glands_plate_destination_detail),
        ),
        splitCallouts = true,
    )
}
