package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentResponseSectionsTest {
    @Test
    fun keepsShortOrdinaryRepliesUnsectioned() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(block("answer", AgentRichBlockType.TEXT, "Done."))
        )

        assertFalse(layout.collapsible)
        assertEquals(AgentResponseSectionKind.FINAL_ANSWER, layout.sections.single().kind)
    }

    @Test
    fun groupsExplicitSectionsAndExpandsOnlyTheFinalAnswerByDefault() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(
                block("plan", AgentRichBlockType.TEXT, "Inspect and verify.", "plan"),
                block("tool", AgentRichBlockType.TOOL, "Read project state."),
                block("final", AgentRichBlockType.TEXT, "The project is running.", "final"),
                block("source", AgentRichBlockType.CITATION, "status.json")
            )
        )

        assertTrue(layout.collapsible)
        assertEquals(
            listOf(
                AgentResponseSectionKind.PLAN,
                AgentResponseSectionKind.EXECUTION_LOG,
                AgentResponseSectionKind.FINAL_ANSWER,
                AgentResponseSectionKind.EVIDENCE
            ),
            layout.sections.map(AgentResponseSection::kind)
        )
        assertEquals(
            listOf(false, false, true, false),
            layout.sections.map(AgentResponseSection::expandedByDefault)
        )
    }

    @Test
    fun recognizesSectionHeadingsWithoutRenderingDuplicateHeadingBlocks() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(
                block("heading-plan", AgentRichBlockType.HEADING, "Plan"),
                block("plan-body", AgentRichBlockType.LIST, "1. Inspect"),
                block("heading-result", AgentRichBlockType.HEADING, "Final answer"),
                block("result-body", AgentRichBlockType.TEXT, "Verified.")
            )
        )

        assertTrue(layout.collapsible)
        assertEquals(listOf("plan-body"), layout.sections[0].blocks.map(AgentRichBlock::id))
        assertEquals(listOf("result-body"), layout.sections[1].blocks.map(AgentRichBlock::id))
    }

    @Test
    fun keepsDeliveredArtifactsInTheFinalAnswerUnlessMarkedAsEvidence() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(
                block("image", AgentRichBlockType.IMAGE, "result.png"),
                block("evidence", AgentRichBlockType.IMAGE, "source.png", evidence = true)
            )
        )

        assertEquals(
            listOf("image"),
            layout.sections.single { it.kind == AgentResponseSectionKind.FINAL_ANSWER }
                .blocks.map(AgentRichBlock::id)
        )
        assertEquals(
            listOf("evidence"),
            layout.sections.single { it.kind == AgentResponseSectionKind.EVIDENCE }
                .blocks.map(AgentRichBlock::id)
        )
    }

    @Test
    fun makesLongPlainRepliesCollapsible() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(block("long", AgentRichBlockType.TEXT, "x".repeat(1_300)))
        )

        assertTrue(layout.collapsible)
        assertTrue(layout.sections.single().expandedByDefault)
    }

    @Test
    fun keepsInteractiveApprovalBlocksInTheExpandedFinalSection() {
        val layout = AgentResponseSectionOrganizer.organize(
            listOf(
                block("heading-plan", AgentRichBlockType.HEADING, "Plan"),
                block("plan", AgentRichBlockType.TEXT, "Prepare the change."),
                block("approval", AgentRichBlockType.APPROVAL, "Approve the protected action.")
            )
        )

        val finalSection = layout.sections.single {
            it.kind == AgentResponseSectionKind.FINAL_ANSWER
        }
        assertEquals(listOf("approval"), finalSection.blocks.map(AgentRichBlock::id))
        assertTrue(finalSection.expandedByDefault)
    }

    private fun block(
        id: String,
        type: AgentRichBlockType,
        text: String,
        section: String = "",
        evidence: Boolean = false
    ) = AgentRichBlock(
        id = id,
        type = type,
        text = text,
        metadata = buildMap {
            if (section.isNotBlank()) put("section", section)
            if (evidence) put("evidence", "true")
        }
    )
}
