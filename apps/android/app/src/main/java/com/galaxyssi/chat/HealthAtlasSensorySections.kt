package com.galaxyssi.chat

internal object HealthAtlasSensorySections {
    private const val EAR_WIDTH = 420

    operator fun get(id: String?) = when (id) {
        "ear" -> ear
        "retina" -> retina
        "cell-inner-ear-hair-cell" -> hairCell
        "cell-rod-photoreceptor" -> rod
        "cell-cone-photoreceptor" -> cone
        else -> null
    }

    private val ear by lazy {
        val original = requireNotNull(HealthAtlasPlates.forId("ear"))
        fun feature(id: String, x: Int, y: Int, title: Int, stage: Int) =
            HealthAtlasFeature(HealthAtlasMarker(id, x.toFloat() / EAR_WIDTH, y / 280f), title, stage)

        val features = listOf(
            feature("ear-canal", 135, 145, R.string.health_atlas_external_ear_name, R.string.health_atlas_hearing_ear_0),
            feature("eardrum", 187, 139, R.string.health_atlas_hearing_eardrum, R.string.health_atlas_hearing_ear_1),
            feature("ossicles", 223, 118, R.string.health_atlas_hearing_ossicles, R.string.health_atlas_hearing_ear_2),
            feature("cochlea-output", 319, 156, R.string.health_atlas_cochlea_name, R.string.health_atlas_hearing_ear_3),
        )
        // Match the 3:2 plate. The final track follows the nerve, not the auditory tube.
        val routes = listOf(
            atlasSectionTrack(79f, 149f) { cubicTo(100f, 146f, 124f, 144f, 153f, 145f) },
            atlasSectionTrack(153f, 145f) { quadTo(172f, 145f, 187f, 139f) },
            atlasSectionTrack(195f, 145f) {
                quadTo(202f, 111f, 211f, 109f)
                cubicTo(221f, 109f, 228f, 113f, 229f, 120f)
                quadTo(233f, 133f, 236f, 143f)
                lineTo(266f, 144f)
            },
            atlasSectionTrack(319f, 156f) {
                cubicTo(344f, 153f, 351f, 151f, 361f, 147f)
                cubicTo(382f, 143f, 395f, 138f, 411f, 135f)
            },
        )
        HealthAtlasSectionLesson(original.copy(features = features), listOf(0, 1, 2, 3), routes,
            listOf(R.string.health_atlas_hearing_route_scope), artWidth = EAR_WIDTH)
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

    private fun portrait(plate: HealthAtlasPlate, stages: List<Int>) =
        HealthAtlasSectionLesson(plate, stages, emptyList(), emptyList(), artWidth = 280, artHeight = 420)

    private val rod by lazy {
        portrait(requireNotNull(HealthAtlasPlates.forId("cell-rod-photoreceptor")), listOf(0, 0, 0, 1))
    }
    private val cone by lazy {
        portrait(requireNotNull(HealthAtlasPlates.forId("cell-cone-photoreceptor")), listOf(0, 0, 0, 1))
    }
    private val hairCell by lazy {
        val plate = requireNotNull(HealthAtlasPlates.forId("cell-inner-ear-hair-cell"))
        val body = HealthAtlasFeature(HealthAtlasMarker("hair-cell-receptor-body", .431f, .574f),
            R.string.health_atlas_cell_inner_ear_hair_cell_name,
            R.string.health_atlas_process_cell_inner_ear_hair_cell_2)
        portrait(plate.copy(features = plate.features + body), listOf(0, 0, 2, 1))
    }
}
