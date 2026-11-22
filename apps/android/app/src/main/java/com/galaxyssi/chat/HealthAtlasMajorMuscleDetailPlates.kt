package com.galaxyssi.chat

import com.galaxyssi.chat.R.string

internal object HealthAtlasMajorMuscleDetailPlates {
    private const val ANATOMY = "https://anatomy.ttuhscep.edu/musculoskeletal_system/"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, detail: Int) =
        HealthAtlasFeature(marker(id, x, y), title, detail)

    val all = listOf(
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_biceps_brachii_anterior,
            owner = "biceps-brachii",
            viewLabel = string.health_atlas_biceps_brachii_anterior_caption,
            markers = listOf(marker("scapula", 220, 46), marker("radius", 144, 255)),
            source = ANATOMY + "axilla_tables.html",
            viewKey = "biceps-brachii-anterior",
            selectorLabel = string.health_atlas_biceps_brachii_anterior_selector,
            features = listOf(
                feature("biceps-brachii-long-head", 153, 115, string.health_atlas_biceps_brachii_long_head,
                    string.health_atlas_biceps_brachii_long_head_detail),
                feature("biceps-brachii-short-head", 192, 94, string.health_atlas_biceps_brachii_short_head,
                    string.health_atlas_biceps_brachii_short_head_detail),
                feature("biceps-brachii-distal-tendon", 175, 213, string.health_atlas_biceps_brachii_distal_tendon,
                    string.health_atlas_biceps_brachii_distal_tendon_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_triceps_brachii_posterior,
            owner = "triceps-brachii",
            viewLabel = string.health_atlas_triceps_brachii_posterior_caption,
            markers = listOf(marker("humerus", 209, 42), marker("ulna", 175, 251)),
            source = ANATOMY + "axilla_tables.html",
            viewKey = "triceps-brachii-posterior",
            selectorLabel = string.health_atlas_triceps_brachii_posterior_selector,
            features = listOf(
                feature("triceps-brachii-long-head", 157, 109, string.health_atlas_triceps_brachii_long_head,
                    string.health_atlas_triceps_brachii_long_head_detail),
                feature("triceps-brachii-lateral-head", 207, 98, string.health_atlas_triceps_brachii_lateral_head,
                    string.health_atlas_triceps_brachii_lateral_head_detail),
                feature("triceps-brachii-medial-head", 150, 170, string.health_atlas_triceps_brachii_medial_head,
                    string.health_atlas_triceps_brachii_medial_head_detail),
                feature("triceps-brachii-distal-tendon", 185, 202, string.health_atlas_triceps_brachii_distal_tendon,
                    string.health_atlas_triceps_brachii_distal_tendon_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_quadriceps_femoris_anterior,
            owner = "quadriceps-femoris",
            viewLabel = string.health_atlas_quadriceps_femoris_anterior_caption,
            markers = listOf(marker("patella", 174, 231)),
            source = ANATOMY + "thigh_tables.html",
            viewKey = "quadriceps-femoris-anterior",
            selectorLabel = string.health_atlas_quadriceps_femoris_anterior_selector,
            features = listOf(
                feature("quadriceps-rectus-femoris", 169, 93, string.health_atlas_quadriceps_rectus_femoris,
                    string.health_atlas_quadriceps_rectus_femoris_detail),
                feature("quadriceps-vastus-lateralis", 125, 117, string.health_atlas_quadriceps_vastus_lateralis,
                    string.health_atlas_quadriceps_vastus_lateralis_detail),
                feature("quadriceps-vastus-medialis", 209, 168, string.health_atlas_quadriceps_vastus_medialis,
                    string.health_atlas_quadriceps_vastus_medialis_detail),
                feature("quadriceps-vastus-intermedius", 286, 112, string.health_atlas_quadriceps_vastus_intermedius,
                    string.health_atlas_quadriceps_vastus_intermedius_detail),
                feature("quadriceps-tendon", 183, 210, string.health_atlas_quadriceps_tendon,
                    string.health_atlas_quadriceps_tendon_detail),
            ),
            splitCallouts = true,
        ),
        HealthAtlasPlate(
            drawable = R.drawable.health_atlas_hamstrings_posterior,
            owner = "hamstrings",
            viewLabel = string.health_atlas_hamstrings_posterior_caption,
            markers = listOf(marker("pelvis", 127, 39), marker("fibula", 219, 251)),
            source = ANATOMY + "gluteal_tables.html",
            viewKey = "hamstrings-posterior",
            selectorLabel = string.health_atlas_hamstrings_posterior_selector,
            features = listOf(
                feature("hamstrings-biceps-femoris-long-head", 203, 119,
                    string.health_atlas_hamstrings_biceps_femoris_long_head,
                    string.health_atlas_hamstrings_biceps_femoris_long_head_detail),
                feature("hamstrings-biceps-femoris-short-head", 187, 166,
                    string.health_atlas_hamstrings_biceps_femoris_short_head,
                    string.health_atlas_hamstrings_biceps_femoris_short_head_detail),
                feature("hamstrings-semitendinosus", 160, 106, string.health_atlas_hamstrings_semitendinosus,
                    string.health_atlas_hamstrings_semitendinosus_detail),
                feature("hamstrings-semimembranosus", 129, 178, string.health_atlas_hamstrings_semimembranosus,
                    string.health_atlas_hamstrings_semimembranosus_detail),
            ),
            splitCallouts = true,
        ),
    )
}
