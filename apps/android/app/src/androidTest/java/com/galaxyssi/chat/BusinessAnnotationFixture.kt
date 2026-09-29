package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.net.Uri
import java.io.File
import org.json.JSONObject

/** Deterministic synthetic strokes, not a substitute for real handwritten-photo acceptance. */
internal object BusinessAnnotationFixture {
    fun image(directory: File, case: JSONObject, index: Int): AgentInputAttachment {
        val fixture = case.getJSONArray("fixtures").getJSONObject(index)
        val bitmap = Bitmap.createBitmap(1200, 1600, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(25, 30, 35); textSize = 42f }
        canvas.drawText(fixture.getString("title"), 60f, 90f, paint)
        paint.textSize = 30f
        canvas.drawText(fixture.getString("code"), 60f, 155f, paint)
        canvas.drawText("合成测试记录；最后一项的原答案被涂抹", 60f, 210f, paint)
        val rows = fixture.getJSONArray("rows")
        for (i in 0 until rows.length()) {
            val row = rows.getJSONObject(i)
            val baseline = 355f + i * 230f
            paint.style = Paint.Style.FILL
            paint.color = Color.rgb(25, 30, 35)
            paint.textSize = 50f
            canvas.drawText(row.getString("label"), 85f, baseline, paint)
            val answer = row.getString("answer")
            if (fixture.optBoolean("handwritten") || answer == "?") {
                answer.forEachIndexed { digitIndex, digit ->
                    stroke(canvas, paint, digit, 610f + digitIndex * 72, baseline - 75)
                }
            } else canvas.drawText(answer, 610f, baseline, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1f
            paint.color = Color.LTGRAY
            canvas.drawLine(60f, baseline + 110, 1140f, baseline + 110, paint)
        }
        paint.style = Paint.Style.FILL
        paint.color = Color.DKGRAY
        paint.textSize = 25f
        canvas.drawText("合成笔迹测试，不代表真实人类手写识别能力。", 60f, 1510f, paint)
        val file = File(directory, case.getString("id") + "-input-$index.png")
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        return AgentInputAttachment(file.nameWithoutExtension, Uri.fromFile(file), file.name, "image/png", file.length())
    }

    private fun stroke(canvas: Canvas, paint: Paint, digit: Char, x: Float, y: Float) {
        val points = when (digit) {
            '0' -> listOf(28 to 2, 9 to 7, 3 to 32, 7 to 68, 29 to 78, 47 to 61, 49 to 23, 28 to 2)
            '1' -> listOf(8 to 20, 30 to 1, 27 to 78)
            '2' -> listOf(5 to 14, 20 to 1, 42 to 5, 50 to 23, 4 to 78, 51 to 77)
            '3' -> listOf(4 to 5, 45 to 3, 26 to 36, 45 to 44, 48 to 65, 28 to 79, 4 to 69)
            '4' -> listOf(34 to 1, 3 to 49, 51 to 50, 39 to 50, 40 to 78, 40 to 1)
            '5' -> listOf(48 to 3, 9 to 5, 5 to 37, 33 to 34, 48 to 47, 47 to 67, 26 to 79, 4 to 69)
            '6' -> listOf(46 to 3, 25 to 8, 6 to 36, 5 to 65, 24 to 78, 45 to 65, 46 to 44, 28 to 35, 6 to 43)
            '7' -> listOf(2 to 5, 50 to 2, 20 to 79)
            '8' -> listOf(27 to 39, 7 to 19, 14 to 3, 36 to 2, 47 to 17, 27 to 39, 4 to 60, 13 to 78, 38 to 77, 49 to 59, 27 to 39)
            '9' -> listOf(45 to 38, 23 to 43, 5 to 29, 9 to 8, 28 to 2, 46 to 15, 45 to 49, 30 to 78)
            else -> listOf(3 to 4, 45 to 65, 6 to 60, 49 to 12, 11 to 78, 41 to 2, 4 to 45, 48 to 50)
        }
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeJoin = Paint.Join.ROUND
        paint.strokeWidth = 5f
        paint.color = Color.rgb(32, 52, 78)
        val path = Path()
        points.forEachIndexed { index, point ->
            if (index == 0) path.moveTo(x + point.first, y + point.second)
            else path.lineTo(x + point.first, y + point.second)
        }
        canvas.drawPath(path, paint)
    }
}
