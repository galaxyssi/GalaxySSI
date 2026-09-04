package com.galaxyssi.chat

import java.util.Locale

enum class AgentResponseSectionKind {
    PLAN,
    EXECUTION_LOG,
    FINAL_ANSWER,
    EVIDENCE
}

data class AgentResponseSection(
    val kind: AgentResponseSectionKind,
    val blocks: List<AgentRichBlock>,
    val expandedByDefault: Boolean
)

data class AgentResponseSectionLayout(
    val collapsible: Boolean,
    val sections: List<AgentResponseSection>
)

object AgentResponseSectionOrganizer {
    private const val LONG_RESPONSE_CHARACTERS = 1_200
    private const val LONG_RESPONSE_BLOCKS = 6

    private val orderedKinds = listOf(
        AgentResponseSectionKind.PLAN,
        AgentResponseSectionKind.EXECUTION_LOG,
        AgentResponseSectionKind.FINAL_ANSWER,
        AgentResponseSectionKind.EVIDENCE
    )

    fun organize(blocks: List<AgentRichBlock>): AgentResponseSectionLayout {
        if (blocks.isEmpty()) return AgentResponseSectionLayout(false, emptyList())
        val grouped = linkedMapOf<AgentResponseSectionKind, MutableList<AgentRichBlock>>()
        var activeKind: AgentResponseSectionKind? = null
        var structured = false

        blocks.forEach { block ->
            headingKind(block)?.let { heading ->
                activeKind = heading
                structured = true
                return@forEach
            }
            val explicit = explicitKind(block)
            if (explicit != null) structured = true
            val kind = explicit ?: typeKind(block) ?: activeKind ?: AgentResponseSectionKind.FINAL_ANSWER
            grouped.getOrPut(kind, ::mutableListOf) += block
        }

        val sections = orderedKinds.mapNotNull { kind ->
            grouped[kind]?.takeIf { it.isNotEmpty() }?.let { sectionBlocks ->
                AgentResponseSection(
                    kind = kind,
                    blocks = sectionBlocks,
                    expandedByDefault = kind == AgentResponseSectionKind.FINAL_ANSWER
                )
            }
        }.let { ordered ->
            if (ordered.none { it.expandedByDefault } && ordered.isNotEmpty()) {
                ordered.mapIndexed { index, section ->
                    if (index == 0) section.copy(expandedByDefault = true) else section
                }
            } else {
                ordered
            }
        }
        val contentSize = blocks.sumOf(::contentCharacters)
        val longResponse = contentSize >= LONG_RESPONSE_CHARACTERS ||
            blocks.size >= LONG_RESPONSE_BLOCKS
        return AgentResponseSectionLayout(
            collapsible = sections.isNotEmpty() && (longResponse || structured),
            sections = sections
        )
    }

    private fun explicitKind(block: AgentRichBlock): AgentResponseSectionKind? {
        val value = sequenceOf("section", "response_section", "role")
            .mapNotNull(block.metadata::get)
            .firstOrNull(String::isNotBlank)
            ?: return null
        return parseKind(value)
    }

    private fun headingKind(block: AgentRichBlock): AgentResponseSectionKind? {
        if (block.type != AgentRichBlockType.HEADING) return null
        return parseKind(block.text.ifBlank { block.title })
    }

    private fun typeKind(block: AgentRichBlock): AgentResponseSectionKind? = when (block.type) {
        AgentRichBlockType.STATUS,
        AgentRichBlockType.PROGRESS,
        AgentRichBlockType.TOOL,
        AgentRichBlockType.TIMELINE -> AgentResponseSectionKind.EXECUTION_LOG
        AgentRichBlockType.CITATION -> AgentResponseSectionKind.EVIDENCE
        AgentRichBlockType.ACTIONS,
        AgentRichBlockType.APPROVAL,
        AgentRichBlockType.FORM -> AgentResponseSectionKind.FINAL_ANSWER
        else -> if (block.metadata["evidence"] == "true") {
            AgentResponseSectionKind.EVIDENCE
        } else {
            null
        }
    }

    private fun parseKind(value: String): AgentResponseSectionKind? {
        val normalized = value
            .trim()
            .lowercase(Locale.ROOT)
            .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
            .trim()
        return when (normalized) {
            "plan", "approach", "steps",
            "\u8ba1\u5212", "\u65b9\u6848", "\u6267\u884c\u8ba1\u5212" ->
                AgentResponseSectionKind.PLAN
            "log", "execution log", "tool log", "activity", "progress",
            "\u65e5\u5fd7", "\u6267\u884c\u65e5\u5fd7", "\u5de5\u5177\u65e5\u5fd7",
            "\u6267\u884c\u8fc7\u7a0b" -> AgentResponseSectionKind.EXECUTION_LOG
            "final", "final answer", "answer", "result", "summary",
            "\u6700\u7ec8\u7b54\u6848", "\u7b54\u6848", "\u7ed3\u679c", "\u603b\u7ed3" ->
                AgentResponseSectionKind.FINAL_ANSWER
            "evidence", "source", "sources", "citation", "citations", "references",
            "\u8bc1\u636e", "\u6765\u6e90", "\u5f15\u7528", "\u53c2\u8003" ->
                AgentResponseSectionKind.EVIDENCE
            else -> null
        }
    }

    private fun contentCharacters(block: AgentRichBlock): Int =
        block.title.length +
            block.text.length +
            block.fallbackText.length +
            block.rows.sumOf { row -> row.sumOf(String::length) }
}
