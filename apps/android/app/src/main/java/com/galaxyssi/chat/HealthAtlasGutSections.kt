package com.galaxyssi.chat

internal object HealthAtlasGutSections {
    private const val BOOK = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private const val UPPER = BOOK + "23-3-the-mouth-pharynx-and-esophagus"
    private const val STOMACH = BOOK + "23-4-the-stomach"
    private const val INTESTINES = BOOK + "23-5-the-small-and-large-intestines"

    private fun marker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 360f, y / 280f)
    private fun feature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(marker(id, x, y), title, explanation)
    private fun paintedMarker(id: String, x: Int, y: Int) = HealthAtlasMarker(id, x / 1254f, y / 1254f)
    private fun paintedFeature(id: String, x: Int, y: Int, title: Int, explanation: Int) =
        HealthAtlasFeature(paintedMarker(id, x, y), title, explanation)
    private fun section(id: String, art: Int, caption: Int, source: String, features: List<HealthAtlasFeature>,
        links: List<HealthAtlasMarker>, steps: List<Int>, tracks: List<HealthAtlasSectionTrack> = emptyList(),
        note: Int? = null, squareArt: Boolean = false) =
        HealthAtlasSectionLesson(HealthAtlasPlate(art, id, caption, links, source, features = features), steps, tracks,
            listOfNotNull(if (tracks.isEmpty()) R.string.health_atlas_gut_section_regional_scope else R.string.health_atlas_gut_section_motion_scope, note),
            artHeight = if (squareArt) 360 else 280)

    private val lessons = listOf(
        section("oral-cavity", R.drawable.health_atlas_gut_mouth, R.string.health_atlas_gut_section_mouth_view, UPPER,
            listOf(
                feature("mouth-0", 155, 103, R.string.health_atlas_gut_section_mouth_feature_0, R.string.health_atlas_gut_section_mouth_detail_0),
                feature("mouth-1", 154, 155, R.string.health_atlas_gut_section_mouth_feature_1, R.string.health_atlas_gut_section_mouth_detail_1),
                feature("mouth-2", 259, 153, R.string.health_atlas_gut_section_mouth_feature_2, R.string.health_atlas_gut_section_mouth_detail_2)),
            listOf(marker("teeth", 103, 123), marker("tongue", 173, 167), marker("pharynx", 274, 165)),
            listOf(0, 1, 1, 2)),
        section("teeth", R.drawable.health_atlas_gut_tooth, R.string.health_atlas_gut_section_tooth_view, UPPER,
            listOf(
                paintedFeature("tooth-0", 461, 324, R.string.health_atlas_gut_section_tooth_feature_0, R.string.health_atlas_gut_section_tooth_detail_0),
                paintedFeature("tooth-1", 492, 393, R.string.health_atlas_gut_section_tooth_feature_1, R.string.health_atlas_gut_section_tooth_detail_1),
                paintedFeature("tooth-2", 606, 555, R.string.health_atlas_gut_section_tooth_feature_2, R.string.health_atlas_gut_section_tooth_detail_2),
                paintedFeature("tooth-3", 846, 777, R.string.health_atlas_gut_section_tooth_feature_3, R.string.health_atlas_gut_section_tooth_detail_3)),
            listOf(),
            listOf(0, 1, 3, 2), squareArt = true),
        section("esophagus", R.drawable.health_atlas_gut_esophagus, R.string.health_atlas_gut_section_esophagus_view, UPPER,
            listOf(
                feature("esophagus-0", 179, 50, R.string.health_atlas_gut_section_esophagus_feature_0, R.string.health_atlas_gut_section_esophagus_detail_0),
                feature("esophagus-1", 145, 111, R.string.health_atlas_gut_section_esophagus_feature_1, R.string.health_atlas_gut_section_esophagus_detail_1),
                feature("esophagus-2", 180, 177, R.string.health_atlas_gut_section_esophagus_feature_2, R.string.health_atlas_gut_section_esophagus_detail_2),
                feature("esophagus-3", 191, 223, R.string.health_atlas_gut_section_esophagus_feature_3, R.string.health_atlas_gut_section_esophagus_detail_3)),
            listOf(marker("stomach", 206, 242)),
            listOf(0, 1, 2, 3),
            tracks = listOf(
                atlasSectionTrack(180f, 45f) { quadTo(179f, 63f, 177f, 82f) },
                atlasSectionTrack(177f, 82f) { quadTo(168f, 106f, 174f, 129f) },
                atlasSectionTrack(174f, 129f) { cubicTo(182f, 146f, 189f, 172f, 193f, 195f) },
                atlasSectionTrack(193f, 195f) { cubicTo(195f, 225f, 194f, 232f, 226f, 246f) })),
        section("stomach", R.drawable.health_atlas_gut_stomach, R.string.health_atlas_gut_section_stomach_view, STOMACH,
            listOf(
                feature("stomach-0", 221, 66, R.string.health_atlas_gut_section_stomach_feature_0, R.string.health_atlas_gut_section_stomach_detail_0),
                feature("stomach-1", 207, 116, R.string.health_atlas_gut_section_stomach_feature_1, R.string.health_atlas_gut_section_stomach_detail_1),
                feature("stomach-2", 145, 184, R.string.health_atlas_gut_section_stomach_feature_2, R.string.health_atlas_gut_section_stomach_detail_2),
                feature("stomach-3", 91, 177, R.string.health_atlas_gut_section_stomach_feature_3, R.string.health_atlas_gut_section_stomach_detail_3)),
            listOf(marker("duodenum", 60, 194), marker("cell-gastric-parietal-cell", 239, 115)),
            listOf(0, 1, 2, 3),
            tracks = listOf(
                atlasSectionTrack(186f, 45f) { cubicTo(185f, 68f, 193f, 88f, 212f, 94f) },
                atlasSectionTrack(212f, 94f) { cubicTo(249f, 74f, 278f, 102f, 256f, 133f) },
                atlasSectionTrack(256f, 133f) {
                    cubicTo(239f, 159f, 172f, 197f, 132f, 175f)
                    quadTo(160f, 155f, 204f, 148f)
                },
                atlasSectionTrack(204f, 148f) { quadTo(169f, 186f, 104f, 177f); quadTo(85f, 181f, 66f, 190f) })),
        section("small-intestine", R.drawable.health_atlas_gut_small, R.string.health_atlas_gut_section_small_view, INTESTINES,
            listOf(
                feature("small-0", 104, 68, R.string.health_atlas_gut_section_small_feature_0, R.string.health_atlas_gut_section_small_detail_0),
                feature("small-1", 176, 139, R.string.health_atlas_gut_section_small_feature_1, R.string.health_atlas_gut_section_small_detail_1),
                feature("small-2", 227, 224, R.string.health_atlas_gut_section_small_feature_2, R.string.health_atlas_gut_section_small_detail_2)),
            listOf(marker("duodenum", 142, 82), marker("jejunum", 219, 105), marker("ileum", 199, 174)),
            listOf(0, 1, 1, 2),
            tracks = listOf(
                atlasSectionTrack(78f, 59f) { quadTo(97f, 60f, 104f, 68f); quadTo(122f, 88f, 142f, 82f) },
                atlasSectionTrack(142f, 82f) { cubicTo(173f, 69f, 217f, 74f, 219f, 105f); quadTo(220f, 129f, 193f, 134f) },
                atlasSectionTrack(193f, 134f) { quadTo(153f, 142f, 146f, 154f); quadTo(142f, 173f, 170f, 178f) },
                atlasSectionTrack(170f, 178f) { quadTo(225f, 166f, 233f, 187f); quadTo(247f, 210f, 227f, 224f); lineTo(246f, 240f) }), note = R.string.health_atlas_gut_section_regional_map_note),
        section("duodenum", R.drawable.health_atlas_gut_duodenum, R.string.health_atlas_gut_section_duodenum_view, INTESTINES,
            listOf(
                feature("duodenum-0", 260, 65, R.string.health_atlas_gut_section_duodenum_feature_0, R.string.health_atlas_gut_section_duodenum_detail_0),
                feature("duodenum-1", 257, 134, R.string.health_atlas_gut_section_duodenum_feature_1, R.string.health_atlas_gut_section_duodenum_detail_1),
                feature("duodenum-2", 137, 198, R.string.health_atlas_gut_section_duodenum_feature_2, R.string.health_atlas_gut_section_duodenum_detail_2)),
            listOf(marker("pancreatic-duct", 159, 148), marker("biliary-tract", 210, 93), marker("jejunum", 102, 214)),
            listOf(0, 1, 1, 2),
            tracks = listOf(
                atlasSectionTrack(175f, 65f) { quadTo(235f, 58f, 260f, 65f) },
                atlasSectionTrack(260f, 65f) { cubicTo(286f, 75f, 290f, 107f, 278f, 138f) },
                atlasSectionTrack(278f, 138f) { quadTo(265f, 180f, 218f, 195f) },
                atlasSectionTrack(218f, 195f) { cubicTo(175f, 213f, 128f, 183f, 102f, 214f) })),
        section("jejunum", R.drawable.health_atlas_gut_jejunum, R.string.health_atlas_gut_section_jejunum_view, INTESTINES,
            listOf(
                paintedFeature("jejunum-0", 318, 918, R.string.health_atlas_gut_section_jejunum_feature_0, R.string.health_atlas_gut_section_jejunum_detail_0),
                paintedFeature("jejunum-1", 615, 336, R.string.health_atlas_gut_section_jejunum_feature_1, R.string.health_atlas_gut_section_jejunum_detail_1),
                paintedFeature("jejunum-2", 608, 461, R.string.health_atlas_gut_section_jejunum_feature_2, R.string.health_atlas_gut_section_jejunum_detail_2),
                paintedFeature("jejunum-3", 643, 607, R.string.health_atlas_gut_section_jejunum_feature_3, R.string.health_atlas_gut_section_jejunum_detail_3)),
            listOf(paintedMarker("cell-enterocyte", 550, 430), paintedMarker("lymphatic-vessels", 620, 801)),
            listOf(0, 1, 2, 3), squareArt = true),
        section("ileum", R.drawable.health_atlas_gut_ileum, R.string.health_atlas_gut_section_ileum_view, INTESTINES,
            listOf(
                feature("ileum-0", 94, 118, R.string.health_atlas_gut_section_ileum_feature_0, R.string.health_atlas_gut_section_ileum_detail_0),
                feature("ileum-1", 140, 161, R.string.health_atlas_gut_section_ileum_feature_1, R.string.health_atlas_gut_section_ileum_detail_1),
                feature("ileum-2", 214, 139, R.string.health_atlas_gut_section_ileum_feature_2, R.string.health_atlas_gut_section_ileum_detail_2)),
            listOf(marker("cecum", 267, 181), marker("gut-associated-lymphoid-tissue", 160, 171)),
            listOf(0, 0, 1, 2)),
        section("large-intestine", R.drawable.health_atlas_gut_large, R.string.health_atlas_gut_section_large_view, INTESTINES,
            listOf(
                feature("large-0", 85, 185, R.string.health_atlas_gut_section_large_feature_0, R.string.health_atlas_gut_section_large_detail_0),
                feature("large-1", 180, 57, R.string.health_atlas_gut_section_large_feature_1, R.string.health_atlas_gut_section_large_detail_1),
                feature("large-2", 236, 198, R.string.health_atlas_gut_section_large_feature_2, R.string.health_atlas_gut_section_large_detail_2),
                feature("large-3", 177, 233, R.string.health_atlas_gut_section_large_feature_3, R.string.health_atlas_gut_section_large_detail_3)),
            listOf(marker("cecum", 77, 207), marker("colon", 265, 108), marker("rectum", 180, 244), marker("anal-canal", 177, 259)),
            listOf(0, 1, 2, 3),
            tracks = listOf(
                atlasSectionTrack(45f, 173f) { cubicTo(60f, 172f, 67f, 181f, 83f, 185f) },
                atlasSectionTrack(83f, 185f) { lineTo(83f, 95f); quadTo(83f, 57f, 112f, 57f); lineTo(180f, 57f) },
                atlasSectionTrack(180f, 57f) { lineTo(233f, 57f); quadTo(270f, 58f, 272f, 98f); lineTo(269f, 164f); quadTo(264f, 181f, 244f, 192f) },
                atlasSectionTrack(244f, 192f) { quadTo(228f, 210f, 203f, 206f); quadTo(177f, 202f, 177f, 233f); lineTo(177f, 247f) }), note = R.string.health_atlas_gut_section_front_note),
        section("cecum", R.drawable.health_atlas_gut_cecum, R.string.health_atlas_gut_section_cecum_view, INTESTINES,
            listOf(
                feature("cecum-0", 152, 135, R.string.health_atlas_gut_section_cecum_feature_0, R.string.health_atlas_gut_section_cecum_detail_0),
                feature("cecum-1", 216, 183, R.string.health_atlas_gut_section_cecum_feature_1, R.string.health_atlas_gut_section_cecum_detail_1),
                feature("cecum-2", 165, 190, R.string.health_atlas_gut_section_cecum_feature_2, R.string.health_atlas_gut_section_cecum_detail_2)),
            listOf(marker("ileum", 102, 127), marker("appendix", 146, 222), marker("colon", 215, 53)),
            listOf(0, 1, 2, 1),
            tracks = listOf(
                atlasSectionTrack(57f, 114f) { quadTo(120f, 119f, 167f, 138f) },
                atlasSectionTrack(167f, 138f) { quadTo(201f, 146f, 216f, 183f) },
                atlasSectionTrack(216f, 183f) { quadTo(225f, 188f, 232f, 174f) },
                atlasSectionTrack(232f, 174f) { quadTo(219f, 115f, 215f, 53f) }), note = R.string.health_atlas_gut_section_case_valve),
        section("appendix", R.drawable.health_atlas_gut_appendix, R.string.health_atlas_gut_section_appendix_view, INTESTINES,
            listOf(
                feature("appendix-0", 176, 131, R.string.health_atlas_gut_section_appendix_feature_0, R.string.health_atlas_gut_section_appendix_detail_0),
                feature("appendix-1", 148, 116, R.string.health_atlas_gut_section_appendix_feature_1, R.string.health_atlas_gut_section_appendix_detail_1),
                feature("appendix-2", 222, 160, R.string.health_atlas_gut_section_appendix_feature_2, R.string.health_atlas_gut_section_appendix_detail_2)),
            listOf(marker("cell-b-cell", 221, 177), marker("gut-associated-lymphoid-tissue", 125, 170)),
            listOf(0, 1, 2, 2)),
        section("colon", R.drawable.health_atlas_gut_colon, R.string.health_atlas_gut_section_colon_view, INTESTINES,
            listOf(
                feature("colon-0", 77, 105, R.string.health_atlas_gut_section_colon_feature_0, R.string.health_atlas_gut_section_colon_detail_0),
                feature("colon-1", 166, 148, R.string.health_atlas_gut_section_colon_feature_1, R.string.health_atlas_gut_section_colon_detail_1),
                feature("colon-2", 253, 121, R.string.health_atlas_gut_section_colon_feature_2, R.string.health_atlas_gut_section_colon_detail_2)),
            listOf(marker("cell-goblet-cell", 185, 161)),
            listOf(0, 1, 2, 0)),
        section("rectum", R.drawable.health_atlas_gut_rectum, R.string.health_atlas_gut_section_rectum_view, INTESTINES,
            listOf(
                feature("rectum-0", 141, 61, R.string.health_atlas_gut_section_rectum_feature_0, R.string.health_atlas_gut_section_rectum_detail_0),
                feature("rectum-1", 184, 129, R.string.health_atlas_gut_section_rectum_feature_1, R.string.health_atlas_gut_section_rectum_detail_1),
                feature("rectum-2", 176, 200, R.string.health_atlas_gut_section_rectum_feature_2, R.string.health_atlas_gut_section_rectum_detail_2)),
            listOf(marker("anal-canal", 201, 232)),
            listOf(0, 1, 1, 2)),
        section("anal-canal", R.drawable.health_atlas_gut_anal, R.string.health_atlas_gut_section_anal_view, INTESTINES,
            listOf(
                feature("anal-0", 146, 149, R.string.health_atlas_gut_section_anal_feature_0, R.string.health_atlas_gut_section_anal_detail_0),
                feature("anal-1", 222, 171, R.string.health_atlas_gut_section_anal_feature_1, R.string.health_atlas_gut_section_anal_detail_1),
                feature("anal-2", 181, 178, R.string.health_atlas_gut_section_anal_feature_2, R.string.health_atlas_gut_section_anal_detail_2)),
            listOf(marker("rectum", 181, 50), marker("cell-skeletal-myocyte", 228, 202)),
            listOf(0, 0, 1, 2))
    ).associateBy(HealthAtlasSectionLesson::owner)
    val all = lessons.values.map(HealthAtlasSectionLesson::plate)
    operator fun get(id: String?) = lessons[id]
}
