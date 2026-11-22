package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasPenileUrinaryAssignment {
    const val OWNER = "penis"
    const val VIEW_KEY = "penile-urinary-section"
    const val CROSS_SECTION = 0
    const val PROXIMAL_ROUTE = 1
    const val SPONGY_ROUTE = 2
    const val durationMs = 15_000L

    private const val ANATOMY =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/27-1-anatomy-and-physiology-of-the-testicular-reproductive-system"
    private const val URINE_TRANSPORT =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/25-2-gross-anatomy-of-urine-transport"

    val owners = setOf(OWNER)
    val title = string.health_atlas_penile_urinary_title
    val scope = string.health_atlas_penile_urinary_scope
    val choice = string.health_atlas_penile_urinary_choice
    val chapterIds = listOf("penile-cross-section", "penile-proximal-route", "penile-spongy-route")
    val chapters = listOf(
        string.health_atlas_penile_urinary_section to string.health_atlas_penile_urinary_section_caption,
        string.health_atlas_penile_urinary_proximal to string.health_atlas_penile_urinary_proximal_caption,
        string.health_atlas_penile_urinary_distal to string.health_atlas_penile_urinary_distal_caption,
    )
    val references = listOf(
        string.health_atlas_penile_urinary_ref_anatomy to ANATOMY,
        string.health_atlas_penile_urinary_ref_route to URINE_TRANSPORT,
    )

    val plate = HealthAtlasPlate(
        drawable = R.drawable.health_atlas_penile_urinary_plate,
        owner = OWNER,
        viewLabel = string.health_atlas_penile_urinary_plate_caption,
        markers = listOf(anchor("bladder", 67, 161)),
        source = ANATOMY,
        viewKey = VIEW_KEY,
        selectorLabel = string.health_atlas_penile_urinary_plate_title,
        features = listOf(
            HealthAtlasFeature(anchor("penile-corpora-cavernosa", 213, 65),
                string.health_atlas_penile_urinary_cavernosa, string.health_atlas_penile_urinary_cavernosa_detail),
            HealthAtlasFeature(anchor("penile-corpus-spongiosum", 163, 112),
                string.health_atlas_penile_urinary_spongiosum, string.health_atlas_penile_urinary_spongiosum_detail),
            HealthAtlasFeature(anchor("penile-spongy-urethra", 181, 114),
                string.health_atlas_penile_urinary_spongy, string.health_atlas_penile_urinary_spongy_detail),
            HealthAtlasFeature(anchor("penile-external-meatus", 325, 228),
                string.health_atlas_penile_urinary_meatus, string.health_atlas_penile_urinary_meatus_detail),
        ),
        splitCallouts = true,
    )

    private fun anchor(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
}
