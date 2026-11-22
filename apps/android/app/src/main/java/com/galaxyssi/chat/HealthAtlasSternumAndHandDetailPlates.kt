package com.galaxyssi.chat

internal object HealthAtlasSternumAndHandDetailPlates {
    private const val THORAX = "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-4-the-thoracic-cage"
    private const val HAND = "https://openstax.org/books/anatomy-and-physiology-2e/pages/8-2-bones-of-the-upper-limb"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_sternum_anterior_landmarks,
            owner = "sternum",
            viewLabel = R.string.health_atlas_sternum_front_detail,
            markers = listOf(marker("clavicle", 102, 36)),
            source = THORAX,
            viewKey = "sternum-anterior-landmarks",
            selectorLabel = R.string.health_atlas_sternum_front_detail,
            features = listOf(
                feature("sternum-notch", 182, 55, R.string.health_atlas_sternum_notch,
                    R.string.health_atlas_sternum_notch_detail),
                feature("sternum-manubrium", 162, 77, R.string.health_atlas_sternum_manubrium,
                    R.string.health_atlas_sternum_manubrium_detail),
                feature("sternum-angle", 205, 103, R.string.health_atlas_sternum_angle,
                    R.string.health_atlas_sternum_angle_detail),
                feature("sternum-body", 169, 166, R.string.health_atlas_sternum_body,
                    R.string.health_atlas_sternum_body_detail),
                feature("sternum-xiphoid", 183, 243, R.string.health_atlas_sternum_xiphoid,
                    R.string.health_atlas_sternum_xiphoid_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_hand_skeleton_palmar,
            owner = "hand-bones",
            viewLabel = R.string.health_atlas_hand_palmar_detail,
            markers = listOf(marker("radius", 162, 246), marker("ulna", 225, 247)),
            source = HAND,
            viewKey = "hand-skeleton-palmar",
            selectorLabel = R.string.health_atlas_hand_palmar_detail,
            features = listOf(
                feature("hand-bones-phalanges", 224, 72, R.string.health_atlas_hand_phalanges,
                    R.string.health_atlas_hand_phalanges_detail),
                feature("hand-bones-thumb", 76, 142, R.string.health_atlas_hand_thumb,
                    R.string.health_atlas_hand_thumb_detail),
                feature("hand-bones-metacarpals", 200, 177, R.string.health_atlas_hand_metacarpals,
                    R.string.health_atlas_hand_metacarpals_detail),
                feature("hand-bones-carpals", 172, 219, R.string.health_atlas_hand_carpals,
                    R.string.health_atlas_hand_carpals_detail),
                feature("hand-bones-pisiform", 217, 220, R.string.health_atlas_hand_pisiform,
                    R.string.health_atlas_hand_pisiform_detail),
            ),
            splitCallouts = true,
        ),
    )
}
