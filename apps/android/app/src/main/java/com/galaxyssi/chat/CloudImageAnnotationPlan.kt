package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class CloudImageMark(
    val left: Float, val top: Float, val right: Float, val bottom: Float,
    val verdict: String, val note: String, val correction: String = ""
)

internal data class CloudImageAnnotationPlan(val imageIndex: Int, val marks: List<CloudImageMark>) {
    companion object {
        const val TOOL = "image_annotate"
        const val MAX_MARKS = 24

        fun parse(arguments: JSONObject, imageCount: Int): CloudImageAnnotationPlan {
            val rawIndex = arguments.getDouble("image_index")
            require(rawIndex.isFinite() && rawIndex == rawIndex.toInt().toDouble()) { "image_index must be an integer" }
            val index = rawIndex.toInt()
            require(index in 0 until imageCount) { "image_index must identify an image in this user turn" }
            val items = arguments.getJSONArray("marks")
            require(items.length() in 1..MAX_MARKS) { "Use 1 to $MAX_MARKS marks per image" }
            val marks = (0 until items.length()).map { position ->
                val item = items.getJSONObject(position)
                fun coordinate(key: String): Float {
                    val value = item.getDouble(key)
                    require(value.isFinite() && value in 0.0..1.0) { "$key must be between 0 and 1" }
                    return value.toFloat()
                }
                val mark = CloudImageMark(coordinate("left"), coordinate("top"), coordinate("right"),
                    coordinate("bottom"), item.getString("verdict"), item.getString("note").trim(),
                    item.optString("correction").trim())
                require(mark.left < mark.right && mark.top < mark.bottom) { "Mark rectangle must have positive area" }
                require(mark.verdict in setOf("correct", "incorrect", "uncertain", "note")) { "Unknown verdict" }
                require(mark.note.length in 1..160 && mark.note.none { it.isISOControl() && it != '\n' }) {
                    "Each mark needs a readable correction or explanation of at most 160 characters"
                }
                require(mark.correction.length <= 40 && mark.correction.none(Char::isISOControl)) {
                    "correction must be a short single-line replacement answer, at most 40 characters"
                }
                require(mark.verdict != "incorrect" || mark.correction.isNotBlank()) {
                    "An incorrect answer needs a short correction, for example 4 or x = 2; put explanations in note"
                }
                mark
            }
            return CloudImageAnnotationPlan(index, marks)
        }

        fun instruction(imageCount: Int): String = if (imageCount == 0) "" else """
            This turn contains $imageCount attached images, indexed from 0. You can call image_annotate to
            put small grading ticks, crosses and short corrections directly on the original image.
            When the user requests homework grading ON the image or an annotated result, inspect the
            supplied image, solve each readable question, and call image_annotate before claiming that
            an annotated image exists. Use normalized coordinates matching the upright input image.
            Do not search for a replacement worksheet. Never infer unreadable handwriting or mark an
            uncertain answer wrong: use uncertain and explain what must be checked. Each call replaces
            the current marks for that image, so include its complete intended set of marks.
            The rectangles only locate each written answer; they are NEVER drawn. Keep them tight around
            the answer, with nearby whitespace for a small tick or cross. For incorrect answers, correction
            must contain only the short replacement answer (e.g. 4), not a sentence. Otherwise use an empty
            correction. Put explanations in note, which is NOT drawn. Do not add frames, numbering,
            a legend, a summary page, a second image or a before/after comparison.
            After success, briefly summarize the corrections. GalaxySSI appends the generated image
            card itself. Do not invent image links, emit drawing code, or duplicate the generated card.
            This tool annotates the source image; it is not a generative image model.
        """.trimIndent()

        fun definition(): JSONObject {
            val coordinates = JSONObject().put("type", "number").put("minimum", 0).put("maximum", 1)
            val mark = JSONObject().put("type", "object").put("additionalProperties", false)
                .put("required", JSONArray(listOf("left", "top", "right", "bottom", "verdict", "note", "correction")))
                .put("properties", JSONObject()
                    .put("left", coordinates).put("top", coordinates).put("right", coordinates).put("bottom", coordinates)
                    .put("verdict", JSONObject().put("type", "string")
                        .put("enum", JSONArray(listOf("correct", "incorrect", "uncertain", "note"))))
                    .put("note", JSONObject().put("type", "string").put("minLength", 1).put("maxLength", 160)
                        .put("description", "Reasoning for the reply only; never drawn onto the image."))
                    .put("correction", JSONObject().put("type", "string").put("maxLength", 40)
                        .put("description", "Short replacement answer for incorrect verdicts; empty otherwise.")))
            return JSONObject().put("type", "function").put("function", JSONObject()
                .put("name", TOOL)
                .put("description", "Grade the original image with small ticks/crosses and short corrections, without boxes or extra pages. " +
                    "Returns a saved local image; the app displays it automatically. Coordinates are fractions of " +
                    "the upright image width/height, not pixels. Does not generate a replacement image.")
                .put("parameters", JSONObject().put("type", "object").put("additionalProperties", false)
                    .put("required", JSONArray(listOf("image_index", "marks")))
                    .put("properties", JSONObject()
                        .put("image_index", JSONObject().put("type", "integer").put("minimum", 0))
                        .put("marks", JSONObject().put("type", "array").put("minItems", 1)
                            .put("maxItems", MAX_MARKS).put("items", mark)))))
        }
    }
}
