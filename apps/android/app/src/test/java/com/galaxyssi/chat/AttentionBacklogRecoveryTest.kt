package com.galaxyssi.chat

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AttentionBacklogRecoveryTest {
    private class Progress : AttentionTranslationProgress {
        val rows = mutableMapOf<String, String>()
        override fun read(source: String) = rows[source]
        override fun save(source: String, translated: String) { rows[source] = translated }
    }

    @Test fun translatedPhysicalUnitsKeepTheirActualDimensionsAndMagnitude() {
        for ((source, result) in listOf(
            "106 MW and 280 MW of capacity" to "容量为106兆瓦和280兆瓦",
            "106 megawatts" to "功率106兆瓦", "1 MW" to "功率1000千瓦",
            "48 kHz" to "频率48千赫兹", "2400 MHz" to "频率2.4吉赫兹",
            "512 MB" to "容量512兆字节", "2 GB" to "容量2吉字节")) {
            AttentionArticlePolicy.validateTranslation(source, result)
        }
        for ((source, result) in listOf("106 MW" to "功率106瓦", "106 MW" to "频率106兆赫兹",
            "106 MW" to "功率280兆瓦", "512 MB" to "容量512吉字节")) {
            assertTrue(runCatching { AttentionArticlePolicy.validateTranslation(source, result) }.isFailure)
        }
    }

    @Test fun incompleteTranslationResumesValidatedChunksButCannotPublishPartialBody() = runBlocking {
        val progress = Progress()
        val first = "The first experiment used 12 samples. " + "The study examines protein structures. ".repeat(12)
        val second = "The second experiment used 24 samples. " + "The study examines cell structures. ".repeat(12)
        val document = AttentionArticleDocument(listOf(AttentionArticleBlock("paragraph", first), AttentionArticleBlock("paragraph", second)))
        val source = mapOf("Experiment report" to "实验报告", first.trim() to "第一次实验使用12个样本，研究了蛋白质的结构。",
            second.trim() to "第二次实验使用24个样本，研究了细胞的结构。")
        val called = mutableListOf<String>()
        assertTrue(runCatching { AttentionArticleTranslation(progress) {
            called += it
            if (it.contains("24")) error("offline")
            source.getValue(it)
        }.run("Experiment report", document) }.isFailure)
        assertTrue(first.trim() in progress.rows)
        called.clear()
        val result = AttentionArticleTranslation(progress) { called += it; source.getValue(it) }.run("Experiment report", document)
        assertEquals(listOf(second.trim()), called)
        assertTrue(result.body.contains("12")); assertTrue(result.body.contains("24"))
        assertEquals(2, result.document!!.blocks.size)
    }

    @Test fun staleOrCorruptTranslationCacheCannotBypassValidation() = runBlocking {
        val progress = Progress().apply { rows["Experiment used 24 samples."] = "实验使用12个样本。" }
        var calls = 0
        val result = AttentionTranslationRecovery.convert("Experiment used 24 samples.", progress) { calls++; "实验使用24个样本。" }
        assertEquals(1, calls); assertEquals("实验使用24个样本。", result)
        assertEquals(result, progress.rows.getValue("Experiment used 24 samples."))
    }

    @Test fun contactAddressesAreMetadataNotUntranslatedProse() = runBlocking {
        val source = "Crusoe: media@crusoe.ai"
        assertTrue(AttentionTranslationRecovery.technicalLabel(source))
        assertEquals(source, AttentionTranslationRecovery.convert(source) { "Crusoe：Media@crusoe.ai" })
        assertFalse(AttentionTranslationRecovery.technicalLabel("Contact us to learn about this new service."))
    }

    @Test fun arxivAbstractExcludesVersionHistoryDownloadControlsAndSocialIcons() {
        val prose = "This study investigates protein and RNA structure prediction using a reproducible computational method. ".repeat(5)
        val html = """<html><head><title>[2610.30668] Research</title></head><body><main>
            <h1 class="title"><span class="descriptor">Title:</span> Protein and RNA structure study</h1>
            <blockquote class="abstract"><span class="descriptor">Abstract:</span>$prose</blockquote>
            <div>[v1] Thu, 22 Oct 2026 03:32:07 UTC (6,220 KB)</div><ul><li>TeX Source</li><li>SciX</li></ul>
            <img src="/reddit.png" alt="Reddit"><p>&lt; prev | next &gt;</p></main></body></html>"""
        val source = AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched("https://arxiv.org/abs/2610.30668",
            "text/html", html.toByteArray()))
        assertEquals("Protein and RNA structure study", source.article.title)
        assertTrue(source.document.body.contains(prose.trim()))
        assertFalse(source.document.body.contains("6,220"))
        assertFalse(source.document.body.contains("TeX Source"))
        assertFalse(source.document.blocks.any { it.kind == "image" })
        assertTrue(source.document.blocks.any { it.kind == "heading" && it.text == "Abstract" })
    }

    @Test fun foreignNicknameDoesNotRetranslateSurroundingChineseFacts() = runBlocking {
        val text = "其中，一般意见和建议约8833条，有关疫苗接种证明的咨询约3661条，关于借用吉祥物麻衣娜酱（マイナちゃん）人偶服的咨询约117条。"
        val calls = mutableListOf<String>()
        val result = AttentionTranslationRecovery.convert(text) {
            calls += it; assertEquals("マイナちゃん", it); "麻衣娜酱"
        }
        assertEquals(listOf("マイナちゃん"), calls)
        assertEquals(text.replace("マイナちゃん", "麻衣娜酱"), result)
        assertTrue(AttentionQuotedTranslation.ranges("これは日本語の文章です（マイナちゃん）。").isEmpty())
    }

    @Test fun shortChineseParagraphsUseTheirExplicitBodyNotRelatedHeadlineLists() {
        val paragraphs = listOf("今日市场出现波动，研究人员正在持续观察数据变化，并核对公开发布的信息。",
            "多个行业出现不同表现，报告分别列出了具体情况，也说明了这些数据的统计范围。",
            "分析指出，这些短期数据不能替代长期趋势，需要结合更多资料进行独立核实。",
            "本次公开说明还列出了相关来源，读者可以查看原文，了解完整的背景与研究局限。",
            "报道并未对后续结果作出保证，具体情况仍应以正式发布的信息和后续更新为准。",
            "相关部门表示，将在完成信息核实后继续公布进展，并对已有说明作出必要补充。")
        assertTrue(paragraphs.all { it.length < 80 })
        val html = "<html><head><title>市场数据报道</title></head><body><div class='left_zw'>" +
            paragraphs.joinToString("") { "<p>$it</p>" } + "</div><div>" + (1..20).joinToString("") {
                "<article><a href='/other/$it'>其他新闻标题 $it</a></article>"
            } + "</div></body></html>"
        val source = AttentionArticlePolicy.extractStructured(AgentWebIntelligenceFetched("https://www.chinanews.com.cn/cj/news.shtml", "text/html", html.toByteArray()))
        assertTrue(source.document.body.contains(paragraphs.first()))
        assertFalse(source.document.body.contains("其他新闻标题"))
    }
}
