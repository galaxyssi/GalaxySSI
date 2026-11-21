package com.galaxyssi.chat

internal enum class HealthAtlasVisionStage(val title: Int, val caption: Int) {
    ENTRY(R.string.health_atlas_vision_story_entry, R.string.health_atlas_vision_story_entry_caption),
    FOCUS(R.string.health_atlas_vision_story_focus, R.string.health_atlas_vision_story_focus_caption),
    CAPTURE(R.string.health_atlas_vision_story_capture, R.string.health_atlas_vision_story_capture_caption),
    RELAY(R.string.health_atlas_vision_story_relay, R.string.health_atlas_vision_story_relay_caption),
    OUTPUT(R.string.health_atlas_vision_story_output, R.string.health_atlas_vision_story_output_caption),
    DIM(R.string.health_atlas_vision_story_dim, R.string.health_atlas_vision_story_dim_caption),
    ROD(R.string.health_atlas_vision_story_rod, R.string.health_atlas_vision_story_rod_caption),
    MIXED(R.string.health_atlas_vision_story_mixed, R.string.health_atlas_vision_story_mixed_caption),
    BRIGHT(R.string.health_atlas_vision_story_bright, R.string.health_atlas_vision_story_bright_caption),
    COLOR(R.string.health_atlas_vision_story_color, R.string.health_atlas_vision_story_color_caption);

    // Display values illustrate relative illumination, with no lux, time or sensitivity calibration.
    fun displayLight(fraction: Float): Float = when (this) {
        DIM -> .68f - .53f * fraction
        ROD -> .15f
        MIXED -> .15f + .43f * fraction
        BRIGHT -> .58f + .36f * fraction
        COLOR -> .94f
        else -> 0f
    }

    companion object {
        val pathway = listOf(ENTRY, FOCUS, CAPTURE, RELAY, OUTPUT)
        val adaptation = listOf(DIM, ROD, MIXED, BRIGHT, COLOR)
    }
}
