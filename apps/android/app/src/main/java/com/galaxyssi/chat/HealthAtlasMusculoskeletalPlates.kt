package com.galaxyssi.chat

/** Only surface structures visibly represented by each teaching plate receive hotspots. */
internal object HealthAtlasMusculoskeletalPlates {
    private const val SKELETAL_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/7-1-divisions-of-the-skeletal-system"
    private const val MUSCLE_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/11-2-naming-skeletal-muscles"
    val all = listOf(
        HealthAtlasPlate(R.drawable.health_atlas_skeleton_front, "skeletal", R.string.health_atlas_skeleton_front,
            listOf(HealthAtlasMarker("skull", .50f, .07f), HealthAtlasMarker("clavicle", .60f, .17f),
                HealthAtlasMarker("sternum", .50f, .22f), HealthAtlasMarker("ribs", .60f, .293f),
                HealthAtlasMarker("pelvis", .60f, .43f), HealthAtlasMarker("femur", .60f, .58f),
                HealthAtlasMarker("patella", .58f, .69f), HealthAtlasMarker("tibia", .57f, .80f)),
            SKELETAL_SOURCE, "skeletal-anterior"),
        HealthAtlasPlate(R.drawable.health_atlas_skeleton_back, "skeletal", R.string.health_atlas_skeleton_back,
            listOf(HealthAtlasMarker("scapula", .63f, .22f), HealthAtlasMarker("humerus", .75f, .27f),
                HealthAtlasMarker("vertebrae", .51f, .34f), HealthAtlasMarker("ulna", .82f, .41f),
                HealthAtlasMarker("hand-bones", .91f, .52f), HealthAtlasMarker("fibula", .645f, .79f),
                HealthAtlasMarker("foot-bones", .66f, .97f)), SKELETAL_SOURCE, "skeletal-posterior"),
        HealthAtlasPlate(R.drawable.health_atlas_muscle_front, "muscle", R.string.health_atlas_muscle_front,
            listOf(HealthAtlasMarker("deltoid", .66f, .22f), HealthAtlasMarker("pectoralis-major", .57f, .24f),
                HealthAtlasMarker("biceps-brachii", .68f, .30f), HealthAtlasMarker("rectus-abdominis", .54f, .35f),
                HealthAtlasMarker("oblique-abdominal-muscles", .61f, .38f), HealthAtlasMarker("quadriceps-femoris", .59f, .58f)),
            MUSCLE_SOURCE, "muscle-anterior"),
        HealthAtlasPlate(R.drawable.health_atlas_muscle_back, "muscle", R.string.health_atlas_muscle_back,
            listOf(HealthAtlasMarker("trapezius", .57f, .20f), HealthAtlasMarker("triceps-brachii", .67f, .29f),
                HealthAtlasMarker("latissimus-dorsi", .60f, .31f), HealthAtlasMarker("gluteus-maximus", .58f, .46f),
                HealthAtlasMarker("hamstrings", .59f, .58f), HealthAtlasMarker("gastrocnemius", .60f, .77f),
                HealthAtlasMarker("tendons", .60f, .90f)), MUSCLE_SOURCE, "muscle-posterior")
    )

    fun viewsForId(id: String?) = all.filter { it.owner == id || it.markers.any { marker -> marker.id == id } }
}
