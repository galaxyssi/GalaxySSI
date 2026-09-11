package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

internal data class CloudImageMark(
    val left: Float, val top: Float, val right: Float, val bottom: Float,
    val verdict: String, val note: String
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
                    coordinate("bottom"), item.getString("verdict"), item.getString("note").trim())
                require(mark.left < mark.right && mark.top < mark.bottom) { "Mark rectangle must have positive area" }
                require(mark.verdict in setOf("correct", "incorrect", "uncertain", "note")) { "Unknown verdict" }
                require(mark.note.length in 1..160 && mark.note.none { it.isISOControl() && it != '\n' }) {
                    "Each mark needs a readable correction or explanation of at most 160 characters"
                }
                mark
            }
            return CloudImageAnnotationPlan(index, marks)
        }

        fun instruction(imageCount: Int): String = if (imageCount == 0) "" else """
            This turn contains $imageCount attached images, indexed from 0. You can call image_annotate to
            draw verified corrections, highlights and comments on these images on the user's phone.
            When the user requests homework grading ON the image or an annotated result, inspect the
            supplied image, solve each readable question, and call image_annotate before claiming that
            an annotated image exists. Use normalized coordinates matching the upright input image.
            Do not search for a replacement worksheet. Never infer unreadable handwriting or mark an
            uncertain answer wrong: use uncertain and explain what must be checked. Each call replaces
            the current marks for that image, so include its complete intended set of marks.
            After success, briefly summarize the corrections. GalaxySSI appends the generated image
            card itself. Do not invent image links, emit drawing code, or duplicate the generated card.
            This tool annotates the source image; it is not a generative image model.
        """.trimIndent()

        fun definition(): JSONObject {
            val coordinates = JSONObject().put("type", "number").put("minimum", 0).put("maximum", 1)
            val mark = JSONObject().put("type", "object").put("additionalProperties", false)
                .put("required", JSONArray(listOf("left", "top", "right", "bottom", "verdict", "note")))
                .put("properties", JSONObject()
                    .put("left", coordinates).put("top", coordinates).put("right", coordinates).put("bottom", coordinates)
                    .put("verdict", JSONObject().put("type", "string")
                        .put("enum", JSONArray(listOf("correct", "incorrect", "uncertain", "note"))))
                    .put("note", JSONObject().put("type", "string").put("minLength", 1).put("maxLength", 160)))
            return JSONObject().put("type", "function").put("function", JSONObject()
                .put("name", TOOL)
                .put("description", "Annotate an attached image with answer verdicts, numbered boxes and corrections. " +
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
