package com.galaxyssi.chat

internal data class AttentionInboxPage(
    val items: List<GlobalProactiveInboxItem> = emptyList(),
    val index: Int = 0,
    val total: Int = 0,
    val pages: Int = 1
)

internal object ProactiveAttentionPaging {
    const val PAGE_SIZE = 20

    fun page(items: List<GlobalProactiveInboxItem>, filter: AttentionFeedFilter,
        savedKeys: Set<String>, requestedPage: Int): AttentionInboxPage {
        val matching = items.filter { ProactiveAttentionPolicy.matches(it, filter, savedKeys) }
        val pages = if (matching.isEmpty()) 1 else (matching.size - 1) / PAGE_SIZE + 1
        val index = requestedPage.coerceIn(0, pages - 1)
        return AttentionInboxPage(matching.drop(index * PAGE_SIZE).take(PAGE_SIZE), index, matching.size, pages)
    }
}
