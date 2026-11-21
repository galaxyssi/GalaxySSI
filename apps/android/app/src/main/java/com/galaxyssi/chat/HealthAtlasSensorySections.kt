package com.galaxyssi.chat

internal object HealthAtlasSensorySections {
    operator fun get(id: String?) = when (id) {
        "ear" -> ear
        "retina" -> retina
        else -> null
    }

    private val ear by lazy {
        val original = requireNotNull(HealthAtlasPlates.forId("ear"))
        fun feature(id: String, x: Int, y: Int, title: Int, stage: Int) =
            HealthAtlasFeature(HealthAtlasMarker(id, x / 460f, y / 280f), title, stage)

        val features = listOf(
            feature("ear-canal", 148, 140, R.string.health_atlas_external_ear_name, R.string.health_atlas_hearing_ear_0),
            feature("eardrum", 214, 138, R.string.health_atlas_hearing_eardrum, R.string.health_atlas_hearing_ear_1),
            feature("ossicles", 254, 111, R.string.health_atlas_hearing_ossicles, R.string.health_atlas_hearing_ear_2),
            feature("cochlea-output", 361, 177, R.string.health_atlas_cochlea_name, R.string.health_atlas_hearing_ear_3),
        )
        val routes = listOf(
            atlasSectionTrack(40f, 137f) { cubicTo(66f, 130f, 77f, 137f, 95f, 140f); quadTo(132f, 136f, 179f, 137f) },
            atlasSectionTrack(179f, 137f) { quadTo(193f, 140f, 214f, 138f) },
            atlasSectionTrack(220f, 137f) { lineTo(231f, 106f); quadTo(248f, 91f, 255f, 109f); lineTo(262f, 141f); lineTo(289f, 141f) },
            atlasSectionTrack(357f, 179f) { cubicTo(377f, 176f, 397f, 181f, 442f, 198f) },
        )
        HealthAtlasSectionLesson(original.copy(features = features), listOf(0, 1, 2, 3), routes,
            listOf(R.string.health_atlas_hearing_route_scope), artWidth = 460)
    }

    private val retina by lazy {
        val original = requireNotNull(HealthAtlasPlates.forId("retina"))
        fun feature(id: String, title: Int, detail: Int) =
            HealthAtlasFeature(original.markers.single { it.id == id }, title, detail)

        // The cross-section shows layers, not every interneuron in the circuit view.
        val features = listOf(
            feature("cell-rod-photoreceptor", R.string.health_atlas_sensory_retinal_rod_label, R.string.health_atlas_sensory_rod_discs_detail),
            original.features.single { it.marker.id == "retina-relay-layer" },
            feature("cell-cone-photoreceptor", R.string.health_atlas_sensory_retinal_cone_label, R.string.health_atlas_sensory_cone_outer_segment_detail),
            feature("cell-retinal-ganglion-cell", R.string.health_atlas_sensory_retinal_ganglion, R.string.health_atlas_sensory_rgc_axon_detail),
        )
        HealthAtlasSectionLesson(original.copy(markers = emptyList(), features = features),
            listOf(0, 1, 2, 3), emptyList(), emptyList())
    }
}
