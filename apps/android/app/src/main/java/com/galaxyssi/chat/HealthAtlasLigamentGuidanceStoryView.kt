package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas

internal class HealthAtlasLigamentGuidanceStoryView(context: Context) :
    HealthAtlasIllustratedStoryView(context, HealthAtlasFunctionStory.LIGAMENT_GUIDANCE) {
    private val aclInk = 0xff30756c
    private val pclInk = 0xff77587a
    private val boneInk = 0xff886e59
    private val anatomy = requireNotNull(context.getDrawable(R.drawable.health_atlas_ligaments_plate)).apply {
        setBounds(0, PLATE_TOP, PLATE_WIDTH, PLATE_TOP + PLATE_HEIGHT)
    }

    init { tag = "atlas-function-ligament-guidance-art" }

    override fun scene(c: Canvas, step: Int, t: Float) {
        val plate = HealthAtlasLigamentsPlate
        anatomy.draw(c)
        callout(c, R.string.health_atlas_ligament_guidance_story_femur, 55f, 55f, 86f, 60f, 143f, 54f, boneInk)
        callout(c, R.string.health_atlas_ligament_guidance_story_tibia, 306f, 212f, 281f, 217f,
            x(plate.tibia), y(plate.tibia), boneInk)
        callout(c, R.string.health_atlas_ligament_guidance_story_acl, 47f, 104f, 67f, 109f,
            x(plate.aclFemur), y(plate.aclFemur), aclInk)
        callout(c, R.string.health_atlas_ligament_guidance_story_pcl, 313f, 104f, 293f, 109f,
            x(plate.pclFemur), y(plate.pclFemur), pclInk)

        val phase = HealthAtlasFunctionStory.safePhase(t)
        val emphasis = phase * phase * (3f - 2f * phase)
        val aclFocus = when (step) { 0 -> phase; 1, 2, 4 -> emphasis; else -> null }
        val pclFocus = when (step) { 0 -> 1f - phase; 1, 3, 4 -> emphasis; else -> null }
        footprints(c, plate.aclFemur, plate.aclTibia, aclInk, aclFocus)
        footprints(c, plate.pclFemur, plate.pclTibia, pclInk, pclFocus)

        if (step >= 2) {
            line(c, 31f, 283f, 329f, 283f, 0xffadc1ba, 1f)
            label(c, R.string.health_atlas_ligament_guidance_story_direction_key, 180f, 302f, 306f)
            if (step >= 3) restraint(c, 159f, 83f, pclInk, emphasis,
                R.string.health_atlas_ligament_guidance_story_backward_slide)
            if (step == 2 || step == 4) restraint(c, 201f, 277f, aclInk, emphasis,
                R.string.health_atlas_ligament_guidance_story_forward_slide)
        }
    }

    private fun callout(c: Canvas, title: Int, textX: Float, baseline: Float, fromX: Float, fromY: Float,
        toX: Float, toY: Float, color: Long) {
        line(c, fromX, fromY, toX, toY, color, 1.05f)
        disc(c, toX, toY, 2.35f, color, cream)
        label(c, title, textX, baseline, 77f)
    }

    private fun footprints(c: Canvas, upper: HealthAtlasMarker, lower: HealthAtlasMarker, color: Long, focus: Float?) {
        footprint(c, upper, color, focus)
        footprint(c, lower, color, focus)
    }

    private fun footprint(c: Canvas, marker: HealthAtlasMarker, color: Long, focus: Float?) {
        disc(c, x(marker), y(marker), 2.55f, color, cream)
        if (focus == null) return
        ink(color, 1.55f)
        paint.alpha = (196f - 76f * focus).toInt()
        c.drawCircle(x(marker), y(marker), 4.5f + 4.5f * focus, paint)
    }

    private fun restraint(c: Canvas, from: Float, stop: Float, color: Long, focus: Float, title: Int) {
        // Fixed arrows show the direction checked by each band, not a force or a tibial displacement.
        val direction = if (stop > from) 1f else -1f
        val tip = stop - direction * 8f
        arrow(c, from, 319f, tip, 319f, color)
        line(c, stop, 313f, stop, 325f, color, 1.55f + 1.45f * focus)
        label(c, title, (from + stop) / 2f, 341f, 136f)
    }

    private fun x(marker: HealthAtlasMarker) = marker.x * PLATE_WIDTH
    private fun y(marker: HealthAtlasMarker) = marker.y * PLATE_HEIGHT + PLATE_TOP

    private companion object {
        const val PLATE_WIDTH = 360
        const val PLATE_HEIGHT = 280
        const val PLATE_TOP = 8
    }
}
