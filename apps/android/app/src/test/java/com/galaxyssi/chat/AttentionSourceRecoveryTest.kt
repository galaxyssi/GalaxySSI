package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import java.time.Instant

class AttentionSourceRecoveryTest {
    @Test fun researchUsesDatedThirtyDayWindowWithoutChangingBreakingNews() {
        val now = Instant.parse("2026-10-25T12:00:00Z").toEpochMilli()
        val xml = """<rss><channel><item><title>Cell communication</title><link>https://example.org/biology</link>
            <pubDate>Thu, 15 Oct 2026 16:50:00 -0400</pubDate></item></channel></rss>"""
        assertTrue(ProactiveAttentionFeedPolicy.parse(xml, "ai_models", now).isEmpty())
        val parsed = ProactiveAttentionFeedPolicy.parse(xml, "protein_life_sciences", now, 30).single()
        assertEquals(Instant.parse("2026-10-15T20:50:00Z").toEpochMilli(), parsed.publishedAt)
        assertEquals(30, ProactiveAttentionSourceCatalog.maxAgeDays("protein_life_sciences"))
        assertEquals(7, ProactiveAttentionSourceCatalog.maxAgeDays("ai_models"))
    }

    @Test fun publishersWithUsTimezoneNamesHaveValidDates() {
        assertEquals(Instant.parse("2026-10-24T13:01:22Z").toEpochMilli(),
            ProactiveAttentionFeedPolicy.date("Sat, 24 Oct 2026 09:01:22 EDT"))
    }

    @Test fun specialistSourcesDoNotRelyOnGenericTechnologyOrSpaceNews() {
        val bio = ProactiveAttentionFeedSources.originals(AttentionTopic("protein_life_sciences", "", ""))
        assertTrue(bio.any { it.contains("plosbiology") }); assertTrue(bio.any { it.contains("elifesciences") })
        assertTrue(bio.any { it.contains("nature.com/nbt") }); assertFalse(bio.any { it.contains("nasa") })
        val agents = ProactiveAttentionFeedSources.originals(AttentionTopic("agent_frontiers", "", ""))
        assertTrue(agents.first().contains("langchain"))
        assertTrue(ProactiveAttentionSourceCatalog.dedicated(bio.first(), "protein_life_sciences"))
        assertFalse(ProactiveAttentionSourceCatalog.dedicated("https://www.ithome.com/rss/", "protein_life_sciences"))
    }

    @Test fun searchesUseSpecificTopicsNotUiLabels() {
        assertEquals("AI agents multi-agent memory", ProactiveAttentionSourceCatalog.searchQuery(
            AttentionTopic("agent_frontiers", "Display label", "Scope")))
        assertEquals("custom topic scope", ProactiveAttentionSourceCatalog.searchQuery(
            AttentionTopic("custom", "Display label", "custom topic scope")))
    }

    @Test fun technicalNamesDoNotOutweighChineseProse() {
        AttentionArticlePolicy.validateTranslation("OpenAI released GPT-5", "OpenAI 发布 GPT-5")
        AttentionArticlePolicy.validateTranslation("John Smith", "John Smith")
        assertFalse(AttentionTranslationRecovery.technicalLabel("This Is Untranslated Text"))
        assertFalse(AttentionArticlePolicy.chinese("This is an untranslated English sentence about AI and biology. 中文"))
    }

    @Test fun numericFailureRetriesSmallerSentencesAndKeepsAllInformation() = runBlocking {
        val source = "The first experiment used 12 samples. The second experiment used 24 samples."
        val result = AttentionTranslationRecovery.convert(source) { part ->
            when {
                part == source -> "实验使用了 12 个样本。"
                part.contains("12") -> "第一次实验使用了 12 个样本。"
                else -> "第二次实验使用了 24 个样本。"
            }
        }
        assertTrue(result.contains("12")); assertTrue(result.contains("24"))
        AttentionArticlePolicy.validateTranslation(source, result)
    }

    @Test fun persistentWrongNumbersAndUntranslatedSentencesStillFail() = runBlocking {
        assertTrue(runCatching { AttentionTranslationRecovery.convert("Experiment used 24 samples.") { "实验用了 12 个样本。" } }.isFailure)
        assertTrue(runCatching { AttentionTranslationRecovery.convert("This is untranslated prose.") { it } }.isFailure)
    }

    @Test fun translatorCannotAlterAuthorNamesOrTechnicalIdentifiers() = runBlocking {
        for (source in listOf("Bruno KA", "Raznahan A", "Tronson NC", "GPT-5", "de Jonge XAKJ",
            "O\u2019Mahony SM", "Carrero J-J", "eLife 10:e70817.", "\u00a9 2026, Debarnot and Four\u00e9")) {
            assertEquals(source, AttentionTranslationRecovery.convert(source) { "mutated name" })
        }
        assertTrue(runCatching { AttentionTranslationRecovery.convert("The Important Research Results") { "mutated name" } }.isFailure)
        assertFalse(AttentionTranslationRecovery.technicalLabel("\u00a9 2026, This article is distributed under the terms of a license."))
    }

    @Test fun offlineFailureAndCancellationDoNotTriggerTranslationRetryStorm() = runBlocking {
        var attempts = 0
        val failure = runCatching { AttentionTranslationRecovery.convert("First sentence. Second sentence.") {
            attempts++; throw CancellationException("cancelled")
        } }.exceptionOrNull()
        assertTrue(failure is CancellationException); assertEquals(1, attempts)
    }

    @Test fun fullWebLinksAreNotSentToTranslationOrAltered() = runBlocking {
        for (url in listOf("https://doi.org/10.1016/S0140-6736(20)31561-0", "https://example.org/p?q=" + "a".repeat(1400))) {
            assertEquals(url, AttentionTranslationRecovery.convert(url) { error("A URL must not be translated") })
            AttentionArticlePolicy.validateTranslation(url, url)
        }
        assertFalse(AttentionTranslationRecovery.technicalLabel("See https://example.org for more details."))
        assertFalse(AttentionTranslationRecovery.technicalLabel("javascript:alert('hello world')"))
    }

    @Test fun sentenceSplittingPreservesVersionsAndUnicode() {
        val text = "Version 2.1.3 used 12 samples. Another experiment \ud83e\uddec used 24 samples."
        assertEquals(text.replace(Regex("\\s+"), ""), AttentionTranslationRecovery.sentences(text, 32)
            .joinToString("").replace(Regex("\\s+"), ""))
    }
}
