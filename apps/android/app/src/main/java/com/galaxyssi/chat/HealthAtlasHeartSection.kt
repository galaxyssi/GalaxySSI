package com.galaxyssi.chat

private const val HEART_SECTION_SIZE = 1254f

private fun heartSectionMarker(id: String, x: Int, y: Int) =
    HealthAtlasMarker(id, x / HEART_SECTION_SIZE, y / HEART_SECTION_SIZE)

internal enum class HealthAtlasValve(val id: String, x: Int, y: Int, private val filling: Boolean) {
    TRICUSPID("tricuspid-valve", 451, 707, true),
    MITRAL("mitral-valve", 859, 659, true),
    PULMONARY("pulmonary-valve", 599, 603, false),
    AORTIC("aortic-valve", 708, 589, false);

    val marker = heartSectionMarker(id, x, y)

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

    val section = HealthAtlasPlate(R.drawable.health_atlas_heart_section, "heart",
        R.string.health_atlas_view_cardiac_section, listOf(
            heartSectionMarker("aorta", 885, 177), heartSectionMarker("pulmonary-trunk", 613, 459),
            heartSectionMarker("left-atrium", 860, 531), heartSectionMarker("right-atrium", 423, 563),
            heartSectionMarker("right-ventricle", 443, 838), heartSectionMarker("left-ventricle", 788, 885),
        ), ANATOMY_SOURCE, "heart-section", R.string.health_atlas_cardiac_section)

    val valves = section.copy(viewLabel = R.string.health_atlas_view_cardiac_valves,
        markers = HealthAtlasValve.entries.map(HealthAtlasValve::marker),
        viewKey = null, selectorLabel = null)

    fun forId(id: String): HealthAtlasPlate? = when {
        HealthAtlasValve.supports(id) -> valves
        section.markers.any { it.id == id } -> section
        else -> null
    }
}
