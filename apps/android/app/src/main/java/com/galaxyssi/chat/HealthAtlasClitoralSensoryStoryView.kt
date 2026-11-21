package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import com.galaxyssi.chat.HealthAtlasClitoralSensoryAssignment as Lesson
import com.galaxyssi.chat.R.string

internal class HealthAtlasClitoralSensoryStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val cutaway = requireNotNull(context.getDrawable(R.drawable.health_atlas_clitoral_cutaway))
    private val guide = 0xff778d91
    private val nerve = 0xffaa7745
    private val nerveLight = 0xffe7c993
    private val signal = 0xff307e83
    private val trail = Path()

    private val endingTissue = Path().apply {
        moveTo(51f, 133f)
        cubicTo(78f, 78f, 217f, 75f, 286f, 115f)
        cubicTo(320f, 135f, 313f, 202f, 278f, 223f)
        cubicTo(229f, 256f, 91f, 244f, 57f, 206f)
        cubicTo(41f, 186f, 41f, 157f, 51f, 133f)
        close()
    }
    private val endingEdge = Path().apply {
        moveTo(55f, 141f)
        cubicTo(89f, 95f, 213f, 93f, 280f, 125f)
    }
    private val endingRoute = Path().apply {
        moveTo(112f, 135f)
        cubicTo(109f, 164f, 141f, 161f, 155f, 182f)
        cubicTo(176f, 218f, 220f, 211f, 236f, 239f)
        cubicTo(248f, 257f, 247f, 275f, 250f, 287f)
    }
    private val endingBranches = Path().apply {
        moveTo(155f, 182f); cubicTo(147f, 166f, 160f, 141f, 151f, 125f)
        moveTo(138f, 169f); cubicTo(126f, 174f, 107f, 171f, 92f, 157f)
        moveTo(197f, 211f); cubicTo(202f, 178f, 182f, 159f, 193f, 129f)
        moveTo(199f, 182f); cubicTo(205f, 166f, 222f, 164f, 227f, 142f)
        moveTo(232f, 233f); cubicTo(250f, 213f, 251f, 190f, 263f, 178f)
    }
    private val dorsalRoute = Path().apply {
        moveTo(179f, 145f)
        cubicTo(169f, 137f, 168f, 123f, 167f, 111f)
        cubicTo(162f, 105f, 145f, 118f, 135f, 129f)
        cubicTo(107f, 154f, 91f, 182f, 83f, 212f)
        cubicTo(77f, 240f, 80f, 250f, 62f, 263f)
        cubicTo(56f, 268f, 52f, 273f, 51f, 281f)
    }
    private val pudendalBranch = Path().apply {
        moveTo(72f, 254f); cubicTo(94f, 264f, 104f, 277f, 109f, 291f)
    }
    private val sacralRoute = Path().apply {
        moveTo(41f, 247f)
        cubicTo(70f, 240f, 87f, 216f, 111f, 190f)
        cubicTo(143f, 147f, 167f, 127f, 199f, 133f)
        cubicTo(220f, 136f, 230f, 145f, 254f, 157f)
    }
    private val ventralRoot = Path().apply {
        moveTo(111f, 190f); cubicTo(156f, 185f, 177f, 225f, 232f, 200f)
    }
    private val grayMatter = Path().apply {
        moveTo(250f, 152f)
        cubicTo(258f, 153f, 260f, 170f, 271f, 172f)
        cubicTo(284f, 174f, 289f, 154f, 298f, 152f)
        cubicTo(309f, 150f, 294f, 172f, 286f, 183f)
        cubicTo(282f, 191f, 304f, 200f, 295f, 212f)
        cubicTo(288f, 221f, 278f, 201f, 273f, 199f)
        cubicTo(266f, 200f, 258f, 221f, 249f, 213f)
        cubicTo(239f, 202f, 259f, 191f, 257f, 183f)
        cubicTo(255f, 176f, 241f, 153f, 250f, 152f)
        close()
    }
    private val endingTrack = track(endingRoute)
    private val dorsalTrack = track(dorsalRoute)
    private val sacralTrack = track(sacralRoute)
    private val tissueShade = shade(96f, 244f, 0xfff9e1d4, 0xffcc9ca9)
    private val cordShade = shade(122f, 243f, 0xfff8e4d5, 0xffd3a8af)

    override fun scene(c: Canvas, step: Int, t: Float) {
        when (step) {
            Lesson.CUTAWAY -> structure(c, t)
            Lesson.ENDINGS -> endings(c, t)
            Lesson.DORSAL_ROUTE -> dorsal(c, t)
            Lesson.SACRAL_ENTRY -> sacral(c, t)
        }
    }

    private fun structure(c: Canvas, t: Float) {
        cutaway.setBounds(0, 36, 360, 316)
        cutaway.draw(c)
        leader(c, 121f, 91f, 176f, 119f)
        leader(c, 232f, 132f, 181f, 156f)
        leader(c, 75f, 258f, 104f, 210f)
        leader(c, 241f, 264f, 215f, 223f)
        label(c, string.health_atlas_clitoral_sensory_body, 78f, 91f, 82f)
        label(c, string.health_atlas_clitoral_sensory_glans, 274f, 132f, 78f)
        label(c, string.health_atlas_clitoral_sensory_crura, 68f, 279f, 118f)
        label(c, string.health_atlas_clitoral_sensory_bulbs, 254f, 285f, 146f)
        // The introductory scan highlights anatomy without moving the tissue.
        when ((t * 4).toInt().coerceAtMost(3)) {
            0 -> ring(c, 176f, 119f, t * 4)
            1 -> ring(c, 181f, 156f, t * 4 - 1)
            2 -> ring(c, 104f, 210f, t * 4 - 2)
            3 -> ring(c, 215f, 223f, t * 4 - 3)
        }
    }

    private fun endings(c: Canvas, t: Float) {
        ink(cream); paint.shader = tissueShade; c.drawPath(endingTissue, paint); paint.shader = null
        stroke(c, endingTissue, 0xffab7f8e, 1.5f)
        stroke(c, endingEdge, 0xfffff0e2, 3f)
        stroke(c, endingBranches, nerve, 2f)
        stroke(c, endingRoute, nerve, 4f)
        stroke(c, endingRoute, nerveLight, 1.8f)
        pulse(c, endingTrack, t)
        leader(c, 113f, 69f, 112f, 135f)
        leader(c, 223f, 301f, 249f, 277f)
        label(c, string.health_atlas_clitoral_sensory_endings, 113f, 59f, 145f)
        label(c, string.health_atlas_clitoral_sensory_afferent, 220f, 321f, 160f)
    }

    private fun dorsal(c: Canvas, t: Float) {
        cutaway.setBounds(0, 25, 360, 305)
        cutaway.draw(c)
        c.save()
        c.scale(-1f, 1f, 180f, 0f)
        stroke(c, pudendalBranch, 0xffc5a985, 2f)
        stroke(c, dorsalRoute, 0xffc5a985, 3f)
        c.restore()
        stroke(c, pudendalBranch, 0xffc5a985, 2f)
        stroke(c, dorsalRoute, nerve, 4.4f)
        stroke(c, dorsalRoute, nerveLight, 2f)
        pulse(c, dorsalTrack, t)
        leader(c, 104f, 78f, 142f, 123f)
        leader(c, 99f, 301f, 66f, 262f)
        label(c, string.health_atlas_clitoral_sensory_dorsal_nerve, 89f, 64f, 158f)
        label(c, string.health_atlas_clitoral_sensory_pudendal, 98f, 321f, 155f)
    }

    private fun sacral(c: Canvas, t: Float) {
        oval(c, 221f, 121f, 326f, 244f, cordShade, 0xffa5808d)
        ink(0xffbc8c9b); c.drawPath(grayMatter, paint)
        stroke(c, grayMatter, 0xffa67989, 1.2f)
        disc(c, 273f, 183f, 2.5f, cream, 0xffa67989)
        stroke(c, ventralRoot, 0xffccb3a5, 4f)
        oval(c, 153f, 122f, 189f, 150f, 0xffecd8b5, nerve)
        stroke(c, sacralRoute, nerve, 5f)
        stroke(c, sacralRoute, nerveLight, 2f)
        pulse(c, sacralTrack, t)
        leader(c, 164f, 100f, 172f, 134f)
        leader(c, 275f, 101f, 273f, 123f)
        leader(c, 95f, 270f, 76f, 228f)
        label(c, string.health_atlas_clitoral_sensory_dorsal_root, 155f, 88f, 112f)
        label(c, string.health_atlas_clitoral_sensory_cord, 277f, 88f, 111f)
        label(c, string.health_atlas_clitoral_sensory_pudendal, 97f, 292f, 145f)
    }

    private fun leader(c: Canvas, x: Float, y: Float, atX: Float, atY: Float) {
        line(c, x, y, atX, atY, guide, 1f)
        disc(c, atX, atY, 2.1f, cream, guide)
    }

    private fun ring(c: Canvas, x: Float, y: Float, t: Float) {
        ink(signal, 1.2f)
        paint.alpha = (125f * (1f - wave(t + .25f))).toInt()
        c.drawCircle(x, y, 5f + 4f * t, paint)
    }

    private fun pulse(c: Canvas, track: PathMeasure, t: Float) {
        val head = t * track.length
        trail.rewind()
        if (track.getSegment((head - 26f).coerceAtLeast(0f), head, trail, true)) {
            stroke(c, trail, signal, 3.1f)
        }
        at(track, t) { x, y -> disc(c, x, y, 4.1f, 0xfff7f6df, signal) }
    }
}
