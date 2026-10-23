package com.galaxyssi.chat

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class AttentionArticlePolicyTest {
    private val english = "Researchers developed a new battery that stores energy safely and improves efficiency. " .repeat(5)
    private val chinese = "研究人员开发了一种新型电池，可以安全地储存能源并提高效率。".repeat(8)
    private fun page(body: String, type: String = "text/html") = AgentWebIntelligenceFetched("https://example.com/news", type, body.toByteArray())
    private fun html(text: String) = "<html><head><title>New battery</title></head><body><article><p>$text</p></article></body></html>"
    private fun message(key: String = "") = GlobalProactiveMessage(id = "attention-feed:a",
        sourceEventId = "research:attention-research:ai_models:feed:a", sourceConversationId = "",
        target = GlobalProactiveTarget.NEW_CONVERSATION, title = "标题", content = chinese, topic = "AI", urgent = false,
        status = GlobalProactiveMessageStatus.DELIVERED, newsArticleKey = key)

    @Test fun titleOnlyNewsIsHiddenFromListAndNotifications() {
        val pending = message()
        assertTrue(GlobalProactiveInboxPolicy.project(listOf(pending), emptyList()).isEmpty())
        assertFalse(GlobalProactiveNotificationPolicy.enabledFor(pending, GlobalAgentSettings()))
        assertNull(GlobalProactiveNotificationPolicy.candidate(listOf(pending)))
    }
    @Test fun readyNewsKeepsIdentityAndProvider() {
        val ready = message("a").copy(newsTranslationProvider = AttentionMlKitTranslator.PROVIDER)
        val item = GlobalProactiveInboxPolicy.project(listOf(ready), emptyList()).single()
        assertEquals("a", item.newsArticleKey)
        assertEquals(AttentionMlKitTranslator.PROVIDER, item.titleTranslationProvider)
        assertNotNull(GlobalProactiveNotificationPolicy.candidate(listOf(ready)))
    }
    @Test fun unrelatedPrivateInsightsRemainVisible() {
        val private = message().copy(id = "private", sourceEventId = "private-event")
        assertEquals(1, GlobalProactiveInboxPolicy.project(listOf(private), emptyList()).size)
    }
    @Test fun oldModelSummaryWithoutArticleIsHidden() {
        assertFalse(AttentionArticlePolicy.visible(message().copy(id = "legacy-summary")))
    }
    @Test fun notificationBatchDoesNotCountHiddenNews() {
        assertEquals(setOf("attention-feed:ready"), GlobalProactiveNotificationPolicy.candidate(listOf(message(),
            message("ready").copy(id = "attention-feed:ready")))!!.messageIds)
    }
    @Test fun actualArticleIsExtractedWithoutNavigation() {
        val article = AttentionArticlePolicy.extract(page(html(english).replace("<article>", "<nav>Menu Home</nav><article>")))
        assertTrue(article.content.contains("Researchers")); assertFalse(article.content.contains("Menu Home"))
    }
    @Test fun emptyPageIsRejected() { rejected { AttentionArticlePolicy.extract(page(html(""))) } }
    @Test fun titleAndDescriptionAreNotAFullArticle() {
        rejected { AttentionArticlePolicy.extract(page("<html><title>Title</title><meta name='description' content='summary'></html>")) }
    }
    @Test fun jsonEndpointIsNotPublishedAsBody() { rejected { AttentionArticlePolicy.extract(page(english, "application/json")) } }
    @Test fun challengeIsRejectedDespiteLongPage() {
        rejected { AttentionArticlePolicy.extract(page(html("Verify you are human. $english"))) }
    }
    @Test fun scriptShellIsRejected() {
        rejected { AttentionArticlePolicy.extract(page("<html><body><div id='root'></div><script>app()</script></body></html>")) }
    }
    @Test fun paywallExcerptIsRejected() {
        rejected { AttentionArticlePolicy.extract(page(html(english).replace("<head>",
            "<head><script type='application/ld+json'>{\"isAccessibleForFree\":false}</script>"))) }
    }
    @Test fun truncatedArticlesAreNotCalledComplete() {
        rejected { AttentionArticlePolicy.extract(page(html("article text ".repeat(25_000)))) }
    }
    @Test fun paragraphSplittingKeepsBeginningMiddleAndEnd() {
        val text = "FIRST " + "a sentence. ".repeat(400) + " LAST"
        val pieces = AttentionArticlePolicy.parts(text)
        assertTrue(pieces.size > 2); assertTrue(pieces.all { it.length <= 1200 })
        assertEquals(text.replace(Regex("\\s+"), ""), pieces.joinToString("").replace(Regex("\\s+"), ""))
    }
    @Test fun longUnbrokenContentAndSurrogatesAreNotDropped() {
        val text = "\ud83d\ude80".repeat(1300)
        assertEquals(text, AttentionArticlePolicy.parts(text, 33).joinToString(""))
        assertTrue(AttentionArticlePolicy.parts(text, 33).none { Character.isHighSurrogate(it.last()) })
    }
    @Test fun paragraphOrderIsStable() {
        assertEquals(listOf("one", "two", "three"), AttentionArticlePolicy.parts("one\n\ntwo\n\nthree"))
    }
    @Test fun chineseArticleDoesNotUseTranslation() = runBlocking {
        val result = AttentionArticleTranslation { error("No translation needed") }.run("电池研究", chinese)
        assertEquals(chinese, result.body); assertEquals("", result.provider)
    }
    @Test fun englishArticlePublishesOnlyTranslatedParagraphs() = runBlocking {
        val result = AttentionArticleTranslation { if (it == "New battery") "新型电池" else chinese }.run("New battery", english)
        assertEquals("新型电池", result.title); assertEquals(chinese, result.body)
        assertFalse(result.body.contains("Researchers")); assertEquals(AttentionMlKitTranslator.PROVIDER, result.provider)
    }
    @Test fun lateTranslationFailureDoesNotReturnPartialArticle() = runBlocking {
        var calls = 0
        val result = runCatching { AttentionArticleTranslation { calls++; if (calls >= 3) error("offline") else chinese }
            .run("Title", english.repeat(3) + "\n\n" + english.repeat(3)) }
        assertTrue(result.isFailure); assertEquals(3, calls)
    }
    @Test fun cancellationPropagates() = runBlocking {
        assertTrue(runCatching { AttentionArticleTranslation { throw CancellationException() }.run("Title", english) }
            .exceptionOrNull() is CancellationException)
    }
    @Test fun modelEchoIsRejected() { rejected { AttentionArticlePolicy.validateTranslation(english, english) } }
    @Test fun changedNumbersAreRejected() { rejected { AttentionArticlePolicy.validateTranslation("Version 2.1 with 20% reduction", "版本 3.1，降低 20%") } }
    @Test fun numericFormattingIsAccepted() { AttentionArticlePolicy.validateTranslation("Price 10,000 with 20% reduction", "价格 10000，降低 20％") }
    @Test fun translatedUnitsAndChineseNumeralsKeepTheirActualValues() {
        AttentionArticlePolicy.validateTranslation("6 billion people; 2 billion users; 20 million accounts; $1 million",
            "60亿人；二十亿用户；2000万个账户；100万美元")
        AttentionArticlePolicy.validateTranslation("6 steps and 2 choices", "六个步骤和两个选择")
    }
    @Test fun incorrectMagnitudeIsStillRejected() {
        rejected { AttentionArticlePolicy.validateTranslation("6 billion people", "6亿人") }
        rejected { AttentionArticlePolicy.validateTranslation("Price 1.2 million", "价格12万元") }
    }
    @Test fun multiPartVersionsMustNotBeRoundedOrCombined() {
        AttentionArticlePolicy.validateTranslation("Version 2.1.3", "版本 2.1.3")
        rejected { AttentionArticlePolicy.validateTranslation("Version 2.1.3", "版本 2.13") }
    }
    @Test fun dedicatedBodyExcludesLargerPageNavigationAndRelatedHeadlines() {
        val navigation = (1..40).joinToString("") { "<div><a href='/news/$it'>Other headline $it</a></div>" }
        val result = AttentionArticlePolicy.extract(page("<html><head><title>News</title></head><body>" +
            "<div>$navigation</div><div class='post_content' id='paragraph'><p>$english</p>" +
            "<div class='related-news'>$navigation</div></div><div>$navigation</div></body></html>"))
        assertEquals(english.trim(), result.content)
    }
    @Test fun nestedArticleBodyExcludesHeaderAndOtherSections() {
        val result = AttentionArticlePolicy.extract(page("<html><body><main><div>Settings</div><article>" +
            "<header class='post-header'><h1>Article title</h1><span>2026</span><span>20 min</span></header>" +
            "<div class='post-body'><p>$english</p></div></article><div class='recommendations'>Other titles</div></main></body></html>"))
        assertEquals("Article title", result.title)
        assertEquals(english.trim(), result.content)
    }
    @Test fun headlineListingIsNotAnArticle() {
        rejected { AttentionArticlePolicy.extract(page("<html><body><main>" +
            (1..30).joinToString("") { "<a href='/news/$it'><h2>News headline $it</h2></a>" } + "</main></body></html>")) }
    }
    @Test fun multipleArticleCardsAreNotJoinedIntoOneBody() {
        rejected { AttentionArticlePolicy.extract(page("<html><body><main><article><p>$english</p></article>" +
            "<article><p>$english</p></article></main></body></html>")) }
    }
    @Test fun bemArticleBodyIsNotConfusedWithSiblingRecommendationCards() {
        val result = AttentionArticlePolicy.extract(page("<html><head><title>Research</title></head><body><main>" +
            "<section class='post__content'><p>$english</p><p>$english</p></section>" +
            (1..5).joinToString("") { "<article class='post-card'><h2>Related $it</h2><p>$english</p></article>" } +
            "</main></body></html>"))
        assertFalse(result.content.contains("Related"))
        assertEquals(2, Regex("Researchers").findAll(result.content).count() / 5)
    }
    @Test fun noSidebarLayoutDoesNotDeleteTheEntireDocumentOrItsArticle() {
        val result = AttentionArticlePolicy.extract(page("<html><head><title>Research</title></head>" +
            "<body class='single-post no-sidebar'><div class='layout-without-sidebar'>" +
            "<section class='post__content'><p>$english</p></section></div>" +
            "<div class='sidebar'><p>Unrelated promotion $english</p></div></body></html>"))
        assertEquals(english.trim(), result.content)
    }
    @Test fun spelledOutNumbersCanBecomeDigits() { AttentionArticlePolicy.validateTranslation("Eight states", "8 个州") }
    @Test fun japaneseAndKoreanAreNotMistakenForChinese() {
        assertFalse(AttentionArticlePolicy.chinese("研究結果について説明する"))
        assertFalse(AttentionArticlePolicy.chinese("研究 한국어"))
    }
    @Test fun standaloneDatesAndPunctuationDoNotRequireALanguageModel() = runBlocking {
        val text = "2026/10/23 18:53:10\n\n$chinese\n\n，"
        assertEquals(text, AttentionArticleTranslation { error("No linguistic content needs translation") }.run("新闻", text).body)
    }
    @Test fun plainTextComparisonsAreNotHtml() {
        AttentionArticlePolicy.validateTranslation("Latency < 20 ms", "延迟 < 20 毫秒")
    }
    @Test fun shortBylinesStayWithTheirArticleAndAllTextSurvives() {
        val body = "A Writer\n\n2026/10/23 18:53:10\n\n$english\n\n$english\n\n$english\n\nA Writer"
        val chunks = AttentionArticlePolicy.translationChunks(body)
        assertTrue(chunks.size < AttentionArticlePolicy.parts(body).size)
        assertTrue(chunks.all { it.length >= 120 })
        assertEquals(body.replace(Regex("\\s+"), ""), chunks.joinToString("").replace(Regex("\\s+"), ""))
    }
    @Test fun markupIsRejected() { rejected { AttentionArticlePolicy.validateTranslation("Title", "<html>标题</html>") } }
    private fun rejected(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }
}
