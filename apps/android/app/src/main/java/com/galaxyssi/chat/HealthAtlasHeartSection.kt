package com.galaxyssi.chat

internal enum class HealthAtlasValve(val id: String, val x: Float, val y: Float, private val filling: Boolean) {
    TRICUSPID("tricuspid-valve", 171f, 266f, true),
    MITRAL("mitral-valve", 324f, 248f, true),
    PULMONARY("pulmonary-valve", 228f, 222f, false),
    AORTIC("aortic-valve", 275f, 215f, false);

    fun openAt(stage: Int): Boolean {
        require(stage in 0..3)
        return stage == if (filling) 0 else 2
    }

    companion object {
        fun supports(id: String) = id == "heart-valves" || entries.any { it.id == id }
    }
}

internal object HealthAtlasHeartSection {
    const val ANATOMY_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-1-heart-anatomy"
    const val CYCLE_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-3-cardiac-cycle"
    const val EJECTION_SOURCE = "https://openstax.org/books/anatomy-and-physiology-2e/pages/19-4-cardiac-physiology"

    private fun marker(id: String, x: Float, y: Float) = HealthAtlasMarker(id, x / 480f, y / 460f)
    val section = HealthAtlasPlate(R.drawable.health_atlas_heart_section, "heart",
        R.string.health_atlas_view_cardiac_section, listOf(
            marker("aorta", 336f, 55f), marker("pulmonary-trunk", 237f, 153f),
            marker("left-atrium", 336f, 193f), marker("right-atrium", 171f, 207f),
            marker("right-ventricle", 198f, 303f), marker("left-ventricle", 321f, 298f),
        ), ANATOMY_SOURCE, "heart-section", R.string.health_atlas_cardiac_section)

    val valves = section.copy(viewLabel = R.string.health_atlas_view_cardiac_valves,
        markers = HealthAtlasValve.entries.map { marker(it.id, it.x, it.y) },
        viewKey = null, selectorLabel = null)

    fun forId(id: String): HealthAtlasPlate? = when {
        HealthAtlasValve.supports(id) -> valves
        section.markers.any { it.id == id } -> section
        else -> null
    }
}
