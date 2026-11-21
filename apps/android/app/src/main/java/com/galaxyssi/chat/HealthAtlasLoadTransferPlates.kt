package com.galaxyssi.chat

internal object HealthAtlasLoadTransferPlates {
    const val pelvicSource =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-3-the-pelvic-girdle-and-pelvis"
    const val subcutaneousSource =
        "https://openstax.org/books/anatomy-and-physiology-2e/pages/5-1-layers-of-the-skin"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)

    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_pelvic_ring,
            owner = "pelvis",
            viewLabel = R.string.health_atlas_pelvic_ring_view,
            markers = listOf(marker("vertebrae", 180, 31), marker("femur", 61, 236)),
            source = pelvicSource,
            viewKey = "pelvic-ring-and-hips",
            selectorLabel = R.string.health_atlas_pelvic_ring_view,
            features = listOf(
                feature("pelvic-ring-sacrum", 180, 87, R.string.health_atlas_pelvic_ring_sacrum,
                    R.string.health_atlas_pelvic_ring_sacrum_detail),
                feature("pelvic-ring-sacroiliac", 148, 75, R.string.health_atlas_pelvic_ring_joint,
                    R.string.health_atlas_pelvic_ring_joint_detail),
                feature("pelvic-ring-acetabulum", 273, 140, R.string.health_atlas_pelvic_ring_socket,
                    R.string.health_atlas_pelvic_ring_socket_detail),
                feature("pelvic-ring-symphysis", 180, 187, R.string.health_atlas_pelvic_ring_symphysis,
                    R.string.health_atlas_pelvic_ring_symphysis_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_subcutaneous_section,
            owner = "subcutaneous-tissue",
            viewLabel = R.string.health_atlas_subcutaneous_view,
            markers = listOf(marker("epidermis", 69, 58), marker("dermis", 278, 90),
                marker("cell-adipocyte", 251, 157)),
            source = subcutaneousSource,
            viewKey = "subcutaneous-lobular-section",
            selectorLabel = R.string.health_atlas_subcutaneous_view,
            features = listOf(
                feature("subcutaneous-lobule", 161, 154, R.string.health_atlas_subcutaneous_lobule,
                    R.string.health_atlas_subcutaneous_lobule_detail),
                feature("subcutaneous-septum", 89, 173, R.string.health_atlas_subcutaneous_septa,
                    R.string.health_atlas_subcutaneous_septa_detail),
                feature("subcutaneous-deep-fascia", 269, 226, R.string.health_atlas_subcutaneous_fascia,
                    R.string.health_atlas_subcutaneous_fascia_detail),
            ),
            splitCallouts = true,
        ),
    )
}
