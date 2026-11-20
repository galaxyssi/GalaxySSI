package com.galaxyssi.chat

internal enum class HealthAtlasDigestionStage(val title: Int, val caption: Int) {
    SWALLOW(R.string.health_atlas_meal_swallow, R.string.health_atlas_meal_swallow_caption),
    PERISTALSIS(R.string.health_atlas_meal_esophagus, R.string.health_atlas_meal_esophagus_caption),
    STOMACH(R.string.health_atlas_meal_stomach, R.string.health_atlas_meal_stomach_caption),
    DUODENUM(R.string.health_atlas_meal_duodenum, R.string.health_atlas_meal_duodenum_caption),
    VILLUS(R.string.health_atlas_meal_villus, R.string.health_atlas_meal_villus_caption),
    CECUM(R.string.health_atlas_colon_story_cecum, R.string.health_atlas_colon_story_cecum_caption),
    MIX(R.string.health_atlas_colon_story_mix, R.string.health_atlas_colon_story_mix_caption),
    WATER(R.string.health_atlas_colon_story_water, R.string.health_atlas_colon_story_water_caption),
    PROPULSION(R.string.health_atlas_colon_story_propulsion, R.string.health_atlas_colon_story_propulsion_caption),
    RECTUM(R.string.health_atlas_colon_story_rectum, R.string.health_atlas_colon_story_rectum_caption);

    companion object {
        val meal = listOf(SWALLOW, PERISTALSIS, STOMACH, DUODENUM, VILLUS)
        val colon = listOf(CECUM, MIX, WATER, PROPULSION, RECTUM)
    }
}
