package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasFunctionStoryTest {
    @Test fun onlySupportedTargetsShareTheGlucoseUptakeStory() {
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("tissue-skeletal-muscle"))
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("cell-adipocyte"))
        assertEquals(HealthAtlasFunctionStory.INSULIN_SECRETION, HealthAtlasFunctionStory.forId("cell-pancreatic-beta-cell"))
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
        assertEquals(HealthAtlasFunctionStory.INSULIN_SECRETION, HealthAtlasFunctionStory.forId("pancreatic-islets"))
        assertEquals(HealthAtlasDigestionStage.VILLUS.caption, meal.chapters.last().second)
        assertEquals(HealthAtlasDigestionStage.WATER.caption, colon.chapters[2].second)
        assertTrue(meal.chapters.toSet().intersect(colon.chapters.toSet()).isEmpty())
    }

    @Test fun visionAndAdaptationAreScopedToDifferentEntriesAndKeepContinuousBrightness() {
        val vision = HealthAtlasFunctionStory.VISION
        val light = HealthAtlasFunctionStory.LIGHT_ADAPTATION
        listOf("eye", "cornea", "lens", "retina", "cell-retinal-bipolar-cell", "cell-retinal-ganglion-cell")
            .forEach { assertEquals(vision, HealthAtlasFunctionStory.forId(it)) }
        listOf("cell-rod-photoreceptor", "cell-cone-photoreceptor")
            .forEach { assertEquals(light, HealthAtlasFunctionStory.forId(it)) }
        assertNull(HealthAtlasFunctionStory.forId("cell-retinal-pigment-epithelial-cell"))
        val scenes = HealthAtlasVisionStage.adaptation
        for (i in 1 until scenes.size) {
            assertEquals(scenes[i - 1].displayLight(1f), scenes[i].displayLight(0f), .000001f)
        }
        assertTrue(HealthAtlasVisionStage.DIM.displayLight(.1f) > HealthAtlasVisionStage.DIM.displayLight(.9f))
        assertTrue(HealthAtlasVisionStage.MIXED.displayLight(.1f) < HealthAtlasVisionStage.MIXED.displayLight(.9f))
        assertTrue(vision.chapters.toSet().intersect(light.chapters.toSet()).isEmpty())
    }

    @Test fun movementAndBoneRemodelingKeepDifferentOwnersAndProcessGeometry() {
        val movement = HealthAtlasMovementGeometry
        listOf("muscle", "biceps-brachii", "triceps-brachii", "tendons", "cell-skeletal-myocyte").forEach {
            assertEquals(HealthAtlasFunctionStory.MUSCLE_MOTION, HealthAtlasFunctionStory.forId(it))
        }
        listOf("skeletal", "humerus", "radius", "ulna", "tissue-compact-bone",
            "cell-osteoblast", "cell-osteocyte", "cell-osteoclast").forEach {
            assertEquals(HealthAtlasFunctionStory.BONE_REMODELING, HealthAtlasFunctionStory.forId(it))
        }
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("tissue-skeletal-muscle"))
        assertNull(HealthAtlasFunctionStory.forId("cell-cardiomyocyte"))
        assertNull(HealthAtlasFunctionStory.forId("bone-marrow"))
        assertTrue(movement.sarcomereHalfWidth(1f) < movement.sarcomereHalfWidth(0f))
        assertTrue(movement.ACTIN_LENGTH + movement.MYOSIN_LENGTH / 2 > movement.sarcomereHalfWidth(0f))
        assertEquals(movement.elbowAngle(false, 1f), movement.elbowAngle(true, 0f), 0f)
        assertEquals(movement.elbowAngle(false, 0f), movement.elbowAngle(true, 1f), 0f)
        for (chapter in 0..3) {
            assertEquals(movement.exposedDepth(chapter, 1f), movement.exposedDepth(chapter + 1, 0f), 0f)
        }
        assertTrue(movement.erosionDepth(1, .9f) > movement.erosionDepth(1, .1f))
        assertTrue(movement.exposedDepth(3, .9f) < movement.exposedDepth(3, .1f))
        assertEquals(movement.erosionDepth(3, .1f), movement.erosionDepth(3, .9f), 0f)
    }

    @Test fun lymphFlowDoesNotRouteThroughTheSpleenAndKeepsTheValvesIndependent() {
        listOf("lymphatic-vessels", "lymph-nodes", "thoracic-duct", "cell-lymphatic-endothelial-cell").forEach {
            assertEquals(HealthAtlasFunctionStory.LYMPH_RETURN, HealthAtlasFunctionStory.forId(it))
        }
        listOf("immune", "cell-b-cell", "cell-plasma-cell").forEach {
            assertEquals(HealthAtlasFunctionStory.ANTIBODY_RESPONSE, HealthAtlasFunctionStory.forId(it))
        }
        assertNull(HealthAtlasFunctionStory.forId("spleen"))
        assertNull(HealthAtlasFunctionStory.forId("cell-t-cell"))
        val pump = HealthAtlasLymphPumpStage
        assertEquals(0f, pump.cycle(Float.NaN), 0f)
        assertEquals(0f, pump.expansion(.97f), .00001f)
        assertEquals(1f, pump.expansion(.57f), .00001f)
        assertTrue(pump.expansion(.40f) > pump.expansion(.15f))
        assertTrue(pump.expansion(.60f) > pump.expansion(.90f))
        assertEquals(HealthAtlasLymphPumpStage.FILLING, pump.at(.24f))
        assertEquals(HealthAtlasLymphPumpStage.HOLDING, pump.at(.49f))
        assertEquals(HealthAtlasLymphPumpStage.EMPTYING, pump.at(.65f))
        for (i in 0..1000) {
            val cycle = pump.cycle(i / 1000f)
            val valves = pump.at(cycle)
            assertFalse(valves.inletOpen && valves.outletOpen)
            assertTrue(pump.expansion(cycle) in 0f..1f)
        }
    }

    @Test fun insulinReleaseAndUptakeStaySeparateWithValidatedMultipleLessons() {
        val insulin = HealthAtlasFunctionStory.INSULIN_SECRETION
        val uptake = HealthAtlasFunctionStory.GLUCOSE
        val motion = HealthAtlasFunctionStory.MUSCLE_MOTION
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION, insulin), HealthAtlasFunctionStory.choicesForId("pancreas"))
        assertEquals(listOf(uptake, motion), HealthAtlasFunctionStory.choicesForId("tissue-skeletal-muscle"))
        assertEquals(listOf(HealthAtlasFunctionStory.ANTIBODY_RESPONSE, HealthAtlasFunctionStory.LYMPH_RETURN),
            HealthAtlasFunctionStory.choicesForId("immune"))
        assertEquals(listOf(insulin), HealthAtlasFunctionStory.choicesForId("cell-pancreatic-beta-cell"))
        assertTrue(HealthAtlasFunctionStory.choicesForId("cell-pancreatic-alpha-cell").isEmpty())
        for (story in listOf(insulin, uptake)) {
            val (id, related) = requireNotNull(story.relatedLesson)
            assertTrue(related in HealthAtlasFunctionStory.choicesForId(id))
            assertNotEquals(story, related)
        }
        val state = HealthAtlasFunctionState()
        state.savePhase("tissue-skeletal-muscle", uptake, .6f)
        state.choose("tissue-skeletal-muscle", motion)
        state.savePhase("tissue-skeletal-muscle", motion, .2f)
        state.choose("tissue-skeletal-muscle", insulin)
        assertEquals(motion, state.current("tissue-skeletal-muscle"))
        assertEquals(.6f, state.loadPhase("tissue-skeletal-muscle", uptake), 0f)
        assertEquals(.2f, state.loadPhase("tissue-skeletal-muscle", motion), 0f)
        assertEquals(0f, state.loadPhase("cell-adipocyte", uptake), 0f)
    }

    @Test fun betaGranulesDoNotReleaseBeforeFusionAndTheIonChannelsChangeOppositely() {
        val diagram = HealthAtlasInsulinDiagram
        assertEquals(1f, diagram.potassiumOpen(0f), 0f)
        assertEquals(0f, diagram.potassiumOpen(1f), 0f)
        assertEquals(0f, diagram.calciumOpen(0f), 0f)
        assertEquals(1f, diagram.calciumOpen(1f), 0f)
        assertEquals(1f, diagram.approach(diagram.FUSION_START), 0f)
        assertEquals(0f, diagram.aperture(diagram.FUSION_START), 0f)
        assertTrue(diagram.aperture(.70f) > diagram.aperture(.57f))
        for (i in 0..2) {
            assertEquals(0f, diagram.release(diagram.FUSION_START, i), 0f)
            assertTrue(diagram.release(.85f, i) > diagram.release(.58f, i))
        }
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
