package com.galaxyssi.chat

internal enum class HealthAtlasNephronRoute {
    FILTRATE, BLOOD, FILTER, REABSORB, LOOP_WATER, LOOP_SALT, SECRETE, DUCT_WATER, URINE
}

internal enum class HealthAtlasNephronStage(val title: Int, val caption: Int, val routes: List<HealthAtlasNephronRoute>) {
    FILTER(R.string.health_atlas_nephron_story_filter, R.string.health_atlas_nephron_story_filter_caption,
        listOf(HealthAtlasNephronRoute.BLOOD, HealthAtlasNephronRoute.FILTER)),
    PROXIMAL(R.string.health_atlas_nephron_story_prox, R.string.health_atlas_nephron_story_prox_caption,
        listOf(HealthAtlasNephronRoute.FILTRATE, HealthAtlasNephronRoute.REABSORB)),
    LOOP(R.string.health_atlas_nephron_story_loop, R.string.health_atlas_nephron_story_loop_caption,
        listOf(HealthAtlasNephronRoute.FILTRATE, HealthAtlasNephronRoute.LOOP_WATER, HealthAtlasNephronRoute.LOOP_SALT)),
    DISTAL(R.string.health_atlas_nephron_story_distal, R.string.health_atlas_nephron_story_distal_caption,
        listOf(HealthAtlasNephronRoute.FILTRATE, HealthAtlasNephronRoute.SECRETE)),
    COLLECT(R.string.health_atlas_nephron_story_collect, R.string.health_atlas_nephron_story_collect_caption,
        listOf(HealthAtlasNephronRoute.DUCT_WATER, HealthAtlasNephronRoute.URINE));
}
