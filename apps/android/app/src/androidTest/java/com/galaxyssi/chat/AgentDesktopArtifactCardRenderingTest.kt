package com.galaxyssi.chat

import android.Manifest
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.os.Environment
import android.provider.MediaStore
import android.util.Base64
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.ScrollView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.security.MessageDigest

@RunWith(AndroidJUnit4::class)
class AgentDesktopArtifactCardRenderingTest {
    @Test
    fun thumbnailDimensionsFollowImageOrientation() {
        assertEquals(
            AgentImageThumbnailSize(
                AGENT_IMAGE_THUMBNAIL_WIDTH_DP,
                AGENT_IMAGE_THUMBNAIL_HEIGHT_DP
            ),
            agentImageThumbnailSize(sourceWidth = 900, sourceHeight = 1_440)
        )
        assertEquals(
            AgentImageThumbnailSize(
                AGENT_IMAGE_THUMBNAIL_HEIGHT_DP,
                AGENT_IMAGE_THUMBNAIL_WIDTH_DP
            ),
            agentImageThumbnailSize(sourceWidth = 1_440, sourceHeight = 900)
        )
    }

    @Test
    fun rendersCodexStyleImageAndDownloadableFileCards() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            instrumentation.uiAutomation.grantRuntimePermission(
                context.packageName,
                Manifest.permission.POST_NOTIFICATIONS
            )
        }
        AgentDesktopArtifactStore.clear(context)
        val png = Base64.decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
            Base64.DEFAULT
        )
        val items = listOf(
            StoredFixture("preview.png", "image/png", png, AgentRichBlockType.IMAGE),
            StoredFixture("report.txt", "text/plain", "GalaxySSI result\nVerified".toByteArray(), AgentRichBlockType.FILE),
            StoredFixture(
                "SnakeGame.apk",
                "application/vnd.android.package-archive",
                "debug-apk".toByteArray(),
                AgentRichBlockType.FILE
            )
        )
        val blocks = items.mapIndexed { index, fixture ->
            val artifactUri = "galaxyssi-artifact://showcase/outputs/${fixture.name}"
            store(context, "showcase-$index", artifactUri, fixture)
            AgentRichBlock(
                id = "showcase-$index",
                type = fixture.type,
                title = fixture.name,
                uri = artifactUri,
                mimeType = fixture.mimeType,
                metadata = mapOf(
                    "transport" to "encrypted-fragmented",
                    "size" to "${fixture.bytes.size} B"
                )
            )
        }
        val activity = instrumentation.startActivitySync(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ) as MainActivity
        lateinit var content: View
        instrumentation.runOnMainSync {
            content = AgentRichContentView(activity, {}, {}, { _, _ -> }).create(
                AgentTranscriptEntry(
                    id = "desktop-artifacts",
                    role = AgentTranscriptRole.ASSISTANT,
                    text = "Generated artifacts",
                    timestampMillis = System.currentTimeMillis(),
                    richOutputJson = AgentRichContentCodec.encode(blocks)
                )
            )
            activity.setContentView(ScrollView(activity).apply {
                setPadding(32, 32, 32, 32)
                addView(
                    content,
                    ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT
                    )
                )
            })
        }
        instrumentation.waitForIdleSync()
        SystemClock.sleep(700)
        instrumentation.runOnMainSync {
            val preview = findImage(content, "preview.png")
            assertNotNull(preview)
            val density = context.resources.displayMetrics.density
            assertEquals((AGENT_IMAGE_THUMBNAIL_WIDTH_DP * density).toInt(), preview!!.width)
            assertEquals((AGENT_IMAGE_THUMBNAIL_HEIGHT_DP * density).toInt(), preview.height)
            assertEquals(ImageView.ScaleType.CENTER_CROP, preview.scaleType)
        }
        val screenshot = instrumentation.uiAutomation.takeScreenshot()
        val screenshotUri = context.contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "galaxyssi-artifact-card-showcase.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    Environment.DIRECTORY_PICTURES + "/GalaxySSI-tests"
                )
            }
        ) ?: error("Could not create screenshot")
        context.contentResolver.openOutputStream(screenshotUri)?.use {
            screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        } ?: error("Could not write screenshot")
        instrumentation.runOnMainSync { activity.finish() }
    }

    private fun store(
        context: android.content.Context,
        taskId: String,
        artifactUri: String,
        fixture: StoredFixture
    ) {
        val digest = sha256(fixture.bytes)
        val artifactId = sha256("$artifactUri\u0000$digest".toByteArray())
        AgentDesktopArtifactStore.ingest(
            context,
            JSONObject()
                .put("type", "artifact_chunk")
                .put("artifact_id", artifactId)
                .put("artifact_uri", artifactUri)
                .put("task_id", taskId)
                .put("name", fixture.name)
                .put("mime_type", fixture.mimeType)
                .put("size_bytes", fixture.bytes.size)
                .put("sha256", digest)
                .put("original_size_bytes", fixture.bytes.size)
                .put("original_sha256", digest)
                .put("chunk_index", 0)
                .put("chunk_count", 1)
                .put("chunk_size_bytes", fixture.bytes.size)
                .put("chunk_sha256", digest)
                .put("data_b64", Base64.encodeToString(fixture.bytes, Base64.NO_WRAP))
        )
    }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun findImage(view: View, description: String): ImageView? {
        if (view is ImageView && view.contentDescription?.toString() == description) return view
        if (view !is ViewGroup) return null
        for (index in 0 until view.childCount) {
            findImage(view.getChildAt(index), description)?.let { return it }
        }
        return null
    }

    private data class StoredFixture(
        val name: String,
        val mimeType: String,
        val bytes: ByteArray,
        val type: AgentRichBlockType
    )
}
