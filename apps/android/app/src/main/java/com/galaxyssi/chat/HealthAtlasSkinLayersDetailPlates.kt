package com.galaxyssi.chat

internal object HealthAtlasSkinLayersDetailPlates {
    private const val SKIN = "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin"
    private const val HISTOLOGY = "https://histology.leeds.ac.uk/home/skin/epidermis_layers/"
    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker("skin-layers-$id", x, y), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_skin_cross_section,
            owner = "skin-organ",
            viewLabel = R.string.health_atlas_skin_cross_section,
            markers = listOf(marker("epidermis", 301, 74), marker("dermis", 66, 132),
                marker("subcutaneous-tissue", 117, 223)),
            source = SKIN,
            viewKey = "skin-cross-section",
            selectorLabel = R.string.health_atlas_skin_cross_section,
            features = listOf(
                feature("follicle", 132, 147, R.string.health_atlas_skin_layers_follicle,
                    R.string.health_atlas_skin_layers_follicle_detail),
                feature("sweat-duct", 241, 110, R.string.health_atlas_skin_layers_sweat_duct,
                    R.string.health_atlas_skin_layers_sweat_duct_detail),
                feature("vessels", 270, 180, R.string.health_atlas_skin_layers_vessels,
                    R.string.health_atlas_skin_layers_vessels_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_epidermis_thick_layers,
            owner = "epidermis",
            viewLabel = R.string.health_atlas_epidermis_thick_layers,
            markers = emptyList(),
            source = HISTOLOGY,
            viewKey = "epidermis-thick-layers",
            selectorLabel = R.string.health_atlas_epidermis_thick_layers,
            features = listOf(
                feature("corneum", 90, 76, R.string.health_atlas_skin_layers_corneum,
                    R.string.health_atlas_skin_layers_corneum_detail),
                feature("lucidum", 249, 121, R.string.health_atlas_skin_layers_lucidum,
                    R.string.health_atlas_skin_layers_lucidum_detail),
                feature("granulosum", 94, 140, R.string.health_atlas_skin_layers_granulosum,
                    R.string.health_atlas_skin_layers_granulosum_detail),
                feature("spinosum", 273, 174, R.string.health_atlas_skin_layers_spinosum,
                    R.string.health_atlas_skin_layers_spinosum_detail),
                feature("basale", 104, 225, R.string.health_atlas_skin_layers_basale,
                    R.string.health_atlas_skin_layers_basale_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_dermis_papillary_reticular,
            owner = "dermis",
            viewLabel = R.string.health_atlas_dermis_two_layers,
            markers = listOf(marker("epidermis", 110, 57)),
            source = SKIN,
            viewKey = "dermis-papillary-reticular",
            selectorLabel = R.string.health_atlas_dermis_two_layers,
            features = listOf(
                feature("papillary", 252, 104, R.string.health_atlas_skin_layers_papillary,
                    R.string.health_atlas_skin_layers_papillary_detail),
                feature("capillary-loop", 91, 80, R.string.health_atlas_skin_layers_capillary_loop,
                    R.string.health_atlas_skin_layers_capillary_loop_detail),
                feature("reticular", 106, 182, R.string.health_atlas_skin_layers_reticular,
                    R.string.health_atlas_skin_layers_reticular_detail),
                feature("sensory-fiber", 209, 184, R.string.health_atlas_skin_layers_sensory_fiber,
                    R.string.health_atlas_skin_layers_sensory_fiber_detail),
            ),
            splitCallouts = true,
        ),
    )
}
