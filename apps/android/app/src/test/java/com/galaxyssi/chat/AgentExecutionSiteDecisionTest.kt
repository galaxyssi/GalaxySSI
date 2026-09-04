package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentExecutionSiteDecisionTest {
    @Test
    fun negativeDesktopInstructionCannotAuthorizeDesktopExecution() {
        val goal = "Run the project on this phone. Do not execute on Desktop."
        val response = """
            {
              "execution_location":"desktop",
              "execution_location_evidence":"Do not execute on Desktop"
            }
        """.trimIndent()

        assertNull(AgentExecutionSiteDecisionCodec.parse(response, goal))
    }

    @Test
    fun explicitPositiveDesktopInstructionCanAuthorizeDesktopExecution() {
        val goal = "Execute this build on Desktop and return the APK."
        val response = """
            {
              "execution_location":"desktop",
              "execution_location_evidence":"Execute this build on Desktop"
            }
        """.trimIndent()

        assertEquals(
            AgentRequestedExecutionSite.DESKTOP,
            AgentExecutionSiteDecisionCodec.parse(response, goal)?.site
        )
    }
}
