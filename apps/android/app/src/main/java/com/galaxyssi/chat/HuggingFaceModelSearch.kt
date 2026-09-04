package com.galaxyssi.chat

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
    val lastModified: String,
    val source: LocalModelHubSource = LocalModelHubSource.HUGGING_FACE,
    val visionCapable: Boolean = false
)

data class HuggingFaceGgufArtifact(
    val repositoryId: String,
    val fileName: String,
    val sizeBytes: Long,
    val sha256: String,
    val quantization: String,
    val parameterCountBillions: Double,
    val visionCapable: Boolean,
    val source: LocalModelHubSource = LocalModelHubSource.HUGGING_FACE
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
            sourceTrust = LocalModelSourceTrust.HUB_VERIFIED,
            sourceHub = source
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
    private val baseUrl: String = "https://huggingface.co/",
    private val modelScopeBaseUrl: String = "https://modelscope.cn/",
    private val preferChinaSource: Boolean = false
) {
    fun search(query: String, limit: Int = 20): List<HuggingFaceModelResult> {
        val clean = query.trim()
        require(clean.length in 2..120) { "Enter at least two characters" }
        val boundedLimit = limit.coerceIn(1, 50)
        return firstAvailable(sourceOrder()) { source ->
            searchSource(source, clean, boundedLimit)
                .filterNot(HuggingFaceModelResult::gated)
                .take(boundedLimit)
        }
    }

    fun artifacts(model: HuggingFaceModelResult): List<HuggingFaceGgufArtifact> {
        val repositoryId = model.repositoryId
        require(repositoryId.matches(Regex("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"))) { "Invalid model repository" }
        val order = listOf(model.source) + sourceOrder().filterNot { it == model.source }
        return firstAvailable(order) { source ->
            artifactsSource(source, repositoryId, model.visionCapable)
        }
    }

    fun artifacts(repositoryId: String): List<HuggingFaceGgufArtifact> = artifacts(
        HuggingFaceModelResult(
            repositoryId = repositoryId,
            displayName = repositoryId.substringAfter('/'),
            author = repositoryId.substringBefore('/'),
            downloads = 0L,
            likes = 0,
            gated = false,
            lastModified = ""
        )
    )

    private fun sourceOrder(): List<LocalModelHubSource> = if (preferChinaSource) {
        listOf(LocalModelHubSource.MODELSCOPE, LocalModelHubSource.HUGGING_FACE)
    } else {
        listOf(LocalModelHubSource.HUGGING_FACE, LocalModelHubSource.MODELSCOPE)
    }

    private fun searchSource(
        source: LocalModelHubSource,
        query: String,
        limit: Int
    ): List<HuggingFaceModelResult> = when (source) {
        LocalModelHubSource.HUGGING_FACE -> {
            val url = baseUrl.toHttpUrl().newBuilder()
                .addPathSegments("api/models")
                .addQueryParameter("search", query)
                .addQueryParameter("filter", "gguf")
                .addQueryParameter("sort", "downloads")
                .addQueryParameter("direction", "-1")
                .addQueryParameter("limit", limit.toString())
                .build()
            parseSearchResults(execute(url.toString()))
        }

        LocalModelHubSource.MODELSCOPE -> {
            val modelScopeQuery = if (query.contains("gguf", ignoreCase = true)) query else "$query GGUF"
            val url = modelScopeBaseUrl.toHttpUrl().newBuilder()
                .addPathSegments("openapi/v1/models")
                .addQueryParameter("search", modelScopeQuery)
                .addQueryParameter("sort", "downloads")
                .addQueryParameter("page_number", "1")
                .addQueryParameter("page_size", limit.toString())
                .build()
            parseModelScopeSearchResults(execute(url.toString()))
        }
    }

    private fun artifactsSource(
        source: LocalModelHubSource,
        repositoryId: String,
        visionCapable: Boolean
    ): List<HuggingFaceGgufArtifact> = when (source) {
        LocalModelHubSource.HUGGING_FACE -> {
            val url = baseUrl.toHttpUrl().newBuilder()
                .addPathSegments("api/models")
                .addPathSegments(repositoryId)
                .addQueryParameter("blobs", "true")
                .build()
            parseArtifacts(repositoryId, execute(url.toString()))
        }

        LocalModelHubSource.MODELSCOPE -> {
            val url = modelScopeBaseUrl.toHttpUrl().newBuilder()
                .addPathSegments("api/v1/models")
                .addPathSegments(repositoryId)
                .addPathSegments("repo/files")
                .addQueryParameter("Revision", "master")
                .addQueryParameter("Recursive", "True")
                .build()
            parseModelScopeArtifacts(repositoryId, execute(url.toString()), visionCapable)
        }
    }

    private fun <T> firstAvailable(
        sources: List<LocalModelHubSource>,
        request: (LocalModelHubSource) -> List<T>
    ): List<T> {
        val failures = mutableListOf<String>()
        var receivedEmptyResponse = false
        sources.distinct().forEach { source ->
            runCatching { request(source) }
                .onSuccess { result ->
                    if (result.isNotEmpty()) return result
                    receivedEmptyResponse = true
                }
                .onFailure { error -> failures += "${source.displayName}: ${error.message.orEmpty()}" }
        }
        if (receivedEmptyResponse) return emptyList()
        throw IOException(failures.joinToString("; ").ifBlank { "No model hub is available" })
    }

    private fun execute(url: String): String {
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("User-Agent", "GalaxySSI-Android")
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
                        lastModified = value.optString("lastModified"),
                        source = LocalModelHubSource.HUGGING_FACE,
                        visionCapable = tags.containsAny("image-text-to-text", "vision")
                    ))
                }
            }
        }

        internal fun parseModelScopeSearchResults(encoded: String): List<HuggingFaceModelResult> {
            val root = JSONObject(encoded)
            val models = root.optJSONObject("data")?.optJSONArray("models")
                ?: root.optJSONObject("Data")?.optJSONArray("Models")
                ?: JSONArray()
            return buildList {
                for (index in 0 until models.length()) {
                    val value = models.optJSONObject(index) ?: continue
                    val repositoryId = value.optString("id")
                    if (!repositoryId.contains('/')) continue
                    val tags = value.optJSONArray("tags")
                    if (!tags.containsAny("gguf", "library:gguf", "custom_tag:gguf")) continue
                    add(HuggingFaceModelResult(
                        repositoryId = repositoryId,
                        displayName = value.optString("display_name").ifBlank { repositoryId.substringAfter('/') },
                        author = repositoryId.substringBefore('/'),
                        downloads = value.optLong("downloads").coerceAtLeast(0L),
                        likes = value.optInt("likes").coerceAtLeast(0),
                        gated = value.optBoolean("gated"),
                        lastModified = value.optString("last_modified"),
                        source = LocalModelHubSource.MODELSCOPE,
                        visionCapable = tags.containsAny("task:image-text-to-text", "vision")
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
                        visionCapable = vision,
                        source = LocalModelHubSource.HUGGING_FACE
                    ))
                }
            }.sortedWith(compareBy<HuggingFaceGgufArtifact> {
                if (it.quantization.equals("Q4_K_M", true)) 0 else 1
            }.thenBy(HuggingFaceGgufArtifact::sizeBytes))
        }

        internal fun parseModelScopeArtifacts(
            repositoryId: String,
            encoded: String,
            visionCapable: Boolean
        ): List<HuggingFaceGgufArtifact> {
            val root = JSONObject(encoded)
            val files = root.optJSONObject("Data")?.optJSONArray("Files")
                ?: root.optJSONObject("data")?.optJSONArray("files")
                ?: JSONArray()
            return buildList {
                for (index in 0 until files.length()) {
                    val file = files.optJSONObject(index) ?: continue
                    val fileName = file.optString("Path").ifBlank { file.optString("Name") }
                    if (!fileName.endsWith(".gguf", true) || splitGguf.containsMatchIn(fileName)) continue
                    val sha = file.optString("Sha256").lowercase(Locale.ROOT)
                    val size = file.optLong("Size")
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
                        visionCapable = visionCapable,
                        source = LocalModelHubSource.MODELSCOPE
                    ))
                }
            }.sortedWith(compareBy<HuggingFaceGgufArtifact> {
                if (it.quantization.equals("Q4_K_M", true)) 0 else 1
            }.thenBy(HuggingFaceGgufArtifact::sizeBytes))
        }

        private fun JSONArray?.containsAny(vararg expected: String): Boolean {
            if (this == null) return false
            return (0 until length()).any { index ->
                val tag = optString(index)
                expected.any { tag.equals(it, ignoreCase = true) }
            }
        }

        private fun inferParameterCount(repositoryId: String): Double =
            parameterPattern.find(repositoryId)?.groupValues?.getOrNull(1)?.toDoubleOrNull() ?: 8.0
    }
}
