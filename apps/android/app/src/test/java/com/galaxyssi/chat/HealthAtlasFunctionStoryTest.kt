package com.galaxyssi.chat

import org.junit.Assert.*
import org.junit.Test

class HealthAtlasFunctionStoryTest {
    @Test fun cellPlaybackPreservesAllFourDedicatedMechanisms() {
        val routes = mapOf(
            "cell-neutrophil" to HealthAtlasFunctionStory.NEUTROPHIL_DEFENSE,
            "cell-eosinophil" to HealthAtlasFunctionStory.EOSINOPHIL_RESPONSE,
            "cell-basophil" to HealthAtlasFunctionStory.BASOPHIL_SIGNALING,
            "cell-monocyte" to HealthAtlasFunctionStory.MONOCYTE_RECRUITMENT,
            "cell-macrophage" to HealthAtlasFunctionStory.MACROPHAGE_CLEARANCE,
            "cell-dendritic-cell" to HealthAtlasFunctionStory.DENDRITIC_PRESENTATION,
            "cell-t-cell" to HealthAtlasFunctionStory.T_CELL_RESPONSE,
            "cell-natural-killer-cell" to HealthAtlasFunctionStory.NK_SURVEILLANCE,
            "cell-megakaryocyte" to HealthAtlasFunctionStory.PLATELET_FORMATION,
        )
        for ((id, story) in routes) {
            assertEquals(id, listOf(story), HealthAtlasFunctionStory.choicesForId(id))
            assertEquals(id, 4, story.chapters.size)
            assertEquals(id, .75f, story.startOf(3), 0f)
        }
        assertEquals(listOf(HealthAtlasFunctionStory.ANTIBODY_RESPONSE), HealthAtlasFunctionStory.choicesForId("cell-b-cell"))
        assertEquals(listOf(HealthAtlasFunctionStory.PLATELET_HEMOSTASIS), HealthAtlasFunctionStory.choicesForId("fragment-platelet"))
    }

    @Test fun specializedOrganAndCellLessonsKeepNeighboringMechanismsDistinct() {
        assertEquals(HealthAtlasFunctionStory.THYMIC_SELECTION, HealthAtlasFunctionStory.forId("thymus"))
        assertEquals(HealthAtlasFunctionStory.T_CELL_RESPONSE, HealthAtlasFunctionStory.forId("cell-t-cell"))
        assertEquals(HealthAtlasFunctionStory.SPLENIC_FILTER, HealthAtlasFunctionStory.forId("spleen"))
        assertEquals(HealthAtlasFunctionStory.RED_CELL_OXYGEN, HealthAtlasFunctionStory.forId("cell-erythrocyte"))
        assertEquals(HealthAtlasFunctionStory.LARYNGEAL_VOICE, HealthAtlasFunctionStory.forId("larynx"))
        assertEquals(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.forId("trachea"))
        assertEquals(HealthAtlasFunctionStory.CEREBELLAR_COORDINATION, HealthAtlasFunctionStory.forId("cerebellum"))
        assertEquals(HealthAtlasFunctionStory.SYNAPTIC_SIGNAL, HealthAtlasFunctionStory.forId("brain"))
        assertEquals(HealthAtlasFunctionStory.CEREBRAL_SENSORIMOTOR, HealthAtlasFunctionStory.forId("cerebrum"))
        assertEquals(HealthAtlasFunctionStory.AUTONOMIC_RELAY, HealthAtlasFunctionStory.forId("autonomic-nerves"))
        assertEquals(HealthAtlasFunctionStory.CRANIAL_REFLEX, HealthAtlasFunctionStory.forId("cranial-nerves"))
        assertEquals(HealthAtlasFunctionStory.ASTROCYTE_SUPPORT, HealthAtlasFunctionStory.forId("cell-astrocyte"))
        assertEquals(HealthAtlasFunctionStory.MYELIN_SIGNAL, HealthAtlasFunctionStory.forId("cell-oligodendrocyte"))
        assertEquals(HealthAtlasFunctionStory.MELANIN_TRANSFER, HealthAtlasFunctionStory.forId("cell-melanocyte"))
        assertEquals(HealthAtlasFunctionStory.BRAINSTEM_RHYTHM, HealthAtlasFunctionStory.forId("brainstem"))
        assertEquals(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.forId("diaphragm"))
        assertEquals(HealthAtlasFunctionStory.FIBROBLAST_MATRIX, HealthAtlasFunctionStory.forId("cell-fibroblast"))
        assertEquals(HealthAtlasFunctionStory.FIBROBLAST_MATRIX, HealthAtlasFunctionStory.forId("dermis"))
        assertEquals(listOf(HealthAtlasFunctionStory.EPIDERMAL_BARRIER, HealthAtlasFunctionStory.TOUCH_SIGNAL,
            HealthAtlasFunctionStory.MELANIN_TRANSFER), HealthAtlasFunctionStory.choicesForId("epidermis"))
    }

    @Test fun arterialExpansionAndTravelStaySeparateFromHeartAndVeinPlayback() {
        val story = HealthAtlasFunctionStory.ARTERIAL_PULSE
        assertEquals(listOf(story), HealthAtlasFunctionStory.choicesForId("arteries"))
        assertEquals(listOf(HealthAtlasFunctionStory.HEARTBEAT, story), HealthAtlasFunctionStory.choicesForId("aorta"))
        assertEquals(listOf(story, HealthAtlasFunctionStory.ENDOTHELIAL_EXCHANGE, HealthAtlasFunctionStory.VENOUS_RETURN),
            HealthAtlasFunctionStory.choicesForId("blood-vessels"))

        val motion = HealthAtlasArterialMotion
        assertEquals(0f, motion.expansion(1, Float.NaN, .3f), 0f)
        assertTrue(motion.expansion(1, .8f, .3f) > motion.expansion(1, .2f, .3f))
        assertTrue(motion.expansion(3, .8f, .3f) < motion.expansion(3, .2f, .3f))
        assertTrue(motion.flowTravel(3, .8f)!! > motion.flowTravel(3, .2f)!!)
        assertNull(motion.front(3, .5f))
        val early = requireNotNull(motion.front(2, .2f))
        val late = requireNotNull(motion.front(2, .8f))
        assertTrue(late > early)
        assertTrue(motion.expansion(2, .2f, early) > motion.expansion(2, .2f, late))
        assertTrue(motion.expansion(2, .8f, late) > motion.expansion(2, .8f, early))
    }

    @Test fun regionalTopicsRespectTheirCellAndOrganScope() {
        assertEquals(HealthAtlasFunctionStory.CORONARY_PERFUSION, HealthAtlasFunctionStory.forId("coronary-vessels"))
        assertEquals(HealthAtlasFunctionStory.HEARTBEAT, HealthAtlasFunctionStory.forId("heart"))
        assertEquals(HealthAtlasFunctionStory.PODOCYTE_BARRIER, HealthAtlasFunctionStory.forId("cell-podocyte"))
        assertEquals(HealthAtlasFunctionStory.NEPHRON, HealthAtlasFunctionStory.forId("glomerulus"))
        assertEquals(HealthAtlasFunctionStory.VISION, HealthAtlasFunctionStory.forId("eye"))
        assertEquals(HealthAtlasFunctionStory.CRANIAL_REFLEX, HealthAtlasFunctionStory.forId("cranial-nerves"))
        assertEquals(HealthAtlasFunctionStory.ENDOMETRIUM_RENEWAL, HealthAtlasFunctionStory.forId("endometrium"))
        assertNull(HealthAtlasFunctionStory.forId("cervix"))
        assertEquals(HealthAtlasFunctionStory.ADRENAL_MEDULLA_SIGNAL, HealthAtlasFunctionStory.forId("adrenal-glands"))
        assertEquals(HealthAtlasFunctionStory.ADRENAL_MEDULLA_SIGNAL, HealthAtlasFunctionStory.forId("cell-chromaffin-cell"))
        assertNull(HealthAtlasFunctionStory.forId("cell-adrenocortical-cell"))
        assertEquals(HealthAtlasFunctionStory.GASTRIC_ACID_SECRETION, HealthAtlasFunctionStory.forId("cell-gastric-parietal-cell"))
        assertEquals(HealthAtlasFunctionStory.GASTRIC_CHIEF_SECRETION, HealthAtlasFunctionStory.forId("cell-gastric-chief-cell"))
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION, HealthAtlasFunctionStory.GASTRIC_ACID_SECRETION,
            HealthAtlasFunctionStory.GASTRIC_CHIEF_SECRETION),
            HealthAtlasFunctionStory.choicesForId("stomach"))
        assertEquals(HealthAtlasFunctionStory.ACINAR_ENZYME_SECRETION, HealthAtlasFunctionStory.forId("cell-pancreatic-acinar-cell"))
        assertEquals(listOf("cell-pancreatic-acinar-cell" to HealthAtlasFunctionStory.ACINAR_ENZYME_SECRETION,
            "cell-pancreatic-ductal-cell" to HealthAtlasFunctionStory.PANCREATIC_DUCT_BUFFER,
            "teeth" to HealthAtlasFunctionStory.TOOTH_MASTICATION),
            HealthAtlasFunctionStory.DIGESTION.relatedLessons)
        assertEquals(HealthAtlasFunctionStory.NAIL_MATRIX_GROWTH, HealthAtlasFunctionStory.forId("nails"))
        assertEquals(HealthAtlasFunctionStory.TONSILLAR_SAMPLING, HealthAtlasFunctionStory.forId("tonsils"))
        assertEquals(HealthAtlasFunctionStory.OLFACTION, HealthAtlasFunctionStory.forId("nasal-cavity"))
        assertEquals(HealthAtlasFunctionStory.SINUS_DRAINAGE, HealthAtlasFunctionStory.forId("paranasal-sinuses"))
        assertEquals(HealthAtlasFunctionStory.DIGESTION, HealthAtlasFunctionStory.forId("oral-cavity"))
        assertEquals(HealthAtlasFunctionStory.TOOTH_MASTICATION, HealthAtlasFunctionStory.forId("teeth"))
        assertEquals(HealthAtlasFunctionStory.MARROW_HEMATOPOIESIS,
            HealthAtlasFunctionStory.forId("cell-hematopoietic-stem-cell"))
        assertEquals(HealthAtlasFunctionStory.RED_CELL_OXYGEN, HealthAtlasFunctionStory.forId("cell-erythrocyte"))
    }

    @Test fun specializedCellStoriesKeepTheirOrganRoutesAndOpenFromTheParentLesson() {
        val routes = listOf(
            Triple("cell-mesangial-cell", HealthAtlasFunctionStory.MESANGIAL_SUPPORT, "glomerulus" to HealthAtlasFunctionStory.NEPHRON),
            Triple("cell-collecting-duct-intercalated-cell", HealthAtlasFunctionStory.INTERCALATED_BALANCE,
                "collecting-ducts" to HealthAtlasFunctionStory.NEPHRON),
            Triple("cell-club-cell", HealthAtlasFunctionStory.CLUB_CELL_AIRWAY, "bronchioles" to HealthAtlasFunctionStory.BREATHING),
            Triple("cell-pancreatic-ductal-cell", HealthAtlasFunctionStory.PANCREATIC_DUCT_BUFFER, "pancreatic-duct" to HealthAtlasFunctionStory.DIGESTION),
        )
        for ((cell, story, organ) in routes) {
            assertEquals(listOf(story), HealthAtlasFunctionStory.choicesForId(cell))
            assertEquals(organ.second, HealthAtlasFunctionStory.forId(organ.first))
            assertEquals(listOf(organ), story.relatedLessons)
            assertTrue(cell to story in organ.second.relatedLessons)
            assertEquals(5, story.chapters.size)
            assertEquals(2, story.references.size)
            assertNotEquals(story.title, story.choiceTitle)
        }
    }

    @Test fun bileDuctAndCartilageExposeTheirSpecializedMotion() {
        val bile = HealthAtlasFunctionStory.CHOLANGIOCYTE_BILE
        val digestion = HealthAtlasFunctionStory.DIGESTION
        assertEquals(listOf(bile), HealthAtlasFunctionStory.choicesForId("cell-cholangiocyte"))
        assertEquals(listOf(digestion, bile), HealthAtlasFunctionStory.choicesForId("biliary-tract"))
        assertEquals(listOf("biliary-tract" to digestion), bile.relatedLessons)
        assertEquals(listOf(HealthAtlasFunctionStory.CARTILAGE_LOAD), HealthAtlasFunctionStory.choicesForId("cartilage"))
    }

    @Test fun pinealGlandAndPinealocyteStartAtDifferentScalesOfTheSamePathway() {
        val story = HealthAtlasFunctionStory.PINEAL_DARK_SIGNAL
        assertEquals(story, HealthAtlasFunctionStory.forId("pineal-gland"))
        assertEquals(story, HealthAtlasFunctionStory.forId("cell-pinealocyte"))
        assertEquals(0, story.chapter(story.entryPhase("pineal-gland")))
        assertEquals(3, story.chapter(story.entryPhase("cell-pinealocyte")))
        assertEquals(listOf("retina" to HealthAtlasFunctionStory.VISION), story.relatedLessons)
    }

    @Test fun thoracicFrameLessonConnectsRibsAndSternumToBreathing() {
        val frame = HealthAtlasFunctionStory.THORACIC_FRAME
        assertEquals(listOf(frame), HealthAtlasFunctionStory.choicesForId("ribs"))
        assertEquals(listOf(frame), HealthAtlasFunctionStory.choicesForId("sternum"))
        assertEquals(listOf("lungs" to HealthAtlasFunctionStory.BREATHING), frame.relatedLessons)
        assertEquals(5, frame.chapters.size)
    }

    @Test fun glialCellLessonsKeepSeparateFunctionsAndSurroundingContext() {
        val surveillance = HealthAtlasFunctionStory.MICROGLIA_SURVEILLANCE
        val flow = HealthAtlasFunctionStory.EPENDYMAL_FLOW
        assertEquals(listOf(surveillance), HealthAtlasFunctionStory.choicesForId("cell-microglia"))
        assertEquals(listOf(flow), HealthAtlasFunctionStory.choicesForId("cell-ependymal-cell"))
        assertEquals(listOf("cell-astrocyte" to HealthAtlasFunctionStory.ASTROCYTE_SUPPORT), surveillance.relatedLessons)
        assertEquals(listOf("brain" to HealthAtlasFunctionStory.SYNAPTIC_SIGNAL), flow.relatedLessons)
        assertTrue(surveillance.chapters.map { it.first }.intersect(flow.chapters.map { it.first }.toSet()).isEmpty())
    }

    @Test fun shoulderMuscleRolesStayDistinctFromTheShoulderBladeEntry() {
        val lift = HealthAtlasFunctionStory.DELTOID_LIFT
        val rotation = HealthAtlasFunctionStory.SCAPULAR_ROTATION
        assertEquals(lift, HealthAtlasFunctionStory.forId("deltoid"))
        assertEquals(rotation, HealthAtlasFunctionStory.forId("trapezius"))
        assertEquals(rotation, HealthAtlasFunctionStory.forId("scapula"))
        assertEquals(2, rotation.chapter(rotation.entryPhase("scapula")))
        assertEquals(listOf("trapezius" to rotation), lift.relatedLessons)
        assertEquals(listOf("deltoid" to lift), rotation.relatedLessons)
    }

    @Test fun focusedEntryChaptersAreOnlyDefaultsAndDoNotOverrideSavedPlayback() {
        val items = mapOf(
            "adenoids" to (HealthAtlasFunctionStory.TONSILLAR_SAMPLING to 1),
            "cell-endometrial-epithelial-cell" to (HealthAtlasFunctionStory.ENDOMETRIUM_RENEWAL to 4),
            "cell-endometrial-stromal-cell" to (HealthAtlasFunctionStory.ENDOMETRIUM_RENEWAL to 1),
            "cell-sebocyte" to (HealthAtlasFunctionStory.SEBUM_RELEASE to 2),
            "aorta" to (HealthAtlasFunctionStory.HEARTBEAT to HealthAtlasBeatStage.EJECTION.ordinal),
            "pulmonary-trunk" to (HealthAtlasFunctionStory.HEARTBEAT to HealthAtlasBeatStage.EJECTION.ordinal),
            "cell-type-i-pneumocyte" to (HealthAtlasFunctionStory.BREATHING to HealthAtlasBreathingStage.DIFFUSE.ordinal),
            "renal-cortex" to (HealthAtlasFunctionStory.NEPHRON to HealthAtlasNephronStage.FILTER.ordinal),
            "renal-medulla" to (HealthAtlasFunctionStory.NEPHRON to HealthAtlasNephronStage.LOOP.ordinal),
            "cell-proximal-tubular-cell" to (HealthAtlasFunctionStory.NEPHRON to HealthAtlasNephronStage.PROXIMAL.ordinal),
            "cell-collecting-duct-principal-cell" to (HealthAtlasFunctionStory.NEPHRON to HealthAtlasNephronStage.COLLECT.ordinal),
        )
        val state = HealthAtlasFunctionState()
        for ((id, expected) in items) {
            val (story, chapter) = expected
            assertEquals(id, story, HealthAtlasFunctionStory.forId(id))
            assertEquals(id, story.startOf(chapter), state.loadPhase(id, story), 0f)
            state.savePhase(id, story, 0f)
            assertEquals(id, 0f, state.loadPhase(id, story), 0f)
        }
        assertEquals(0f, state.loadPhase("alveoli", HealthAtlasFunctionStory.BREATHING), 0f)
        assertEquals(0f, state.loadPhase("heart", HealthAtlasFunctionStory.HEARTBEAT), 0f)
    }

    @Test fun regionalAnimationsOnlyOpenTheMatchingAnatomyAndKeepTheOriginalLessons() {
        val stories = mapOf(
            HealthAtlasFunctionStory.RED_CELL_OXYGEN to listOf("blood", "cell-erythrocyte"),
            HealthAtlasFunctionStory.SALIVA_SECRETION to listOf("parotid-glands", "submandibular-glands",
                "sublingual-glands", "cell-salivary-acinar-cell"),
            HealthAtlasFunctionStory.VENOUS_RETURN to listOf("veins", "gastrocnemius", "soleus"),
            HealthAtlasFunctionStory.HAIR_FOLLICLE_CYCLE to listOf("hair", "hair-follicles", "cell-hair-matrix-cell"),
            HealthAtlasFunctionStory.URINE_ROUTE to listOf("renal-pelvis", "ureters", "bladder", "urethra"),
            HealthAtlasFunctionStory.PLEURAL_COUPLING to listOf("pleura"),
            HealthAtlasFunctionStory.PARATHYROID_FEEDBACK to listOf("parathyroid-glands", "cell-parathyroid-chief-cell"),
            HealthAtlasFunctionStory.MAMMARY_MILK_FLOW to listOf("mammary-glands", "cell-mammary-luminal-cell", "cell-myoepithelial-cell"),
        )
        for ((story, ids) in stories) for (id in ids) assertEquals(id, listOf(story), HealthAtlasFunctionStory.choicesForId(id))
        val urine = HealthAtlasFunctionStory.URINE_ROUTE
        assertEquals(R.string.health_atlas_urine_route_story_peristalsis_caption,
            urine.chapters[urine.chapter(urine.entryPhase("ureters"))].second)
        assertEquals(R.string.health_atlas_urine_route_story_store_caption,
            urine.chapters[urine.chapter(urine.entryPhase("bladder"))].second)
        assertEquals(R.string.health_atlas_urine_route_story_empty_caption,
            urine.chapters[urine.chapter(urine.entryPhase("urethra"))].second)
        assertEquals(listOf(HealthAtlasFunctionStory.BREATHING, HealthAtlasFunctionStory.PLEURAL_COUPLING),
            HealthAtlasFunctionStory.choicesForId("lungs"))
        assertEquals(listOf(HealthAtlasFunctionStory.DIGESTION, HealthAtlasFunctionStory.SALIVA_SECRETION),
            HealthAtlasFunctionStory.choicesForId("salivary-glands"))
        assertEquals(listOf(HealthAtlasFunctionStory.NEPHRON), HealthAtlasFunctionStory.choicesForId("nephron"))
        val milk = HealthAtlasFunctionStory.MAMMARY_MILK_FLOW
        assertEquals(R.string.health_atlas_mammary_story_secrete_caption, milk.chapters[milk.chapter(milk.entryPhase("cell-mammary-luminal-cell"))].second)
        assertEquals(R.string.health_atlas_mammary_story_contract_caption, milk.chapters[milk.chapter(milk.entryPhase("cell-myoepithelial-cell"))].second)
    }

    @Test fun cardiacExcitationExplainsCellMotionWithoutReplacingHeartPumping() {
        val signal = HealthAtlasFunctionStory.CARDIAC_EXCITATION
        val pump = HealthAtlasFunctionStory.HEARTBEAT
        assertEquals(listOf(signal), HealthAtlasFunctionStory.choicesForId("cell-cardiomyocyte"))
        for (id in listOf("cardio", "heart", "ventricles", "tissue-cardiac-muscle")) {
            assertEquals(listOf(pump, signal), HealthAtlasFunctionStory.choicesForId(id))
        }
        assertEquals(listOf(pump), HealthAtlasFunctionStory.choicesForId("tricuspid-valve"))
        for (step in 0..2) assertEquals(0f, HealthAtlasCardiacSignalMotion.shortening(step, .75f), 0f)
        assertEquals(HealthAtlasCardiacSignalMotion.shortening(3, 1f),
            HealthAtlasCardiacSignalMotion.shortening(4, 0f), 0f)
        assertTrue(HealthAtlasCardiacSignalMotion.shortening(3, .75f) >
            HealthAtlasCardiacSignalMotion.shortening(3, .25f))
        assertTrue(HealthAtlasCardiacSignalMotion.shortening(4, .75f) <
            HealthAtlasCardiacSignalMotion.shortening(4, .25f))
    }

    @Test fun kneeMotionLinksTheMatchingJointBonesAndMusclesAndKeepsItsPoseAtCuts() {
        val story = HealthAtlasFunctionStory.KNEE_ARTICULATION
        for (id in listOf("joints", "femur", "tibia", "quadriceps-femoris", "hamstrings")) {
            assertEquals(id, story, HealthAtlasFunctionStory.forId(id))
        }
        assertEquals(listOf(HealthAtlasFunctionStory.CARTILAGE_LOAD, story),
            HealthAtlasFunctionStory.choicesForId("patella"))
        for (index in story.chapters.indices) {
            val finish = HealthAtlasKneeMotion.at(index, 1f)
            val start = HealthAtlasKneeMotion.at((index + 1) % story.chapters.size, 0f)
            assertEquals(start.bend, finish.bend, .0001f)
            assertEquals(start.extensor, finish.extensor, .0001f)
            assertEquals(start.flexor, finish.flexor, .0001f)
        }
        val flex = HealthAtlasKneeMotion.at(1, .75f)
        val extend = HealthAtlasKneeMotion.at(3, .75f)
        assertTrue(flex.flexor > flex.extensor)
        assertTrue(extend.extensor > extend.flexor)
        assertTrue(HealthAtlasKneeMotion.at(1, .75f).bend > HealthAtlasKneeMotion.at(1, .25f).bend)
        assertTrue(HealthAtlasKneeMotion.at(3, .75f).bend < HealthAtlasKneeMotion.at(3, .25f).bend)
    }

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
            "tissue-cardiac-muscle" to listOf(HealthAtlasFunctionStory.HEARTBEAT, HealthAtlasFunctionStory.CARDIAC_EXCITATION),
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
        assertEquals(HealthAtlasFunctionStory.CHONDROCYTE_MATRIX, HealthAtlasFunctionStory.forId("cell-chondrocyte"))
        assertEquals(listOf("cell-chondrocyte" to HealthAtlasFunctionStory.CHONDROCYTE_MATRIX),
            HealthAtlasFunctionStory.CARTILAGE_LOAD.relatedLessons)
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
        assertEquals(HealthAtlasFunctionStory.RED_CELL_OXYGEN, HealthAtlasFunctionStory.forId("blood"))
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
        assertEquals(HealthAtlasFunctionStory.HAIR_FOLLICLE_CYCLE, HealthAtlasFunctionStory.forId("cell-hair-matrix-cell"))
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
        assertEquals(HealthAtlasFunctionStory.URINE_ROUTE, HealthAtlasFunctionStory.forId("bladder"))
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
        assertEquals(HealthAtlasFunctionStory.CARDIAC_EXCITATION, HealthAtlasFunctionStory.forId("cell-cardiomyocyte"))
        assertEquals(HealthAtlasFunctionStory.MARROW_HEMATOPOIESIS, HealthAtlasFunctionStory.forId("bone-marrow"))
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
        assertEquals(HealthAtlasFunctionStory.SPLENIC_FILTER, HealthAtlasFunctionStory.forId("spleen"))
        assertEquals(HealthAtlasFunctionStory.T_CELL_RESPONSE, HealthAtlasFunctionStory.forId("cell-t-cell"))
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
        assertEquals(HealthAtlasFunctionStory.SEBUM_RELEASE, HealthAtlasFunctionStory.forId("sebaceous-glands"))
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
        assertEquals(HealthAtlasFunctionStory.PARATHYROID_FEEDBACK, HealthAtlasFunctionStory.forId("parathyroid-glands"))
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
        for (id in listOf("prostate", "uterus", "cell-trophoblast")) {
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
        val count = story.chapters.size
        assertTrue(count in 4..5)
        assertEquals(count, story.chapters.map { it.second }.toSet().size)
        for (i in story.chapters.indices) {
            val start = story.startOf(i)
            assertEquals(i, story.chapter(start))
            assertEquals(0f, story.fraction(start), .00001f)
            assertEquals(.5f, story.fraction(start + .5f / count), .00001f)
        }
        assertEquals(count - 1, story.chapter(1f))
        assertEquals(1f, story.fraction(1f), 0f)
        assertEquals(0f, HealthAtlasFunctionStory.safePhase(Float.NaN), 0f)
        assertEquals(0f, HealthAtlasFunctionStory.safePhase(Float.POSITIVE_INFINITY), 0f)
        assertEquals(0f, story.startOf(-1), 0f)
        assertEquals((count - 1) / count.toFloat(), story.startOf(count), 0f)
    }
}
