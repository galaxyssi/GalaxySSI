package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasFunctionStoryTest {
    @Test fun onlySupportedTargetsShareTheGlucoseUptakeStory() {
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("tissue-skeletal-muscle"))
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("tissue-white-adipose"))
        assertEquals(HealthAtlasFunctionStory.GLUCOSE, HealthAtlasFunctionStory.forId("cell-adipocyte"))
        assertEquals(listOf(HealthAtlasFunctionStory.MUSCLE_MOTION, HealthAtlasFunctionStory.GLUCOSE),
            HealthAtlasFunctionStory.choicesForId("cell-skeletal-myocyte"))
        assertEquals(HealthAtlasFunctionStory.INSULIN_SECRETION, HealthAtlasFunctionStory.forId("cell-pancreatic-beta-cell"))
        assertEquals(HealthAtlasFunctionStory.GLUCAGON_RESPONSE, HealthAtlasFunctionStory.forId("liver"))
        assertNull(HealthAtlasFunctionStory.forId(null))
    }

    @Test fun tissueEntriesReuseOnlyTheirMatchingPlaybackLesson() {
        val lessons = mapOf(
            "tissue-alveolar-epithelium" to listOf(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.ALVEOLAR_SURFACTANT),
            "tissue-renal-tubular-epithelium" to listOf(HealthAtlasFunctionStory.NEPHRON),
            "tissue-cardiac-muscle" to listOf(HealthAtlasFunctionStory.HEARTBEAT),
            "tissue-intestinal-epithelium" to listOf(HealthAtlasFunctionStory.INTESTINAL_ABSORPTION, HealthAtlasFunctionStory.DIGESTION),
        )
        for ((id, stories) in lessons) {
            assertEquals(id, stories.first(), HealthAtlasFunctionStory.forId(id))
            assertEquals(id, stories, HealthAtlasFunctionStory.choicesForId(id))
        }
    }

    @Test fun tissueAndPlateletMechanismsHaveScopedPlayback() {
        val owners = mapOf(
            "tissue-vascular-endothelium" to HealthAtlasFunctionStory.ENDOTHELIAL_EXCHANGE,
            "cell-vascular-endothelial-cell" to HealthAtlasFunctionStory.ENDOTHELIAL_EXCHANGE,
            "fragment-platelet" to HealthAtlasFunctionStory.PLATELET_HEMOSTASIS,
            "tissue-smooth-muscle" to HealthAtlasFunctionStory.SMOOTH_MUSCLE_WAVE,
            "cell-smooth-muscle-cell" to HealthAtlasFunctionStory.SMOOTH_MUSCLE_WAVE,
            "tissue-dense-regular-connective" to HealthAtlasFunctionStory.TENDON_FORCE_TRANSFER,
            "tissue-hyaline-cartilage" to HealthAtlasFunctionStory.CARTILAGE_LOAD,
        )
        for ((id, story) in owners) {
            assertEquals(id, story, HealthAtlasFunctionStory.forId(id))
            assertEquals(id, listOf(story), HealthAtlasFunctionStory.choicesForId(id))
        }
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION, HealthAtlasFunctionStory.INTESTINAL_ABSORPTION,
            HealthAtlasFunctionStory.SMOOTH_MUSCLE_WAVE),
            HealthAtlasFunctionStory.choicesForId("small-intestine"))
        assertEquals(listOf(HealthAtlasFunctionStory.MUSCLE_MOTION, HealthAtlasFunctionStory.TENDON_FORCE_TRANSFER),
            HealthAtlasFunctionStory.choicesForId("tendons"))
        assertEquals(HealthAtlasFunctionStory.ENDOTHELIAL_EXCHANGE, HealthAtlasFunctionStory.forId("capillaries"))
        assertEquals(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.forId("pulmonary-capillaries"))
        assertNull(HealthAtlasFunctionStory.forId("cell-chondrocyte"))
    }

    @Test fun glut4DocksAndFlattensContinuouslyBeforeGlucoseCrossesTheMembrane() {
        val radius = HealthAtlasUptakeMotion.RADIUS
        val surface = HealthAtlasUptakeMotion.SURFACE
        val start = HealthAtlasUptakeMotion(3, 0f)
        val dock = HealthAtlasUptakeMotion(3, .58f)
        val justBefore = HealthAtlasUptakeMotion(3, .579f)
        val justAfter = HealthAtlasUptakeMotion(3, .581f)
        val open = HealthAtlasUptakeMotion(3, .80f)
        val fused = HealthAtlasUptakeMotion(3, 1f)
        assertEquals(HealthAtlasUptakeMotion(2, 1f).transporterX, start.transporterX, 0f)
        assertEquals(HealthAtlasUptakeMotion(2, 1f).transporterY, start.transporterY, 0f)
        assertTrue(start.vesicleY + radius < surface)
        assertEquals(surface, dock.vesicleY + radius, .0001f)
        assertEquals(justBefore.transporterX, justAfter.transporterX, .002f)
        assertEquals(justBefore.transporterY, justAfter.transporterY, .002f)
        assertTrue(open.opening > 0f)
        assertTrue(open.radiusY in 0f..radius)
        assertEquals(0f, fused.radiusY, 0f)
        assertEquals(surface, fused.transporterY, 0f)
        assertEquals(fused.transporterY, HealthAtlasUptakeMotion(4, 0f).transporterY, 0f)
        for (index in 0..2) {
            for (step in 0..10) {
                assertEquals(0f, HealthAtlasUptakeMotion(3, step / 10f).glucoseTravel(index), 0f)
            }
            assertEquals(1f, HealthAtlasUptakeMotion(4, 1f).glucoseTravel(index), 0f)
        }
        assertTrue(HealthAtlasUptakeMotion(4, .50f).glucoseTravel(0) >
            HealthAtlasUptakeMotion(4, .50f).glucoseTravel(1))
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

    @Test fun airwayClearanceTracksTrappedParticlesWithoutReplacingGasExchange() {
        val airway = HealthAtlasFunctionStory.AIRWAY_CLEARANCE
        val breathing = HealthAtlasFunctionStory.BREATHING
        for (id in listOf("tissue-respiratory-epithelium", "cell-ciliated-airway-cell", "cell-goblet-cell")) {
            assertEquals(airway, HealthAtlasFunctionStory.forId(id))
        }
        for (id in listOf("respiratory", "trachea", "bronchi")) {
            assertEquals(listOf(breathing, airway), HealthAtlasFunctionStory.choicesForId(id))
        }
        assertFalse(airway in HealthAtlasFunctionStory.choicesForId("alveoli"))
        assertTrue(HealthAtlasAirwayMotion.fall(0, .6f, 0) > HealthAtlasAirwayMotion.fall(0, .6f, 2))
        for (step in 0..2) assertEquals(0f, HealthAtlasAirwayMotion.surfaceTravel(step, 1f), 0f)
        assertEquals(1f, HealthAtlasAirwayMotion.fall(0, 1f, 2), 0f)
        assertEquals(HealthAtlasAirwayMotion.surfaceTravel(3, 1f), HealthAtlasAirwayMotion.surfaceTravel(4, 0f), 0f)
        assertEquals(1f, HealthAtlasAirwayMotion.surfaceTravel(4, 1f), 0f)
    }

    @Test fun hearingStoryIsScopedAndItsWaveTravelsFromBaseTowardApex() {
        for (id in listOf("ear", "external-ear", "middle-ear", "inner-ear", "cochlea", "cell-inner-ear-hair-cell")) {
            assertEquals(HealthAtlasFunctionStory.HEARING, HealthAtlasFunctionStory.forId(id))
        }
        assertEquals(HealthAtlasFunctionStory.VESTIBULAR_BALANCE, HealthAtlasFunctionStory.forId("vestibular-apparatus"))
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

    @Test fun surfactantAndAbsorptionExtendButDoNotReplaceWholeOrganPlayback() {
        val surfactant = HealthAtlasFunctionStory.ALVEOLAR_SURFACTANT
        val absorption = HealthAtlasFunctionStory.INTESTINAL_ABSORPTION
        val breathing = HealthAtlasFunctionStory.BREATHING
        val digestion = HealthAtlasFunctionStory.DIGESTION
        assertEquals(surfactant, HealthAtlasFunctionStory.forId("cell-type-ii-pneumocyte"))
        assertFalse(surfactant in HealthAtlasFunctionStory.choicesForId("cell-type-i-pneumocyte"))
        assertEquals(listOf(breathing, surfactant), HealthAtlasFunctionStory.choicesForId("alveoli"))
        for (id in listOf("cell-enterocyte", "duodenum", "jejunum", "ileum")) {
            assertEquals(listOf(digestion, absorption), HealthAtlasFunctionStory.choicesForId(id))
        }
        assertEquals(listOf("lymphatic-vessels" to HealthAtlasFunctionStory.LYMPH_RETURN), absorption.relatedLessons)
    }

    @Test fun visionAndAdaptationAreScopedToDifferentEntriesAndKeepContinuousBrightness() {
        val vision = HealthAtlasFunctionStory.VISION
        val light = HealthAtlasFunctionStory.LIGHT_ADAPTATION
        listOf("eye", "cornea", "lens", "retina", "cell-retinal-bipolar-cell", "cell-retinal-ganglion-cell")
            .forEach { assertEquals(vision, HealthAtlasFunctionStory.forId(it)) }
        listOf("cell-rod-photoreceptor", "cell-cone-photoreceptor")
            .forEach { assertEquals(light, HealthAtlasFunctionStory.forId(it)) }
        assertEquals(HealthAtlasFunctionStory.RPE_VISUAL_CYCLE,
            HealthAtlasFunctionStory.forId("cell-retinal-pigment-epithelial-cell"))
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
        val glucagon = HealthAtlasFunctionStory.GLUCAGON_RESPONSE
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION, insulin, glucagon), HealthAtlasFunctionStory.choicesForId("pancreas"))
        assertEquals(listOf(uptake, motion), HealthAtlasFunctionStory.choicesForId("tissue-skeletal-muscle"))
        assertEquals(listOf(HealthAtlasFunctionStory.ANTIBODY_RESPONSE, HealthAtlasFunctionStory.LYMPH_RETURN),
            HealthAtlasFunctionStory.choicesForId("immune"))
        assertEquals(listOf(insulin), HealthAtlasFunctionStory.choicesForId("cell-pancreatic-beta-cell"))
        assertEquals(listOf(glucagon), HealthAtlasFunctionStory.choicesForId("cell-pancreatic-alpha-cell"))
        for (story in listOf(insulin, uptake, glucagon)) {
            assertTrue(story.relatedLessons.isNotEmpty())
            for ((id, related) in story.relatedLessons) {
                assertTrue(related in HealthAtlasFunctionStory.choicesForId(id))
                assertNotEquals(story, related)
            }
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

    @Test fun glucagonAndSweatUseSeparatePhysiologyAndQualitativeComparisons() {
        val glucagon = HealthAtlasFunctionStory.GLUCAGON_RESPONSE
        val sweat = HealthAtlasFunctionStory.SWEAT_COOLING
        for (id in listOf("cell-pancreatic-alpha-cell", "liver", "cell-hepatocyte")) {
            assertEquals(glucagon, HealthAtlasFunctionStory.forId(id))
        }
        assertEquals(listOf(HealthAtlasFunctionStory.INSULIN_SECRETION, glucagon),
            HealthAtlasFunctionStory.choicesForId("pancreatic-islets"))
        assertEquals(listOf(HealthAtlasFunctionStory.INSULIN_SECRETION, glucagon, HealthAtlasFunctionStory.THYROID_FEEDBACK),
            HealthAtlasFunctionStory.choicesForId("endocrine"))
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION), HealthAtlasFunctionStory.choicesForId("gallbladder"))
        for (id in listOf("skin", "sweat-glands", "cell-sweat-gland-secretory-cell")) {
            assertEquals(sweat, HealthAtlasFunctionStory.forId(id))
        }
        assertNull(HealthAtlasFunctionStory.forId("sebaceous-glands"))
        val motion = HealthAtlasHomeostasisMotion
        assertEquals(1f, motion.liquidRemaining(0f, false), 0f)
        assertEquals(1f, motion.liquidRemaining(0f, true), 0f)
        assertEquals(1f, motion.liquidRemaining(Float.NaN, true), 0f)
        for (frame in 1..100) {
            val now = frame / 100f
            val previous = (frame - 1) / 100f
            assertTrue(motion.liquidRemaining(now, true) > motion.liquidRemaining(now, false))
            assertTrue(motion.liquidRemaining(now, true) < motion.liquidRemaining(previous, true))
            assertTrue(motion.liquidRemaining(now, false) < motion.liquidRemaining(previous, false))
            assertTrue(motion.glycogenRemaining(now) in 0f..1f)
            assertTrue(motion.glycogenRemaining(now) < motion.glycogenRemaining(previous))
        }
    }

    @Test fun axonAndThyroidStoriesKeepSeparateOwnersAndOrderedMotion() {
        val synapse = HealthAtlasFunctionStory.SYNAPTIC_SIGNAL
        val myelin = HealthAtlasFunctionStory.MYELIN_SIGNAL
        val thyroid = HealthAtlasFunctionStory.THYROID_FEEDBACK
        assertEquals(listOf(synapse, myelin), HealthAtlasFunctionStory.choicesForId("cell-neuron"))
        assertEquals(listOf(synapse, myelin), HealthAtlasFunctionStory.choicesForId("nervous"))
        assertEquals(listOf(myelin), HealthAtlasFunctionStory.choicesForId("cell-oligodendrocyte"))
        assertEquals(listOf(myelin), HealthAtlasFunctionStory.choicesForId("cell-schwann-cell"))
        assertEquals(listOf(thyroid), HealthAtlasFunctionStory.choicesForId("cell-thyrotroph"))
        assertEquals(listOf(thyroid), HealthAtlasFunctionStory.choicesForId("cell-thyroid-follicular-cell"))
        assertNull(HealthAtlasFunctionStory.forId("cell-thyroid-parafollicular-cell"))
        assertNull(HealthAtlasFunctionStory.forId("parathyroid-glands"))
        val motion = HealthAtlasSignalMotion
        assertEquals(0f, motion.axonTravel(0f, true), 0f)
        assertEquals(0f, motion.axonTravel(0f, false), 0f)
        assertEquals(1f, motion.upstreamDrive(0f), 0f)
        for (frame in 1..100) {
            val t = frame / 100f
            assertTrue(motion.axonTravel(t, true) > motion.axonTravel(t, false))
            assertTrue(motion.upstreamDrive(t) < motion.upstreamDrive((frame - 1) / 100f))
            for (index in 0..4) {
                assertTrue(motion.synapticRelease(t, index) in 0f..1f)
                if (t <= .35f) assertEquals(0f, motion.synapticRelease(t, index), 0f)
            }
        }
        assertTrue(motion.synapticRelease(.61f, 0) > motion.synapticRelease(.61f, 3))
    }

    @Test fun barrierAndGameteLessonsAreScopedAndHaveOrderedMotion() {
        val barrier = HealthAtlasFunctionStory.EPIDERMAL_BARRIER
        val sperm = HealthAtlasFunctionStory.SPERM_TRANSPORT
        val ovum = HealthAtlasFunctionStory.OVUM_TRANSPORT
        assertEquals(listOf(HealthAtlasFunctionStory.SWEAT_COOLING, barrier, HealthAtlasFunctionStory.TOUCH_SIGNAL),
            HealthAtlasFunctionStory.choicesForId("skin"))
        for (id in listOf("skin-organ", "epidermis", "tissue-epidermal", "cell-keratinocyte")) {
            assertEquals(barrier, HealthAtlasFunctionStory.choicesForId(id).first())
        }
        for (id in listOf("male", "testes", "epididymis", "vas-deferens", "cell-spermatozoon",
            "cell-sertoli-cell", "cell-spermatogonium", "cell-spermatocyte")) {
            assertEquals(listOf(sperm), HealthAtlasFunctionStory.choicesForId(id))
        }
        for (id in listOf("female", "ovaries", "uterine-tubes", "cell-oocyte-or-ovum",
            "cell-granulosa-cell", "cell-ciliated-oviduct-cell")) {
            assertEquals(listOf(ovum), HealthAtlasFunctionStory.choicesForId(id))
        }
        for (id in listOf("dermis", "prostate", "uterus", "cell-trophoblast")) {
            assertNull(HealthAtlasFunctionStory.forId(id))
        }
        val water = HealthAtlasBarrierMotion
        val flow = HealthAtlasGameteMotion
        assertTrue(water.ascent(1f) < water.ascent(0f))
        assertEquals(0f, water.escape(0f, true, 0), 0f)
        for (i in 0..5) {
            assertTrue(water.escape(.65f, true, i) > water.escape(.65f, false, i))
        }
        assertEquals(0f, flow.release(flow.FOLLICLE_OPENS), 0f)
        assertEquals(1f, flow.release(1f), .000001f)
        assertEquals(0f, flow.pickup(Float.NaN), 0f)
        assertEquals(1f, flow.pickup(1f), 0f)
        assertTrue(flow.pickup(.65f) > flow.pickup(.35f))
        assertTrue(flow.ductRadius(180f, .5f) < flow.ductRadius(65f, .5f))
        assertTrue(flow.ductRadius(180f, .5f) < flow.ductRadius(180f, .1f))
    }

    @Test fun sensoryAndGutOverviewsOfferTheRightDistinctLessons() {
        val smell = HealthAtlasFunctionStory.OLFACTION
        val taste = HealthAtlasFunctionStory.TASTE_SIGNAL
        val touch = HealthAtlasFunctionStory.TOUCH_SIGNAL
        val balance = HealthAtlasFunctionStory.VESTIBULAR_BALANCE
        val hearing = HealthAtlasFunctionStory.HEARING
        val meal = HealthAtlasFunctionStory.DIGESTION
        assertEquals(listOf(HealthAtlasFunctionStory.VISION, hearing, balance, smell, taste, touch),
            HealthAtlasFunctionStory.choicesForId("sensory"))
        assertEquals(listOf(meal, HealthAtlasFunctionStory.COLON), HealthAtlasFunctionStory.choicesForId("gut"))
        assertEquals(listOf(hearing, balance), HealthAtlasFunctionStory.choicesForId("ear"))
        assertEquals(listOf(hearing, balance), HealthAtlasFunctionStory.choicesForId("cell-inner-ear-hair-cell"))
        assertEquals(listOf(meal, taste), HealthAtlasFunctionStory.choicesForId("tongue"))
        assertEquals(listOf(smell), HealthAtlasFunctionStory.choicesForId("cell-olfactory-receptor-neuron"))
        assertEquals(listOf(taste), HealthAtlasFunctionStory.choicesForId("cell-taste-receptor-cell"))
        assertEquals(listOf(touch), HealthAtlasFunctionStory.choicesForId("cell-merkel-cell"))
        assertEquals(listOf(balance), HealthAtlasFunctionStory.choicesForId("vestibular-apparatus"))
        assertEquals(listOf(hearing), HealthAtlasFunctionStory.choicesForId("cochlea"))
        val senses = HealthAtlasChemicalSenseMotion
        assertEquals(0f, senses.transfer(.09f, 0, .12f), 0f)
        assertTrue(senses.transfer(.55f, 0, .12f) > senses.transfer(.55f, 2, .12f))
        assertNotEquals(senses.odorChannels(false), senses.odorChannels(true))
        val motion = HealthAtlasMotionSenseMotion
        assertEquals(0f, motion.touchLoad(0, .28f), 0f)
        assertEquals(motion.touchLoad(3, .2f), motion.touchLoad(3, .8f), 0f)
        assertEquals(0f, motion.touchLoad(4, 1f), 0f)
        for (i in 1..9) {
            val t = i / 10f
            assertTrue(motion.relativeFluid(t) < 0f)
            assertEquals(0f, motion.headHeading(t) + motion.gazeCounterRotation(t), 0f)
        }
    }

    @Test fun ocularCellsKeepSpecializedLessonsAndRetainTheExistingVisionAndAdaptationRoutes() {
        val pigment = HealthAtlasFunctionStory.RPE_VISUAL_CYCLE
        val relay = HealthAtlasFunctionStory.DIM_LIGHT_RELAY
        val cornea = HealthAtlasFunctionStory.CORNEAL_SURFACE_RENEWAL
        val vision = HealthAtlasFunctionStory.VISION
        val adaptation = HealthAtlasFunctionStory.LIGHT_ADAPTATION

        assertEquals(listOf(pigment), HealthAtlasFunctionStory.choicesForId("cell-retinal-pigment-epithelial-cell"))
        assertEquals(listOf(relay), HealthAtlasFunctionStory.choicesForId("cell-retinal-aii-amacrine-cell"))
        assertEquals(listOf(cornea), HealthAtlasFunctionStory.choicesForId("cell-corneal-epithelial-cell"))
        assertEquals(listOf(vision, relay, pigment), HealthAtlasFunctionStory.choicesForId("retina"))
        assertEquals(listOf(vision, relay), HealthAtlasFunctionStory.choicesForId("cell-retinal-bipolar-cell"))
        assertEquals(listOf(adaptation, relay, pigment), HealthAtlasFunctionStory.choicesForId("cell-rod-photoreceptor"))
        assertEquals(listOf(adaptation), HealthAtlasFunctionStory.choicesForId("cell-cone-photoreceptor"))
        assertEquals(listOf(vision, cornea), HealthAtlasFunctionStory.choicesForId("cornea"))
        assertEquals(listOf(vision), HealthAtlasFunctionStory.choicesForId("lens"))
        assertEquals(172f, HealthAtlasOcularMotion.transfer(0f, false), 0f)
        assertEquals(238f, HealthAtlasOcularMotion.transfer(1f, false), 0f)
        assertEquals(238f, HealthAtlasOcularMotion.transfer(0f, true), 0f)
        assertEquals(172f, HealthAtlasOcularMotion.transfer(1f, true), 0f)
        assertTrue(HealthAtlasOcularMotion.limbalRadius(.85f) < HealthAtlasOcularMotion.limbalRadius(.15f))
        assertTrue(HealthAtlasOcularMotion.relayFraction(.4f, 2) < HealthAtlasOcularMotion.relayFraction(.4f, 0))
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
