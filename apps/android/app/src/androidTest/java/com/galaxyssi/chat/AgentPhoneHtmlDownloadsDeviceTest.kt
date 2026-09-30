package com.galaxyssi.chat

import android.content.ContextWrapper
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class AgentPhoneHtmlDownloadsDeviceTest {
    @Test fun archiveUserRequestedPublicPageWithoutModelCall() {
        val address = InstrumentationRegistry.getArguments().getString("original_archive_url").orEmpty()
        assumeTrue(address.startsWith("https://"))
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val turn = "original-archive-${UUID.randomUUID()}"
        val prepared = AgentPhonePublicHtmlAttachment.prepareAll(context, turn, address).getOrThrow().single()
        val suffix = prepared.attachment.displayName.removeSuffix(".html") + "-原貌.html"
        val root = File(context.filesDir, "agent-public-html-original")
        val directory = root.listFiles().orEmpty().single { directory ->
            val metadata = File(directory, "metadata.json")
            metadata.isFile && org.json.JSONObject(metadata.readText()).optString("name") == suffix
        }
        val manager = androidx.work.WorkManager.getInstance(context)
        val deadline = android.os.SystemClock.elapsedRealtime() + 210_000
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            val info = manager.getWorkInfosForUniqueWork("original-page-${directory.name}").get().lastOrNull()
            if (info?.state == androidx.work.WorkInfo.State.SUCCEEDED) {
                println("ORIGINAL_PAGE_SAVED Download/GalaxySSI/$suffix")
                return
            }
            assertNotEquals(androidx.work.WorkInfo.State.FAILED, info?.state)
            Thread.sleep(500)
        }
        fail("Original archive did not finish")
    }

    @Test fun exportedHtmlIsExactDeduplicatedAndRestoredAfterDeletion() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val turn = "html-download-test-${UUID.randomUUID()}"
        val root = File(base.filesDir, "agent-public-html/$turn")
        val context = object : ContextWrapper(base) {
            override fun getFilesDir(): File = root
        }
        val document = AgentPhonePublicHtmlDocument("https://example.com/$turn", turn, "Article body.")
        val fileName = UUID.nameUUIDFromBytes("$turn\u001f${document.url}".toByteArray()).toString() + ".html"
        val preferences = context.getSharedPreferences("phone_html_downloads", 0)
        val resolver = context.contentResolver
        fun saved() = Uri.parse(requireNotNull(preferences.getString(fileName, null)))
        try {
            val first = AgentPhonePublicHtmlAttachment.stageDocument(context, turn, document, saveRequested = true)
            assertTrue(first.savedToDownloads)
            val uri = saved()
            assertEquals(first.readableHtml, resolver.openInputStream(uri)!!.bufferedReader().use { it.readText() })
            assertTrue(AgentPhonePublicHtmlAttachment.instruction(first).contains("Downloads/GalaxySSI"))
            assertTrue(AgentPhonePublicHtmlAttachment.stageDocument(context, turn, document, saveRequested = true).savedToDownloads)
            assertEquals(uri, saved())
            resolver.delete(uri, null, null)
            assertTrue(AgentPhonePublicHtmlAttachment.stageDocument(context, turn, document, saveRequested = true).savedToDownloads)
            assertEquals(first.readableHtml, resolver.openInputStream(saved())!!.bufferedReader().use { it.readText() })
        } finally {
            preferences.getString(fileName, null)?.let { resolver.delete(Uri.parse(it), null, null) }
            preferences.edit().remove(fileName).commit()
            root.deleteRecursively()
        }
    }
}
