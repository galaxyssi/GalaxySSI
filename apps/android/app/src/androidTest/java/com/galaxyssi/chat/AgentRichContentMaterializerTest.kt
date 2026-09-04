package com.galaxyssi.chat

import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AgentRichContentMaterializerTest {
    @Test
    fun replacesInlineImageWithDurablePrivateFile() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val bytes = "galaxyssi-rich-output".toByteArray()
        val raw = AgentRichContentCodec.encode(
            listOf(
                AgentRichBlock(
                    id = "image-1",
                    type = AgentRichBlockType.IMAGE,
                    title = "result.png",
                    mimeType = "image/png",
                    dataB64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                )
            )
        )

        val materialized = AgentRichContentCodec.decode(
            AgentRichContentMaterializer.materialize(context, raw)
        ).single()

        assertTrue(materialized.dataB64.isBlank())
        assertTrue(materialized.uri.startsWith("content:"))
        assertEquals(bytes.size.toString(), materialized.metadata["size_bytes"])
        val stored = context.contentResolver.openInputStream(android.net.Uri.parse(materialized.uri))
            ?.use { it.readBytes() }
        assertArrayEquals(bytes, stored)
    }
}
