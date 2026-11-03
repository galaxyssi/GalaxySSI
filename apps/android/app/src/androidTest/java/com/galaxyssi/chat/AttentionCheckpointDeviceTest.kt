package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttentionCheckpointDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val prose = "A protein participates in molecular processes and cell signaling. ".repeat(8)
    private fun source(title: String = "Protein research") = AttentionArticleSource(
        AgentPublicArticle(title, "", "", prose, emptyList(), emptyList(), "article"),
        AttentionArticleDocument(listOf(AttentionArticleBlock("paragraph", prose),
            AttentionArticleBlock("image", "Cell", "https://example.org/cell.png", 600, 900),
            AttentionArticleBlock("caption", "Figure 1"))))
    private fun enqueue(store: AttentionArticleStore, id: String) = store.enqueue(
        AttentionFeedArticle(id, "biology", "Protein research", "", "https://example.org/$id", "Example", 1, 2), "Biology")

    @Test fun sourceAndValidatedProgressSurviveReopeningWithoutPublishingPartialText() = isolated { name ->
        var store = AttentionArticleStore(context, name)
        enqueue(store, "one")
        store.checkpoint("one", source(), 1000)
        store.translationProgress("one").save("Protein research", "蛋白质研究")
        assertNull(store.body("one")); assertNull(store.presentation("one", true))
        AttentionArticleStore.closeTest(context, name)
        store = AttentionArticleStore(context, name)
        assertEquals(source().document, store.extracted("one", 1001)!!.document)
        assertEquals("蛋白质研究", store.translationProgress("one").read("Protein research"))
        assertNull(store.translationProgress("one").read("Changed text"))
        assertNull(store.extracted("one", 1000 + 86_400_001L))
    }

    @Test fun changedSourceInvalidatesOldChunksAndSuccessfulBodyClearsOnlyItsCheckpoint() = isolated { name ->
        val store = AttentionArticleStore(context, name)
        for (id in listOf("one", "two")) {
            enqueue(store, id); store.checkpoint(id, source(), 1000)
            store.translationProgress(id).save("Protein research", "蛋白质研究")
        }
        store.checkpoint("one", source(), 2000)
        assertNotNull(store.translationProgress("one").read("Protein research"))
        store.checkpoint("one", source("A changed discovery"), 3000)
        assertNull(store.translationProgress("one").read("Protein research"))
        val body = "蛋白质参与细胞内的生化反应，也参与细胞信号的传递。".repeat(8)
        store.ready("one", AttentionChineseArticle("蛋白质研究", body, "fixture"))
        assertNull(store.extracted("one", 3001))
        assertEquals(body, store.body("one"))
        assertNotNull(store.extracted("two", 3001))
        assertNotNull(store.translationProgress("two").read("Protein research"))
    }

    private fun isolated(test: (String) -> Unit) {
        val name = "article-checkpoint-${UUID.randomUUID()}.db"
        try { test(name) } finally { AttentionArticleStore.closeTest(context, name); context.deleteDatabase(name) }
    }
}
