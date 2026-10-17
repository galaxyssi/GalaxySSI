package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class AgentWorkspaceArtifactExportTest {
    @get:Rule val temporary = TemporaryFolder()
    private fun tools(policy: AgentWorkspaceFilePolicy = AgentWorkspaceFilePolicy()) =
        AgentWorkspaceFileTools(temporary.newFolder().toPath(), policy)

    private fun export(tools: AgentWorkspaceFileTools, path: String): Map<*, *> {
        val output = (tools.exportArtifact("test", path) as AgentWorkspaceFileResult.Success).value
        return (output["artifacts"] as List<*>).single() as Map<*, *>
    }

    @Test fun `text export is readable hash-bound and sufficient for artifact completion`() {
        val tools = tools()
        tools.writeText("test", "report.txt", "alpha=7\nbeta=5\n")
        val artifact = export(tools, "report.txt")
        assertEquals("alpha=7\nbeta=5\n", File(artifact["host_path"].toString()).readText())
        val inspection = artifact["openability"] as Map<*, *>
        assertEquals("verified", inspection["status"])
        assertEquals(artifact["sha256"], inspection["sha256"])
        val review = inspection["details"] as Map<*, *>
        assertEquals(true, review["text_complete"])
        assertEquals("alpha=7\nbeta=5\n", review["text"])
        val action = AgentAction("export", AgentActionKind.CALL_NATIVE_TOOL, "file", AgentRisk.MEDIUM,
            AgentActionStatus.COMPLETED, "Export", evidence = JSONObject().put("artifacts", listOf(artifact)).toString())
        assertTrue(AgentArtifactCompletionEvidence.missing(listOf(AgentArtifactRequirement("report.txt")), listOf(action)).isEmpty())
    }

    @Test fun `source edits do not change an earlier delivered snapshot`() {
        val tools = tools()
        tools.writeText("test", "report.csv", "value\n12\n")
        val first = export(tools, "report.csv")
        tools.writeText("test", "report.csv", "value\n15\n")
        val second = export(tools, "report.csv")
        assertNotEquals(first["sha256"], second["sha256"])
        assertEquals("value\n12\n", File(first["host_path"].toString()).readText())
        assertEquals("value\n15\n", File(second["host_path"].toString()).readText())
        assertEquals("value\n12\n", ((first["openability"] as Map<*, *>)["details"] as Map<*, *>)["text"])
        assertEquals("value\n15\n", ((second["openability"] as Map<*, *>)["details"] as Map<*, *>)["text"])
    }

    @Test fun `repeated export reuses content identity without duplicate artifacts`() {
        val tools = tools()
        tools.writeText("test", "report.md", "# Report\n")
        val first = export(tools, "report.md")
        val second = export(tools, "report.md")
        assertEquals(first["sha256"], second["sha256"])
        assertEquals(first["host_path"], second["host_path"])
    }

    @Test fun `missing directory and escaped paths cannot export`() {
        val tools = tools()
        tools.mkdir("test", "folder")
        for (path in listOf("missing.txt", "folder", "../other.txt", "/absolute.txt")) {
            assertTrue(path, tools.exportArtifact("test", path) is AgentWorkspaceFileResult.Failure)
        }
    }

    @Test fun `invalid UTF8 remains explicitly unverified rather than claiming openability`() {
        val tools = tools()
        tools.write("test", "broken.txt", byteArrayOf(0xc3.toByte(), 0x28))
        val artifact = export(tools, "broken.txt")
        assertEquals("unverified", (artifact["openability"] as Map<*, *>)["status"])
    }

    @Test fun `oversize exports fail and remove temporary snapshots`() {
        val tools = tools(AgentWorkspaceFilePolicy(maxHashBytes = 2))
        tools.writeText("test", "large.txt", "123")
        val failed = tools.exportArtifact("test", "large.txt") as AgentWorkspaceFileResult.Failure
        assertEquals(AgentWorkspaceFileErrorCode.LIMIT_EXCEEDED, failed.error.code)
        val remaining = temporary.root.walkTopDown().filter { it.name.endsWith(".tmp") }.toList()
        assertTrue(remaining.isEmpty())
    }
}
