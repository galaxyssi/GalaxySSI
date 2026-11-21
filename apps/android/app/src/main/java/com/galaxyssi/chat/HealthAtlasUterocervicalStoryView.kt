package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.Shader
import com.galaxyssi.chat.R.string
import kotlin.math.abs

internal object HealthAtlasUterocervicalMotion {
    fun sweep(t: Float) = ease((phase(t) - .08f) / .84f)

    fun wallEmphasis(t: Float, layer: Int) =
        ease(1f - abs(phase(t) - (.17f + .33f * layer)) / .26f)

    fun foldDepth(t: Float) = 1f - .53f * ease(1f - abs(2f * phase(t) - 1f))

    private fun phase(t: Float) = if (t.isFinite()) t.coerceIn(0f, 1f) else 0f

    private fun ease(value: Float): Float {
        val f = value.coerceIn(0f, 1f)
        return f * f * (3f - 2f * f)
    }
}

internal class HealthAtlasUterocervicalStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasIllustratedStoryView(context, story) {
    private val a = HealthAtlasUterocervicalAssignment
    private val m = HealthAtlasUterocervicalMotion
    private val edge = 0xff89535d
    private val muscleInk = 0xffa5636d
    private val cervixEdge = 0xff916652
    private val vaginaEdge = 0xff765870
    private val foldInk = 0xff9c6881
    private val guide = 0xff526f70
    private val accent = 0xff24776d
    private val space = 0xfffff5e7
    private val uterusShade = shade(64f, 167f, 0xfff7c5ae, 0xffca8c8e)
    private val cervixShade = shade(105f, 263f, 0xfff6dbc0, 0xffc8927d)
    private val vaginalShade = shade(148f, 280f, 0xffead4df, 0xffb489a4)
    private val muscleShade = shade(111f, 273f, 0xffe7a598, 0xffc4808e)
    private val liningShade = shade(106f, 275f, 0xffffdccb, 0xffecad9f)
    private val foldShade = shade(104f, 270f, 0xfff5dae0, 0xffd8a5bd)
    private val activeTrace = Path()
    private val movingLining = Path()

    // The same schematic stays in place while each region is enlarged.
    private val locatorVagina = shape {
        moveTo(51f, 168f); cubicTo(43f, 180f, 49f, 200f, 61f, 214f)
        cubicTo(72f, 231f, 85f, 252f, 95f, 269f)
        quadTo(104f, 278f, 114f, 269f)
        cubicTo(107f, 246f, 92f, 229f, 86f, 211f)
        cubicTo(81f, 194f, 110f, 183f, 94f, 167f)
        quadTo(72f, 157f, 51f, 168f); close()
    }
    private val locatorVaginalSpace = shape {
        moveTo(55f, 176f); cubicTo(52f, 202f, 85f, 226f, 99f, 268f)
        quadTo(104f, 271f, 109f, 268f)
        cubicTo(96f, 234f, 72f, 218f, 78f, 197f)
        quadTo(94f, 182f, 92f, 176f); close()
    }
    private val locatorCervix = shape {
        moveTo(56f, 138f); quadTo(72f, 129f, 86f, 138f)
        cubicTo(84f, 151f, 94f, 167f, 87f, 186f)
        quadTo(74f, 197f, 60f, 185f)
        cubicTo(54f, 171f, 62f, 153f, 56f, 138f); close()
    }
    private val locatorUterus = shape {
        moveTo(27f, 77f); cubicTo(36f, 64f, 49f, 59f, 72f, 59f)
        cubicTo(95f, 59f, 110f, 66f, 119f, 78f)
        cubicTo(109f, 92f, 113f, 110f, 101f, 123f)
        quadTo(88f, 136f, 85f, 147f)
        quadTo(72f, 154f, 58f, 147f)
        quadTo(56f, 133f, 42f, 121f)
        cubicTo(31f, 108f, 34f, 91f, 27f, 77f); close()
    }
    private val locatorCavity = shape {
        moveTo(37f, 80f); quadTo(72f, 91f, 108f, 80f)
        cubicTo(88f, 93f, 86f, 112f, 76f, 126f)
        quadTo(73f, 130f, 74f, 138f); lineTo(68f, 138f)
        quadTo(69f, 132f, 65f, 125f); cubicTo(54f, 110f, 55f, 95f, 37f, 80f); close()
    }
    private val locatorCanal = shape {
        moveTo(71f, 137f); cubicTo(71f, 153f, 77f, 175f, 74f, 192f)
    }
    private val locatorTraces = listOf(
        track(shape { moveTo(72f, 89f); quadTo(67f, 114f, 71f, 137f) }),
        track(locatorCanal),
        track(shape { moveTo(74f, 192f); cubicTo(66f, 211f, 92f, 236f, 104f, 269f) }),
    )
    private val locatorOs = shape {
        moveTo(62f, 188f); quadTo(74f, 194f, 86f, 188f)
    }
    private val locatorWallTexture = shape {
        moveTo(38f, 89f); quadTo(42f, 112f, 55f, 122f)
        moveTo(107f, 93f); quadTo(104f, 112f, 91f, 123f)
        moveTo(54f, 204f); quadTo(58f, 201f, 63f, 202f)
        moveTo(61f, 216f); quadTo(65f, 212f, 70f, 213f)
        moveTo(69f, 229f); quadTo(73f, 225f, 78f, 227f)
        moveTo(77f, 241f); quadTo(81f, 237f, 86f, 240f)
    }
    private val ownerLabels = intArrayOf(
        string.health_atlas_uterocervical_locator_uterus,
        string.health_atlas_uterocervical_locator_cervix,
        string.health_atlas_uterocervical_locator_vagina,
    )

    private val wallSurface = shape {
        moveTo(209f, 107f); cubicTo(237f, 102f, 272f, 105f, 307f, 115f)
        cubicTo(278f, 158f, 275f, 224f, 291f, 262f)
        quadTo(242f, 275f, 198f, 260f)
        cubicTo(170f, 229f, 174f, 147f, 209f, 107f); close()
    }
    private val wallMuscle = shape {
        moveTo(218f, 106f); quadTo(258f, 103f, 294f, 112f)
        cubicTo(267f, 158f, 263f, 225f, 279f, 265f)
        quadTo(239f, 273f, 206f, 263f)
        cubicTo(178f, 229f, 181f, 149f, 218f, 106f); close()
    }
    private val wallLining = shape {
        moveTo(284f, 110f); lineTo(307f, 115f)
        cubicTo(278f, 158f, 275f, 224f, 291f, 262f)
        lineTo(268f, 267f); cubicTo(250f, 221f, 257f, 154f, 284f, 110f); close()
    }
    private val wallFibers = shape {
        for (i in 0..4) {
            val x = 10f * i
            moveTo(218f + x, 120f)
            cubicTo(194f + x, 151f, 188f + x, 221f, 209f + x, 248f)
            quadTo(216f + x, 256f, 222f + x, 257f)
        }
        for (i in 0..3) {
            val y = 21f * i
            moveTo(196f, 157f + y); quadTo(224f, 152f + y, 255f, 172f + y)
        }
    }
    private val wallGlands = shape {
        for (i in 0..4) {
            val y = 23f * i
            val x = floatArrayOf(290f, 284f, 280f, 280f, 283f)[i]
            moveTo(x, 137f + y); rQuadTo(-14f, -3f, -11f, 7f); rQuadTo(-1f, 4f, 4f, 4f)
        }
    }
    private val wallRims = listOf(
        shape { moveTo(307f, 115f); cubicTo(278f, 158f, 275f, 224f, 291f, 262f) },
        shape { moveTo(251f, 111f); cubicTo(222f, 152f, 218f, 228f, 238f, 266f) },
        shape { moveTo(209f, 107f); cubicTo(174f, 147f, 170f, 229f, 198f, 260f) },
    )

    private val upperVagina = shape {
        moveTo(200f, 207f); quadTo(183f, 224f, 201f, 259f)
        quadTo(211f, 274f, 215f, 288f); lineTo(231f, 287f)
        quadTo(223f, 269f, 221f, 257f); quadTo(211f, 236f, 220f, 224f)
        lineTo(274f, 222f); quadTo(284f, 235f, 274f, 257f)
        quadTo(270f, 275f, 271f, 287f); lineTo(287f, 288f)
        quadTo(289f, 274f, 297f, 252f); quadTo(310f, 220f, 291f, 207f); close()
    }
    private val neck = shape {
        moveTo(194f, 95f); quadTo(217f, 86f, 243f, 95f)
        quadTo(270f, 87f, 297f, 96f)
        cubicTo(274f, 123f, 284f, 151f, 285f, 179f)
        cubicTo(288f, 217f, 282f, 246f, 267f, 251f)
        quadTo(249f, 257f, 230f, 251f)
        cubicTo(209f, 247f, 207f, 217f, 209f, 183f)
        cubicTo(211f, 153f, 217f, 127f, 194f, 95f); close()
    }
    private val canalSpace = shape {
        moveTo(219f, 91f); quadTo(242f, 94f, 270f, 91f)
        quadTo(245f, 112f, 248f, 123f)
        cubicTo(250f, 149f, 260f, 170f, 259f, 195f)
        quadTo(259f, 227f, 253f, 253f)
        lineTo(244f, 253f); quadTo(238f, 228f, 238f, 193f)
        cubicTo(235f, 161f, 244f, 141f, 241f, 123f)
        quadTo(241f, 109f, 219f, 91f); close()
    }
    private val neckCollagen = shape {
        for (i in 0..4) {
            val y = 16f * i
            moveTo(217f, 162f + y); quadTo(229f, 170f + y, 233f, 183f + y)
            moveTo(278f, 161f + y); quadTo(265f, 170f + y, 264f, 183f + y)
        }
    }
    private val canalFolds = shape {
        for (i in 0..3) {
            val y = 16f * i
            moveTo(239f, 154f + y); rQuadTo(-8f, -7f, -11f, -9f)
            moveTo(257f, 167f + y); rQuadTo(5f, -8f, 10f, -10f)
        }
    }
    private val neckTrace = track(shape {
        moveTo(244f, 122f); cubicTo(244f, 151f, 252f, 171f, 249f, 193f)
        quadTo(250f, 229f, 248f, 253f)
    })

    private val deepVaginalWall = shape {
        moveTo(199f, 104f); quadTo(217f, 98f, 235f, 107f)
        cubicTo(211f, 138f, 218f, 209f, 256f, 267f)
        quadTo(245f, 279f, 230f, 274f)
        cubicTo(191f, 228f, 175f, 150f, 199f, 104f); close()
    }
    private val muscleVaginalWall = shape {
        moveTo(210f, 102f); quadTo(223f, 102f, 235f, 107f)
        cubicTo(211f, 148f, 220f, 213f, 256f, 267f)
        quadTo(251f, 273f, 240f, 275f)
        cubicTo(206f, 235f, 185f, 154f, 210f, 102f); close()
    }
    private val facingVaginalWall = shape {
        moveTo(258f, 104f); quadTo(277f, 101f, 289f, 111f)
        cubicTo(260f, 154f, 276f, 230f, 291f, 259f)
        quadTo(285f, 271f, 273f, 271f)
        cubicTo(255f, 244f, 232f, 150f, 258f, 104f); close()
    }
    private val vaginalMuscleFibers = shape {
        for (i in 0..2) {
            val x = 4f * i
            moveTo(209f + x, 120f)
            cubicTo(193f + x, 155f, 209f + x, 225f, 237f + x, 260f)
        }
    }

    override fun scene(c: Canvas, step: Int, t: Float) {
        rounded(c, 12f, 21f, 140f, 344f, 7f, 0x70ffffff)
        rounded(c, 150f, 21f, 348f, 344f, 7f, 0x80ffffff)
        label(c, string.health_atlas_uterocervical_locator, 76f, 43f, 110f)
        label(c, string.health_atlas_uterocervical_magnification, 249f, 43f, 178f)
        locator(c, step, t)
        when (step) {
            a.UTERUS_WALL -> uterus(c, t)
            a.CERVICAL_CANAL -> cervix(c, t)
            a.VAGINAL_WALL -> vagina(c, t)
        }
    }

    private fun locator(c: Canvas, step: Int, t: Float) {
        surface(c, locatorVagina, vaginalShade, vaginaEdge)
        ink(space); c.drawPath(locatorVaginalSpace, paint)
        stroke(c, locatorVaginalSpace, vaginaEdge, 1f)
        // Keep the lower end open rather than putting a contour across the aperture.
        line(c, 100f, 269f, 108f, 269f, space, 2.3f)
        surface(c, locatorCervix, cervixShade, cervixEdge)
        surface(c, locatorUterus, uterusShade, edge)
        ink(space); c.drawPath(locatorCavity, paint)
        stroke(c, locatorCavity, edge, 1f)
        stroke(c, locatorWallTexture, 0xffaa7482, 1f)
        stroke(c, locatorCanal, cervixEdge, 6f)
        stroke(c, locatorCanal, space, 4.2f)
        stroke(c, locatorOs, cervixEdge, 1f)
        stroke(c, if (step == a.UTERUS_WALL) locatorUterus else if (step == a.CERVICAL_CANAL) locatorCervix else locatorVagina,
            accent, 1.6f)
        trace(c, locatorTraces[step], m.sweep(t))
        line(c, 49f, 304f, 103f, 304f, accent, 1.1f)
        label(c, ownerLabels[step], 76f, 326f, 108f)
    }

    private fun uterus(c: Canvas, t: Float) {
        surface(c, wallSurface, liningShade, edge)
        surface(c, wallMuscle, muscleShade, muscleInk)
        c.save()
        c.clipPath(wallMuscle)
        stroke(c, wallFibers, 0xffcc8586, 1.2f)
        c.restore()
        surface(c, wallLining, liningShade, edge)
        stroke(c, wallGlands, 0xffac6573, 1.3f)
        wallRims.forEachIndexed { index, rim ->
            val emphasis = m.wallEmphasis(t, index)
            if (emphasis > 0f) stroke(c, rim, withAlpha(accent, (180f * emphasis).toInt()), 1.2f + 4f * emphasis)
        }
        callout(c, string.health_atlas_uterocervical_endometrium, 293f, 83f, 103f, 294f, 92f, 287f, 132f)
        callout(c, string.health_atlas_uterocervical_perimetrium, 199f, 313f, 92f, 197f, 297f, 188f, 238f)
        callout(c, string.health_atlas_uterocervical_myometrium, 286f, 328f, 105f, 272f, 312f, 242f, 226f)
    }

    private fun cervix(c: Canvas, t: Float) {
        surface(c, upperVagina, foldShade, vaginaEdge)
        surface(c, neck, cervixShade, cervixEdge)
        stroke(c, neckCollagen, 0xffc29387, 1.3f)
        stroke(c, canalFolds, 0xffb87d67, 1.4f)
        ink(space); c.drawPath(canalSpace, paint)
        stroke(c, canalSpace, cervixEdge, 1.2f)
        line(c, 245f, 253f, 252f, 253f, space, 2.6f)
        trace(c, neckTrace, m.sweep(t))
        callout(c, string.health_atlas_uterocervical_internal_os, 207f, 75f, 100f, 212f, 83f, 244f, 122f)
        callout(c, string.health_atlas_uterocervical_canal, 293f, 316f, 86f, 299f, 299f, 257f, 194f)
        callout(c, string.health_atlas_uterocervical_external_os, 205f, 316f, 82f, 207f, 300f, 248f, 253f)
    }

    private fun vagina(c: Canvas, t: Float) {
        surface(c, facingVaginalWall, foldShade, vaginaEdge)
        surface(c, deepVaginalWall, vaginalShade, vaginaEdge)
        surface(c, muscleVaginalWall, muscleShade, muscleInk)
        stroke(c, vaginalMuscleFibers, 0xffaa6878, 1.2f)

        // Only the folded surface changes; the canal does not rhythmically open or close.
        val depth = m.foldDepth(t)
        movingLining.rewind()
        movingLining.moveTo(233f, 106f)
        for (i in 0..4) {
            val y = 108f + 22f * i
            val x = 232f - 4.4f * i + 1.12f * i * i
            movingLining.cubicTo(x - 5f, y + 4f, x - 3f + 15f * depth, y + 7f, x + 15f * depth, y + 11f)
            movingLining.cubicTo(x + 17f * depth, y + 15f, x - 3f, y + 17f, x - 2f, y + 22f)
        }
        movingLining.cubicTo(244f, 237f, 252f, 253f, 260f, 267f)
        movingLining.quadTo(256f, 273f, 250f, 272f)
        movingLining.cubicTo(211f, 221f, 203f, 144f, 223f, 103f)
        movingLining.close()
        surface(c, movingLining, foldShade, foldInk)

        line(c, 259f, 269f, 273f, 271f, accent, 1.35f)
        callout(c, string.health_atlas_uterocervical_folds, 244f, 81f, 117f, 246f, 90f, 229f + 15f * depth, 141f)
        callout(c, string.health_atlas_uterocervical_muscle, 204f, 316f, 84f, 205f, 300f, 219f, 232f)
        callout(c, string.health_atlas_uterocervical_opening, 295f, 316f, 94f, 294f, 300f, 266f, 270f)
    }

    private fun callout(c: Canvas, res: Int, x: Float, baseline: Float, width: Float,
        leadX: Float, leadY: Float, anchorX: Float, anchorY: Float) {
        line(c, leadX, leadY, anchorX, anchorY, guide, 1f)
        disc(c, anchorX, anchorY, 2.3f, space, guide)
        label(c, res, x, baseline, width)
    }

    private fun trace(c: Canvas, measure: PathMeasure, progress: Float) {
        activeTrace.rewind()
        if (measure.getSegment(0f, progress * measure.length, activeTrace, true)) {
            stroke(c, activeTrace, accent, 2.15f)
        }
        at(measure, progress) { x, y -> disc(c, x, y, 2.9f, accent, space) }
    }

    private fun surface(c: Canvas, path: Path, fill: Shader, border: Long) {
        ink(space)
        paint.shader = fill
        c.drawPath(path, paint)
        paint.shader = null
        stroke(c, path, border, 1.25f)
    }

    private inline fun shape(block: Path.() -> Unit) = Path().apply(block)

    private fun withAlpha(color: Long, alpha: Int) = (color and 0x00ffffff) or (alpha.toLong() shl 24)
}
