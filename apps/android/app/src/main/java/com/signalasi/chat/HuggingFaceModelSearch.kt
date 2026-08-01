package com.signalasi.chat

import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.util.Locale
import java.util.concurrent.TimeUnit

data class HuggingFaceModelResult(
    val repositoryId: String,
    val displayName: String,
    val author: String,
    val downloads: Long,
    val likes: Int,
    val gated: Boolean,
    val lastModified: String
)

data class HuggingFaceGgufArtifact(
    val repositoryId: String,
    val fileName: String,
    val sizeBytes: Long,
    val sha256: String,
    val quantization: String,
    val parameterCountBillions: Double,
    val visionCapable: Boolean
) {
    fun toRuntimeProfile(): LocalModelRuntimeProfile {
        require(sizeBytes > 0L)
        require(sha256.matches(Regex("[a-f0-9]{64}")))
        val shape = estimatedShape(parameterCountBillions)
        val safeRepository = repositoryId.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]+"), "-").trim('-')
        return LocalModelRuntimeProfile(
            id = "hub-${safeRepository.take(48)}-${sha256.take(12)}",
            displayName = fileName.removeSuffix(".gguf").replace('_', ' '),
            expectedModelFileBytes = sizeBytes,
            layerCount = shape.layers,
            keyValueHeadCount = shape.keyValueHeads,
            headDimension = shape.headDimension,
            defaultContextTokens = 4_096,
            maximumContextTokens = 32_768,
            quantizationLabel = quantization,
            repositoryId = repositoryId,
            fileName = fileName,
            sha256 = sha256,
            parameterCountBillions = parameterCountBillions,
            defaultNoThink = repositoryId.contains("qwen3", ignoreCase = true) &&
                !repositoryId.contains("qwen3.5", ignoreCase = true),
            visionCapable = visionCapable,
            sourceTrust = LocalModelSourceTrust.HUB_VERIFIED
        )
    }

    private data class EstimatedShape(val layers: Int, val keyValueHeads: Int, val headDimension: Int)

    private fun estimatedShape(parameters: Double): EstimatedShape = when {
        parameters <= 1.5 -> EstimatedShape(26, 4, 128)
        parameters <= 5.0 -> EstimatedShape(36, 8, 128)
        parameters <= 10.0 -> EstimatedShape(36, 8, 128)
        parameters <= 14.0 -> EstimatedShape(48, 8, 128)
        else -> EstimatedShape(64, 8, 128)
    }
}

class HuggingFaceModelSearch(
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .callTimeout(45, TimeUnit.SECONDS)
        .build(),
    private val baseUrl: String = "https://huggingface.co/"
) {
    fun search(query: String, limit: Int = 20): List<HuggingFaceModelResult> {
        val clean = query.trim()
        require(clean.length in 2..120) { "Enter at least two characters" }
        val url = baseUrl.toHttpUrl().newBuilder()
            .addPathSegments("api/models")
            .addQueryParameter("search", clean)
            .addQueryParameter("filter", "gguf")
            .addQueryParameter("sort", "downloads")
            .addQueryParameter("direction", "-1")
            .addQueryParameter("limit", limit.coerceIn(1, 50).toString())
            .build()
        val body = execute(url.toString())
        return parseSearchResults(body)
            .filterNot(HuggingFaceModelResult::gated)
            .take(limit.coerceIn(1, 50))
    }

    fun artifacts(repositoryId: String): List<HuggingFaceGgufArtifact> {
        require(repositoryId.matches(Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"))) { "Invalid model repository" }
        val url = baseUrl.toHttpUrl().newBuilder()
            .addPathSegments("api/models")
            .addPathSegments(repositoryId)
            .addQueryParameter("blobs", "true")
            .build()
        return parseArtifacts(repositoryId, execute(url.toString()))
    }

    private fun execute(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("User-Agent", "SignalASI-Android")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("Model Hub returned HTTP ${response.code}")
            return response.body?.string() ?: throw IOException("Model Hub returned an empty response")
        }
    }

    companion object {
        private val splitGguf = Regex("-\\d{5}-of-\\d{5}\\.gguf$", RegexOption.IGNORE_CASE)
        private val quantizationPattern = Regex(
            "(?:^|[-_.])(IQ\\d(?:_[A-Z0-9]+)?|Q\\d(?:_[A-Z0-9]+)+)(?:[-_.]|$)",
            RegexOption.IGNORE_CASE
        )
        private val parameterPattern = Regex("(?:^|[-_/])(\\d+(?:\\.\\d+)?)B(?:[-_/]|$)", RegexOption.IGNORE_CASE)

        internal fun parseSearchResults(encoded: String): List<HuggingFaceModelResult> {
            val array = JSONArray(encoded)
            return buildList {
                for (index in 0 until array.length()) {
                    val value = array.optJSONObject(index) ?: continue
                    val repositoryId = value.optString("id").ifBlank { value.optString("modelId") }
                    if (!repositoryId.contains('/')) continue
                    val tags = value.optJSONArray("tags")
                    val hasGguf = tags?.let { tagArray ->
                        (0 until tagArray.length()).any { tagArray.optString(it).equals("gguf", true) }
                    } ?: false
                    if (!hasGguf) continue
                    val gatedValue = value.opt("gated")
                    val gated = when (gatedValue) {
                        is Boolean -> gatedValue
                        is String -> gatedValue.isNotBlank() && !gatedValue.equals("false", true)
                        else -> false
                    }
                    add(HuggingFaceModelResult(
                        repositoryId = repositoryId,
                        displayName = repositoryId.substringAfter('/'),
                        author = repositoryId.substringBefore('/'),
                        downloads = value.optLong("downloads").coerceAtLeast(0L),
                        likes = value.optInt("likes").coerceAtLeast(0),
                        gated = gated,
                        lastModified = value.optString("lastModified")
                    ))
                }
            }
        }

        internal fun parseArtifacts(repositoryId: String, encoded: String): List<HuggingFaceGgufArtifact> {
            val root = JSONObject(encoded)
            val tags = root.optJSONArray("tags")
            val vision = tags?.let { tagArray ->
                (0 until tagArray.length()).map(tagArray::optString).any { tag ->
                    tag.equals("image-text-to-text", true) || tag.equals("vision", true)
                }
            } ?: false
            val siblings = root.optJSONArray("siblings") ?: return emptyList()
            return buildList {
                for (index in 0 until siblings.length()) {
                    val file = siblings.optJSONObject(index) ?: continue
                    val fileName = file.optString("rfilename")
                    if (!fileName.endsWith(".gguf", true) || splitGguf.containsMatchIn(fileName)) continue
                    val lfs = file.optJSONObject("lfs") ?: continue
                    val sha = lfs.optString("sha256").lowercase(Locale.ROOT)
                    val size = lfs.optLong("size", file.optLong("size"))
                    val quantization = quantizationPattern.find(fileName)?.groupValues?.getOrNull(1)?.uppercase(Locale.ROOT)
                        ?: continue
                    if (size <= 0L || !sha.matches(Regex("[a-f0-9]{64}"))) continue
                    add(HuggingFaceGgufArtifact(
                        repositoryId = repositoryId,
                        fileName = fileName,
                        sizeBytes = size,
                        sha256 = sha,
                        quantization = quantization,
                        parameterCountBillions = inferParameterCount("$repositoryId/$fileName"),
                        visionCapable = vision
                    ))
                }
            }.sortedWith(compareBy<HuggingFaceGgufArtifact> {
                if (it.quantization.equals("Q4_K_M", true)) 0 else 1
            }.thenBy(HuggingFaceGgufArtifact::sizeBytes))
        }

        private fun inferParameterCount(repositoryId: String): Double =
            parameterPattern.find(repositoryId)?.groupValues?.getOrNull(1)?.toDoubleOrNull() ?: 8.0
    }
}
