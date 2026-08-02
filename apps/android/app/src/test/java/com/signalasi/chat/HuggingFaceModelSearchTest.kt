package com.signalasi.chat

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HuggingFaceModelSearchTest {
    @Test
    fun searchUsesGgufFilterAndOmitsGatedRepositories() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(200).setBody(
                """
                [
                  {"id":"Qwen/Qwen3-8B-GGUF","tags":["gguf"],"downloads":42,"likes":7,"gated":false},
                  {"id":"private/Model-GGUF","tags":["gguf"],"downloads":99,"likes":1,"gated":"manual"}
                ]
                """.trimIndent()
            ))
            val search = HuggingFaceModelSearch(
                client = OkHttpClient(),
                baseUrl = server.url("/").toString()
            )

            val results = search.search("Qwen3", limit = 10)

            assertEquals(listOf("Qwen/Qwen3-8B-GGUF"), results.map(HuggingFaceModelResult::repositoryId))
            val request = requireNotNull(server.takeRequest())
            assertEquals("/api/models", request.requestUrl?.encodedPath)
            assertEquals("Qwen3", request.requestUrl?.queryParameter("search"))
            assertEquals("gguf", request.requestUrl?.queryParameter("filter"))
        }
    }

    @Test
    fun artifactsKeepOnlySingleVerifiedGgufFilesAndPreferQ4Km() {
        val artifacts = HuggingFaceModelSearch.parseArtifacts(
            repositoryId = "SignalASI/Test-8B-GGUF",
            encoded = """
                {
                  "tags": ["gguf"],
                  "siblings": [
                    {"rfilename":"Test-8B-Q8_0.gguf","lfs":{"size":900,"sha256":"${"a".repeat(64)}"}},
                    {"rfilename":"Test-8B-Q4_K_M.gguf","lfs":{"size":500,"sha256":"${"b".repeat(64)}"}},
                    {"rfilename":"Test-8B-Q4_K_M-00001-of-00002.gguf","lfs":{"size":300,"sha256":"${"c".repeat(64)}"}},
                    {"rfilename":"README.md","size":10},
                    {"rfilename":"unsafe-Q4_K_M.gguf","lfs":{"size":500}}
                  ]
                }
            """.trimIndent()
        )

        assertEquals(listOf("Test-8B-Q4_K_M.gguf", "Test-8B-Q8_0.gguf"), artifacts.map { it.fileName })
        assertEquals(8.0, artifacts.first().parameterCountBillions, 0.0)
        assertEquals("Q4_K_M", artifacts.first().quantization)
    }

    @Test
    fun verifiedArtifactBecomesDownloadableAppPrivateRuntimeProfile() {
        val profile = HuggingFaceGgufArtifact(
            repositoryId = "Qwen/Qwen3-4B-GGUF",
            fileName = "Qwen3-4B-Q4_K_M.gguf",
            sizeBytes = 1234L,
            sha256 = "d".repeat(64),
            quantization = "Q4_K_M",
            parameterCountBillions = 4.0,
            visionCapable = false
        ).toRuntimeProfile()

        assertTrue(profile.downloadable)
        assertTrue(profile.defaultNoThink)
        assertEquals(LocalModelSourceTrust.HUB_VERIFIED, profile.sourceTrust)
        assertTrue(profile.sourceUrls(preferChinaMirror = true).first().startsWith("https://hf-mirror.com/"))
        assertFalse(profile.visionCapable)
    }

    @Test
    fun unsafeRepositoryOrArtifactPathCannotBecomeDownloadable() {
        val valid = HuggingFaceGgufArtifact(
            repositoryId = "SignalASI/Test-1B-GGUF",
            fileName = "quantized/Test 1B-Q4_K_M.gguf",
            sizeBytes = 1234L,
            sha256 = "e".repeat(64),
            quantization = "Q4_K_M",
            parameterCountBillions = 1.0,
            visionCapable = false
        ).toRuntimeProfile()

        assertTrue(valid.downloadable)
        assertTrue(valid.sourceUrls(false).first().contains("Test%201B-Q4_K_M.gguf"))
        assertFalse(valid.copy(repositoryId = "SignalASI/Test/Unexpected").downloadable)
        assertFalse(valid.copy(fileName = "../Test-1B-Q4_K_M.gguf").downloadable)
    }
}
