package com.galaxyssi.chat

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.graphics.RectF
import android.graphics.Shader
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

internal object HealthAtlasMovementGeometry {
    const val ACTIN_LENGTH = 80f
    const val MYOSIN_LENGTH = 122f
    fun ease(t: Float) = t * t * (3f - 2f * t)
    fun sarcomereHalfWidth(t: Float) = 111f - 33f * ease(t)
    fun elbowAngle(extending: Boolean, t: Float) = 96f * ease(if (extending) 1f - t else t)
    fun erosionDepth(chapter: Int, t: Float) = when (chapter) {
        0 -> 0f
        1 -> 62f * ease(t)
        else -> 62f
    }
    fun exposedDepth(chapter: Int, t: Float) = when (chapter) {
        3 -> 62f - 48f * ease(t)
        4 -> 14f
        else -> erosionDepth(chapter, t)
    }
}

internal class HealthAtlasMovementStoryView(context: Context, story: HealthAtlasFunctionStory) :
    HealthAtlasFunctionArt(context, story) {
    private val bone = story == HealthAtlasFunctionStory.BONE_REMODELING
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
        textAlign = Paint.Align.CENTER
        typeface = android.graphics.Typeface.create("sans-serif-medium", android.graphics.Typeface.NORMAL)
    }
    private val field = RectF(0f, 0f, 340f, 340f)
    private val scratch = Path()
    private val wave = Path()
    private val xy = FloatArray(2)
    private val nerve = track {
        moveTo(29f, 112f); cubicTo(91f, 113f, 91f, 55f, 149f, 77f)
        cubicTo(174f, 86f, 164f, 120f, 174f, 131f)
    }
    private val tubule = track {
        moveTo(33f, 139f); lineTo(151f, 139f); quadTo(166f, 139f, 166f, 158f)
        lineTo(166f, 224f); quadTo(166f, 246f, 177f, 246f)
        quadTo(188f, 246f, 188f, 224f); lineTo(188f, 159f)
        quadTo(188f, 139f, 202f, 139f); lineTo(303f, 139f)
    }
    private val paper = gradient(0f, 340f, 0xfff0f8f8, 0xfffbf2e4)
    private val fiberPaint = gradient(142f, 282f, 0xfff8cfc1, 0xffd99589)
    private val matrixPaint = gradient(145f, 302f, 0xfff9e5c4, 0xffd5b48e)
    private val boneShade = horizontalShade(0xffbd9675, 0xfffdf3dc, 0xffd7b898)
    private val flexorShade = horizontalShade(0xff923f50, 0xffdc9290, 0xffa14e5d)
    private val extensorShade = horizontalShade(0xff66527f, 0xffb7a2cb, 0xff83628d)
    private val osteoclastShade = gradient(-48f, 1f, 0xfff3c5cb, 0xffbb7183)
    private val nerveColor = 0xff467a8e
    private val teal = 0xff347c78
    private val scarlet = 0xffae5660
    private val purple = 0xff81669b
    private val amber = 0xffb57735
    private val edge = 0xff8a614b
    private val textColor = 0xff24464f
    private val white = 0xfffaf9f1

    init { tag = if (bone) "atlas-function-bone-remodeling-art" else "atlas-function-muscle-motion-art" }

    override fun onDraw(canvas: Canvas) {
        val scale = minOf(width, height) / 340f
        if (scale <= 0f) return
        val chapter = story.chapter(phase)
        val t = story.fraction(phase)
        canvas.save()
        canvas.translate((width - 340f * scale) / 2f, (height - 340f * scale) / 2f)
        canvas.scale(scale, scale)
        ink(white)
        paint.shader = paper
        canvas.drawRoundRect(field, 8f, 8f, paint)
        paint.shader = null
        if (bone) remodeling(canvas, chapter, t) else when (chapter) {
            0 -> signal(canvas, t)
            1 -> calcium(canvas, t)
            2 -> sliding(canvas, t)
            else -> elbow(canvas, chapter == 4, t)
        }
        canvas.restore()
    }

    private fun muscleFiber(c: Canvas) {
        ink(0xffdba396)
        paint.shader = fiberPaint
        c.drawRoundRect(21f, 139f, 319f, 284f, 33f, 33f, paint)
        paint.shader = null
        ink(0xffac6a67, 1.5f)
        c.drawRoundRect(21f, 139f, 319f, 284f, 33f, 33f, paint)
        for (i in 0..15) {
            val x = 38f + 17.5f * i
            oval(c, x, 158f, 4f, 9f, 0xfff9dfd4)
            oval(c, x, 263f, 4f, 10f, 0xffedbcad)
            line(c, x, 183f, x, 239f, 0xffc6857c, .85f)
        }
        for (y in 178..246 step 17) line(c, 30f, y.toFloat(), 309f, y.toFloat(), 0xffc6857c, 1f)
    }

    private fun signal(c: Canvas, t: Float) {
        muscleFiber(c)
        strokeTrack(c, nerve, 0xffb8d5df, 22f)
        strokeTrack(c, nerve, nerveColor, 3f)
        oval(c, 177f, 132f, 19f, 10f, nerveColor)
        for (i in 0..2) pulse(c, nerve, cycle(t * 1.3f + i * .14f), white, 2.9f)
        for (i in 0..8) {
            val f = cycle(t * 1.8f + i / 9f)
            oval(c, 159f + (i % 5) * 8.5f, 134f + 18f * f, 2.5f, 2.5f, amber)
        }
        for (sign in listOf(-1, 1)) {
            val x = 177f + sign * (15f + 109f * cycle(t * 1.25f))
            line(c, x - 7f, 150f, x + 7f, 150f, teal, 3.2f)
        }
        leader(c, 103f, 56f, 117f, 83f, R.string.health_atlas_motion_axon, nerveColor)
        leader(c, 265f, 112f, 193f, 148f, R.string.health_atlas_motion_ach, amber)
        label(c, 170f, 316f, R.string.health_atlas_motion_fiber)
    }

    private fun calcium(c: Canvas, t: Float) {
        muscleFiber(c)
        strokeTrack(c, tubule, white, 16f)
        strokeTrack(c, tubule, nerveColor, 1.8f)
        pulse(c, tubule, cycle(t * 1.45f), teal, 5f)
        for (side in listOf(-1, 1)) {
            val x = 177f + side * 35f
            oval(c, x, 201f, 11f, 35f, 0xffb6cfca)
            oval(c, x, 201f, 5f, 26f, teal)
            for (i in 0..7) {
                val f = cycle(t * 1.3f + i / 8f)
                oval(c, x + side * (10f + 43f * f), 176f + i * 6.6f + (i % 2) * f * 16f,
                    3.2f, 3.2f, amber)
            }
        }
        leader(c, 94f, 106f, 166f, 163f, R.string.health_atlas_motion_tubule, nerveColor)
        leader(c, 249f, 92f, 212f, 175f, R.string.health_atlas_motion_store, teal)
        label(c, 170f, 316f, R.string.health_atlas_motion_ca)
    }

    private fun sliding(c: Canvas, t: Float) {
        val left = 170f - HealthAtlasMovementGeometry.sarcomereHalfWidth(t)
        val right = 340f - left
        for (y in 131..222 step 34) {
            val h = y.toFloat()
            line(c, left, h, left + HealthAtlasMovementGeometry.ACTIN_LENGTH, h, teal, 4.2f)
            line(c, right, h, right - HealthAtlasMovementGeometry.ACTIN_LENGTH, h, teal, 4.2f)
            val start = 170f - HealthAtlasMovementGeometry.MYOSIN_LENGTH / 2
            line(c, start, h + 14f, 340f - start, h + 14f, scarlet, 7f)
            for (i in 0..8) {
                val x = start + 8f + i * 13f
                line(c, x, h + 14f, x + (if (i < 4) 1 else -1) * (4f + 2f * sin(t * 18f + i)),
                    h + 5f, scarlet, 2.5f)
            }
        }
        for (x in listOf(left, right)) {
            line(c, x, 113f, x, 236f, edge, 5f)
            line(c, x, 270f, x, 290f, edge, 1.3f)
        }
        line(c, left, 280f, right, 280f, edge, 1.3f)
        leader(c, 73f, 78f, left + 32f, 131f, R.string.health_atlas_motion_actin, teal)
        leader(c, 258f, 78f, 205f, 145f, R.string.health_atlas_motion_myosin, scarlet)
        label(c, 170f, 312f, R.string.health_atlas_motion_sarcomere)
    }

    private fun elbow(c: Canvas, extending: Boolean, t: Float) {
        val angle = HealthAtlasMovementGeometry.elbowAngle(extending, t)
        val rad = angle * PI.toFloat() / 180f
        val pivotX = 131f
        val pivotY = 189f
        val radiusX = pivotX + 33f * sin(rad) + 7f * cos(rad)
        val radiusY = pivotY + 33f * cos(rad) - 7f * sin(rad)
        val ulnaX = pivotX + 10f * sin(rad) - 10f * cos(rad)
        val ulnaY = pivotY + 10f * cos(rad) + 10f * sin(rad)
        boneBar(c, 132f, 62f, pivotX, pivotY, 14f)
        c.save()
        c.rotate(-angle, pivotX, pivotY)
        boneBar(c, 121f, 195f, 125f, 284f, 9f)
        boneBar(c, 139f, 213f, 144f, 286f, 10f)
        c.restore()
        muscle(c, 149f, 64f, radiusX, radiusY, 15f + 6f * angle / 96f, scarlet)
        muscle(c, 112f, 71f, ulnaX, ulnaY, 18f - 5f * angle / 96f, purple)
        leader(c, 251f, 75f, 157f, 110f, R.string.health_atlas_motion_biceps, scarlet)
        leader(c, 56f, 113f, 106f, 120f, R.string.health_atlas_motion_triceps, purple)
        leader(c, 54f, 212f, pivotX - 3f, pivotY + 3f, R.string.health_atlas_motion_joint, nerveColor)
        leader(c, 260f, 238f, radiusX, radiusY, R.string.health_atlas_motion_tendon, edge)
        if (extending) label(c, 170f, 319f, R.string.health_atlas_motion_reuptake)
    }

    private fun boneBar(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, width: Float) {
        val dx = x2 - x1
        val dy = y2 - y1
        val length = sqrt(dx * dx + dy * dy)
        c.save()
        c.translate(x1, y1)
        c.rotate(-kotlin.math.atan2(dx, dy) * 180f / PI.toFloat())
        c.scale(width / 12f, 1f)
        shape {
            moveTo(-7f, -7f)
            cubicTo(-3f, -15f, 9f, -14f, 10f, -5f)
            cubicTo(11f, 3f, 6f, 10f, 5f, 22f)
            cubicTo(3f, length * .47f, 4f, length - 28f, 7f, length - 12f)
            cubicTo(10f, length - 4f, 13f, length + 2f, 7f, length + 7f)
            cubicTo(1f, length + 12f, -10f, length + 10f, -11f, length + 1f)
            cubicTo(-10f, length - 7f, -5f, length - 20f, -5f, length - 32f)
            cubicTo(-4f, length * .46f, -4f, 19f, -7f, 7f)
            quadTo(-10f, 0f, -7f, -7f)
            close()
        }
        ink(white); paint.shader = boneShade; c.drawPath(scratch, paint); paint.shader = null
        ink(edge, 1.3f); c.drawPath(scratch, paint)
        shape { moveTo(0f, 13f); quadTo(-1.5f, length * .58f, 1f, length - 11f) }
        ink(white, 1.2f); c.drawPath(scratch, paint)
        c.restore()
    }

    private fun muscle(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, width: Float, fill: Long) {
        val dx = x2 - x1
        val dy = y2 - y1
        val length = sqrt(dx * dx + dy * dy)
        c.save()
        c.translate(x1, y1)
        c.rotate(-kotlin.math.atan2(dx, dy) * 180f / PI.toFloat())
        line(c, 0f, 0f, 0f, length, edge, 5.6f)
        line(c, 0f, 0f, 0f, length, 0xffe8dac4, 3.8f)
        c.scale(width / 17f, 1f)
        shape {
            moveTo(0f, length * .10f)
            cubicTo(8f, length * .23f, 18f, length * .46f, 10f, length * .65f)
            quadTo(5f, length * .76f, 0f, length * .84f)
            cubicTo(-9f, length * .71f, -19f, length * .48f, -10f, length * .30f)
            quadTo(-5f, length * .21f, 0f, length * .10f)
            close()
        }
        ink(fill); paint.shader = if (fill == scarlet) flexorShade else extensorShade
        c.drawPath(scratch, paint); paint.shader = null
        ink(fill, 1.15f); c.drawPath(scratch, paint)
        for (i in -3..3) {
            shape {
                moveTo(i * .6f, length * (.17f + .012f * kotlin.math.abs(i)))
                cubicTo(i * 4.1f, length * .36f, i * 3.5f, length * .57f, i * .4f, length * .77f)
            }
            ink(0x9ff7d6cf, .85f); c.drawPath(scratch, paint)
        }
        c.restore()
    }

    private fun remodeling(c: Canvas, chapter: Int, t: Float) {
        val depth = HealthAtlasMovementGeometry.exposedDepth(chapter, t)
        val original = HealthAtlasMovementGeometry.erosionDepth(chapter, t)
        matrix(c, original, true)
        if (chapter >= 3) {
            shape {
                surface(this, depth)
                for (x in 318 downTo 22 step 4) lineTo(x.toFloat(), boneY(x.toFloat(), original))
                close()
            }
            val ratio = if (chapter == 4) t else 0f
            ink(blend(0xff8ac2b2, 0xffecd5ab, ratio)); c.drawPath(scratch, paint)
            if (chapter == 4) for (i in 0..14) {
                val x = 111f + i * 8.5f
                val y = boneY(x, depth) + 4f + (boneY(x, original) - boneY(x, depth) - 8f) * (.15f + .11f * (i % 5))
                if (t > i * .043f) oval(c, x, y, 2.1f, 1.4f, edge)
            }
        }
        matrix(c, depth, false)
        osteocyte(c, 76f, 227f, if (chapter == 0) t else null)
        osteocyte(c, 202f, 260f)
        osteocyte(c, 282f, 214f)
        when (chapter) {
            0 -> {
                repeat(3) { i ->
                    val dy = 24f * cycle(t * 1.35f + i * .23f)
                    val x = 63f + 29f * i
                    line(c, x, 101f + dy, x, 127f + dy, amber, 2.2f)
                    line(c, x, 127f + dy, x - 4f, 121f + dy, amber, 2.2f)
                    line(c, x, 127f + dy, x + 4f, 121f + dy, amber, 2.2f)
                }
                label(c, 92f, 78f, R.string.health_atlas_bone_loading)
                leader(c, 99f, 296f, 76f, 227f, R.string.health_atlas_bone_osteocyte, purple)
            }
            1 -> {
                val y = boneY(170f, depth)
                osteoclast(c, depth)
                for (i in 0..5) {
                    val f = cycle(t * 1.8f + i / 6f)
                    val x = 149f + i * 8f
                    oval(c, x, boneY(x, depth) - 1f - f * 5f, 1.5f, 1.5f, amber)
                }
                leader(c, 170f, 83f, 170f, y - 48f, R.string.health_atlas_bone_osteoclast, scarlet)
            }
            2 -> {
                for (i in 0..5) {
                    val x = 112f + i * 19f + 5f * sin(t * 4f + i)
                    surfaceCell(c, x, boneY(x, depth), 5f, purple)
                }
                leader(c, 170f, 100f, 170f, boneY(170f, depth) - 12f, R.string.health_atlas_bone_reversal_cells, purple)
            }
            3 -> {
                for (i in 0..6) {
                    val x = 111f + i * 19.5f
                    surfaceCell(c, x, boneY(x, depth), 8f, teal)
                }
                leader(c, 170f, 100f, 170f, boneY(170f, depth) - 16f, R.string.health_atlas_bone_osteoblast, teal)
            }
            4 -> {
                osteocyte(c, 166f, 184f + 5f * t)
                leader(c, 170f, 100f, 166f, 184f + 5f * t, R.string.health_atlas_bone_osteocyte, purple)
            }
        }
        label(c, 170f, 317f, when (chapter) {
            3 -> R.string.health_atlas_bone_osteoid
            4 -> R.string.health_atlas_bone_new
            else -> R.string.health_atlas_bone_old
        })
    }

    private fun matrix(c: Canvas, depth: Float, fill: Boolean) {
        shape {
            surface(this, depth)
            if (fill) { lineTo(318f, 291f); lineTo(22f, 291f); close() }
        }
        if (!fill) {
            ink(edge, 1.4f); c.drawPath(scratch, paint)
            return
        }
        ink(white); paint.shader = matrixPaint
        c.drawPath(scratch, paint); paint.shader = null
        c.save()
        c.clipPath(scratch)
        for (i in 0..5) {
            val y = 169f + i * 23f
            shape { moveTo(17f, y); cubicTo(109f, y + 8f, 220f, y + 17f, 320f, y - 1f) }
            ink(0xffc59e77, 1.2f); c.drawPath(scratch, paint)
        }
        for (i in 0..31) {
            val x = 29f + i * 91 % 282
            val y = 155f + i * 43 % 128
            oval(c, x, y, 1.4f, .9f, 0xffd0ab84)
        }
        c.restore()
    }

    private fun boneY(x: Float, depth: Float): Float {
        val local = ((x - 81f) / 178f).coerceIn(0f, 1f)
        val cup = sin(local * PI.toFloat())
        return 151f + cup * cup * depth
    }

    private fun surface(p: Path, depth: Float) {
        p.moveTo(22f, boneY(22f, depth))
        for (x in 26..318 step 4) p.lineTo(x.toFloat(), boneY(x.toFloat(), depth))
    }

    private fun osteoclast(c: Canvas, depth: Float) {
        val floor = boneY(170f, depth)
        fun contact(x: Float) = boneY(x, depth) - floor
        c.save()
        c.translate(0f, floor)
        shape {
            moveTo(121f, contact(121f))
            cubicTo(130f, -41f, 138f, -51f, 155f, -47f)
            cubicTo(179f, -55f, 210f, -46f, 219f, contact(219f))
            for (i in 8 downTo 0) {
                val x = 125f + i * 10.5f
                quadTo(x + 5f, contact(x + 5f) - 6f, x, contact(x))
            }
            close()
        }
        ink(white); paint.shader = osteoclastShade; c.drawPath(scratch, paint); paint.shader = null
        ink(scarlet, 1.4f); c.drawPath(scratch, paint)
        for (i in 0..3) {
            val x = 144f + i * 17f
            val y = -34f + i % 2 * 5f
            oval(c, x, y, 6.8f, 4.9f, 0xffa791b2)
            oval(c, x + .7f, y + .5f, 5f, 3.7f, purple)
            oval(c, x - 1.5f, y - .6f, 1.3f, 1f, 0xffccb1cc)
        }
        c.restore()
    }

    private fun osteocyte(c: Canvas, x: Float, y: Float, t: Float? = null) {
        for (i in 0..6) {
            val a = i * 2f * PI.toFloat() / 7f
            line(c, x, y, x + cos(a) * 15f, y + sin(a) * 11f, purple, .9f)
        }
        oval(c, x, y, 7f, 4.5f, purple)
        oval(c, x, y, 2.7f, 2.2f, white)
        if (t != null) {
            ink(amber, 1.6f)
            c.drawCircle(x, y, 12f + 16f * cycle(t * 1.2f), paint)
        }
    }

    private fun surfaceCell(c: Canvas, x: Float, y: Float, h: Float, color: Long) {
        oval(c, x, y - h, 8f, h, color)
        oval(c, x, y - h - .5f, 2.8f, 2f, white)
    }

    private fun leader(c: Canvas, x: Float, y: Float, toX: Float, toY: Float, title: Int, color: Long) {
        line(c, x, y + 5f, toX, toY, color, 1.05f)
        oval(c, toX, toY, 2.75f, 2.75f, white)
        oval(c, toX, toY, 1.7f, 1.7f, color)
        label(c, x, y, title)
    }

    private fun label(c: Canvas, x: Float, y: Float, title: Int) {
        ink(textColor)
        paint.textSize = 13f
        c.drawText(context.getString(title), x, y, paint)
    }

    private fun strokeTrack(c: Canvas, track: PathMeasure, color: Long, width: Float) {
        wave.rewind()
        track.getSegment(0f, track.length, wave, true)
        ink(color, width); c.drawPath(wave, paint)
    }

    private fun pulse(c: Canvas, track: PathMeasure, fraction: Float, color: Long, r: Float) {
        if (track.getPosTan(track.length * fraction, xy, null)) oval(c, xy[0], xy[1], r, r, color)
    }

    private fun oval(c: Canvas, x: Float, y: Float, rx: Float, ry: Float, fill: Long) {
        ink(fill)
        c.drawOval(x - rx, y - ry, x + rx, y + ry, paint)
    }

    private fun line(c: Canvas, x1: Float, y1: Float, x2: Float, y2: Float, color: Long, width: Float) {
        ink(color, width); c.drawLine(x1, y1, x2, y2, paint)
    }

    private fun ink(color: Long, width: Float = 0f) {
        paint.color = color.toInt()
        paint.style = if (width == 0f) Paint.Style.FILL else Paint.Style.STROKE
        paint.strokeWidth = width
    }

    private inline fun shape(build: Path.() -> Unit) { scratch.rewind(); scratch.build() }

    private fun track(build: Path.() -> Unit) = PathMeasure(Path().apply(build), false)
    private fun cycle(t: Float) = t % 1f
    private fun gradient(top: Float, bottom: Float, a: Long, b: Long) =
        LinearGradient(0f, top, 0f, bottom, a.toInt(), b.toInt(), Shader.TileMode.CLAMP)

    private fun horizontalShade(edge: Long, light: Long, shadow: Long) =
        LinearGradient(-13f, 0f, 13f, 0f, intArrayOf(edge.toInt(), light.toInt(), shadow.toInt()),
            floatArrayOf(0f, .40f, 1f), Shader.TileMode.CLAMP)

    private fun blend(from: Long, to: Long, t: Float): Long {
        fun channel(shift: Int) = (((from shr shift) and 255) * (1f - t) + ((to shr shift) and 255) * t).toLong()
        return 0xff000000L or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
    }
}
