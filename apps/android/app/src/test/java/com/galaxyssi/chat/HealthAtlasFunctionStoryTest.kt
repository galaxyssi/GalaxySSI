package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasFunctionStoryTest {
    @Test fun onlySupportedTargetsShareTheGlucoseUptakeStory() {
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("tissue-skeletal-muscle"))
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("cell-adipocyte"))
        assertNull(HealthAtlasFunctionStory.forId("cell-pancreatic-beta-cell"))
        assertNull(HealthAtlasFunctionStory.forId("liver"))
        assertNull(HealthAtlasFunctionStory.forId(null))
    }

    @Test fun heartbeatIsScopedAndValvesNeverAllowConflictingVentricularFlow() {
        for (id in listOf("heart", "cardio", "atria", "ventricles", "heart-valves",
            "left-atrium", "right-atrium", "left-ventricle", "right-ventricle") + HealthAtlasValve.entries.map { it.id }) {
            assertEquals(HealthAtlasFunctionStory.HEARTBEAT, HealthAtlasFunctionStory.forId(id))
        }
        assertNull(HealthAtlasFunctionStory.forId("blood"))
        HealthAtlasBeatStage.entries.forEachIndexed { i, stage ->
            val expected = when (i) {
                0, 1 -> setOf(HealthAtlasValve.TRICUSPID, HealthAtlasValve.MITRAL)
                3 -> setOf(HealthAtlasValve.PULMONARY, HealthAtlasValve.AORTIC)
                else -> emptySet()
            }
            assertEquals(expected, HealthAtlasValve.entries.filter { stage.valveOpenness(it, .5f) == 1f }.toSet())
            assertEquals(expected.size, if (stage.fillsVentricles || stage.ejects) 2 else 0)
            for (valve in HealthAtlasValve.entries.filter { it !in expected }) {
                for (t in 0..10) assertEquals(0f, stage.valveOpenness(valve, t / 10f), 0f)
            }
            val next = HealthAtlasBeatStage.entries[(i + 1) % 5]
            assertEquals(stage.ventricularNarrowing(1f), next.ventricularNarrowing(0f), .000001f)
            for (valve in HealthAtlasValve.entries) {
                assertEquals(stage.valveOpenness(valve, 1f), next.valveOpenness(valve, 0f), .000001f)
            }
        }
        assertEquals(0f, HealthAtlasBeatStage.PRESSURE_RISE.ventricularNarrowing(.65f), 0f)
        assertEquals(1f, HealthAtlasBeatStage.RELAXATION.ventricularNarrowing(.65f), 0f)
        assertTrue(HealthAtlasBeatStage.EJECTION.ventricularNarrowing(.75f) > HealthAtlasBeatStage.EJECTION.ventricularNarrowing(.25f))
    }

    @Test fun breathingMovesFromWholeLungsToExchangeAndBackWithoutAShapeJump() {
        val stage = HealthAtlasBreathingStage.entries
        for (id in listOf("respiratory", "lungs", "diaphragm", "trachea", "bronchi", "bronchioles", "alveoli",
            "respiratory-membrane", "pulmonary-capillaries")) {
            assertEquals(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.forId(id))
        }
        assertNull(HealthAtlasFunctionStory.forId("cell-red-blood-cell"))
        stage.forEachIndexed { i, current ->
            val next = stage[(i + 1) % stage.size]
            assertEquals(current.closeUp(1f), next.closeUp(0f), .000001f)
            assertEquals(current.expansion(1f), next.expansion(0f), .000001f)
            assertEquals(i == stage.lastIndex, current.exhales)
        }
        assertTrue(stage.first().expansion(.75f) > stage.first().expansion(.25f))
        assertTrue(stage.last().expansion(.75f) < stage.last().expansion(.25f))
        assertEquals(1f, HealthAtlasBreathingStage.DIFFUSE.closeUp(.5f), 0f)
    }

    @Test fun hearingStoryIsScopedAndItsWaveTravelsFromBaseTowardApex() {
        for (id in listOf("ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "cell-inner-ear-hair-cell")) {
            assertEquals(HealthAtlasFunctionStory.HEARING, HealthAtlasFunctionStory.forId(id))
        }
        assertNull(HealthAtlasFunctionStory.forId("vestibular-apparatus"))
        assertNull(HealthAtlasFunctionStory.forId("cell-hair-matrix-cell"))
        assertEquals(0f, HealthAtlasSoundStage.packet(.90f, .10f), 0f)
        assertEquals(0f, HealthAtlasSoundStage.packet(.10f, .90f), 0f)
        assertNotEquals(0f, HealthAtlasSoundStage.packet(.85f, .90f), .01f)
        assertTrue(HealthAtlasSoundStage.oscillation(.09f) > 0f)
        assertTrue(HealthAtlasSoundStage.oscillation(.25f) < 0f)
    }

    @Test fun nephronChaptersKeepCrossWallTransferSeparateFromTubularFlow() {
        val story = HealthAtlasFunctionStory.NEPHRON
        for (id in listOf("urinary", "kidneys", "nephron", "glomerulus", "bowmans-capsule", "renal-tubules",
            "proximal-tubule", "nephron-loop", "distal-tubule", "collecting-ducts")) {
            assertEquals(story, HealthAtlasFunctionStory.forId(id))
        }
        assertNull(HealthAtlasFunctionStory.forId("bladder"))
        assertNull(HealthAtlasFunctionStory.forId("cell-urothelial-cell"))
        val chapters = HealthAtlasNephronStage.entries.map { it.routes.toSet() }
        assertEquals(5, chapters.toSet().size)
        assertEquals(setOf(HealthAtlasNephronRoute.BLOOD, HealthAtlasNephronRoute.FILTER), chapters[0])
        assertTrue(HealthAtlasNephronRoute.REABSORB in chapters[1])
        assertTrue(setOf(HealthAtlasNephronRoute.LOOP_WATER, HealthAtlasNephronRoute.LOOP_SALT).all { it in chapters[2] })
        assertTrue(HealthAtlasNephronRoute.SECRETE in chapters[3])
        assertTrue(HealthAtlasNephronRoute.URINE in chapters[4])
        assertFalse(chapters.any { HealthAtlasNephronRoute.BLOOD in it && HealthAtlasNephronRoute.URINE in it })
    }

    @Test fun digestionAndColonUseDifferentStagesAndEntryPoints() {
        val meal = HealthAtlasFunctionStory.DIGESTION
        val colon = HealthAtlasFunctionStory.COLON
        listOf("digestive", "oral-cavity", "pharynx", "esophagus", "stomach", "duodenum", "jejunum",
            "ileum", "gallbladder", "pancreatic-duct", "cell-enterocyte").forEach {
            assertEquals(meal, HealthAtlasFunctionStory.forId(it))
        }
        listOf("large-intestine", "cecum", "colon", "rectum", "anal-canal").forEach {
            assertEquals(colon, HealthAtlasFunctionStory.forId(it))
        }
        assertNull(HealthAtlasFunctionStory.forId("appendix"))
        assertNull(HealthAtlasFunctionStory.forId("pancreatic-islets"))
        assertEquals(HealthAtlasDigestionStage.VILLUS.caption, meal.chapters.last().second)
        assertEquals(HealthAtlasDigestionStage.WATER.caption, colon.chapters[2].second)
        assertTrue(meal.chapters.toSet().intersect(colon.chapters.toSet()).isEmpty())
    }

    @Test fun allChaptersScrubToTheirOwnBoundariesAndRejectInvalidState() = HealthAtlasFunctionStory.entries.forEach { story ->
        assertEquals(5, story.chapters.size)
        assertEquals(5, story.chapters.map { it.second }.toSet().size)
        for (i in story.chapters.indices) {
            val start = story.startOf(i)
            assertEquals(i, story.chapter(start))
            assertEquals(0f, story.fraction(start), .00001f)
            assertEquals(.5f, story.fraction(start + .1f), .00001f)
        }
        assertEquals(4, story.chapter(1f))
        assertEquals(1f, story.fraction(1f), 0f)
        assertEquals(0f, HealthAtlasFunctionStory.safePhase(Float.NaN), 0f)
        assertEquals(0f, HealthAtlasFunctionStory.safePhase(Float.POSITIVE_INFINITY), 0f)
        assertEquals(0f, story.startOf(-1), 0f)
        assertEquals(.8f, story.startOf(5), 0f)
    }
}
