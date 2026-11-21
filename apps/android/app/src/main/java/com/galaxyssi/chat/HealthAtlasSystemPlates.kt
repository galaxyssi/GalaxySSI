package com.galaxyssi.chat

/** Composite plates depict selected structures, never individual cells or a shared anatomical plane. */
internal object HealthAtlasSystemPlates {
    private const val BOOK = "https://openstax.org/books/anatomy-and-physiology-2e/pages/"
    private val sensory = HealthAtlasPlate(R.drawable.health_atlas_system_sensory, "sensory",
        R.string.health_atlas_view_system_sensory, listOf(
            HealthAtlasMarker("eye", .24f, .26f), HealthAtlasMarker("ear", .71f, .24f),
            HealthAtlasMarker("nose", .14f, .79f), HealthAtlasMarker("tongue", .76f, .73f)),
        BOOK + "14-1-sensory-perception")
    private val respiratory = HealthAtlasPlate(R.drawable.health_atlas_system_respiratory, "respiratory",
        R.string.health_atlas_view_system_respiratory, listOf(
            HealthAtlasMarker("nasal-cavity", .42f, .15f), HealthAtlasMarker("pharynx", .52f, .23f),
            HealthAtlasMarker("larynx", .489f, .353f), HealthAtlasMarker("trachea", .49f, .45f),
            HealthAtlasMarker("lungs", .68f, .64f), HealthAtlasMarker("diaphragm", .51f, .83f)),
        BOOK + "22-1-organs-and-structures-of-the-respiratory-system")
    private val digestive = HealthAtlasPlate(R.drawable.health_atlas_system_digestive, "digestive",
        R.string.health_atlas_view_system_digestive, listOf(
            HealthAtlasMarker("parotid-glands", .60f, .18f), HealthAtlasMarker("sublingual-glands", .38f, .30f),
            HealthAtlasMarker("submandibular-glands", .51f, .33f), HealthAtlasMarker("liver", .42f, .49f),
            HealthAtlasMarker("gallbladder", .35f, .63f), HealthAtlasMarker("pancreas", .63f, .73f)),
        BOOK + "23-1-overview-of-the-digestive-system")
    private val endocrine = HealthAtlasPlate(R.drawable.health_atlas_system_endocrine, "endocrine",
        R.string.health_atlas_view_system_endocrine, listOf(
            HealthAtlasMarker("pituitary-gland", .23f, .42f), HealthAtlasMarker("thyroid-gland", .81f, .31f),
            HealthAtlasMarker("adrenal-glands", .37f, .58f), HealthAtlasMarker("pancreas", .71f, .71f)),
        BOOK + "17-1-an-overview-of-the-endocrine-system")
    private val immune = HealthAtlasPlate(R.drawable.health_atlas_system_immune, "immune",
        R.string.health_atlas_view_system_immune, listOf(
            HealthAtlasMarker("thymus", .285f, .20f), HealthAtlasMarker("spleen", .82f, .33f),
            HealthAtlasMarker("lymph-nodes", .28f, .70f), HealthAtlasMarker("bone-marrow", .70f, .76f)),
        BOOK + "21-1-anatomy-of-the-lymphatic-and-immune-systems")
    private val skin = HealthAtlasPlate(R.drawable.health_atlas_system_skin, "skin",
        R.string.health_atlas_view_system_skin, listOf(
            HealthAtlasMarker("epidermis", .32f, .34f), HealthAtlasMarker("dermis", .51f, .46f),
            HealthAtlasMarker("sebaceous-glands", .43f, .53f), HealthAtlasMarker("hair-follicles", .325f, .58f),
            HealthAtlasMarker("sweat-glands", .60f, .67f), HealthAtlasMarker("subcutaneous-tissue", .47f, .84f)),
        BOOK + "5-1-layers-of-the-skin")

    private fun marker(id: String, x: Int, y: Int, height: Int = 560) = HealthAtlasMarker(id, x / 420f, y / height.toFloat())

    private val nervous = HealthAtlasPlate(R.drawable.health_atlas_system_nervous, "nervous",
        R.string.health_atlas_view_system_nervous, listOf(
            marker("brain", 203, 61), marker("spinal-cord", 210, 132),
            marker("spinal-nerves", 159, 214), marker("ganglia", 221, 264),
            marker("peripheral-nerves", 245, 496)),
        BOOK + "12-1-basic-structure-and-function-of-the-nervous-system")
    private val cardio = HealthAtlasPlate(R.drawable.health_atlas_system_cardio, "cardio",
        R.string.health_atlas_view_system_cardio, listOf(
            marker("aorta", 243, 164), marker("lungs", 269, 229), marker("pulmonary-trunk", 211, 193),
            marker("heart", 228, 235), marker("veins", 198, 288), marker("capillaries", 181, 526)),
        BOOK + "20-5-circulatory-pathways")
    private val testicular = HealthAtlasPlate(R.drawable.health_atlas_system_testicular, "male",
        R.string.health_atlas_view_system_testicular, listOf(
            marker("vas-deferens", 155, 105, 400), marker("seminal-vesicles", 271, 169, 400),
            marker("prostate", 218, 194, 400), marker("ejaculatory-ducts", 234, 209, 400),
            marker("testes", 178, 325, 400), marker("epididymis", 213, 327, 400)),
        BOOK + "27-1-anatomy-and-physiology-of-the-testicular-reproductive-system")
    private val ovarian = HealthAtlasPlate(R.drawable.health_atlas_system_ovarian, "female",
        R.string.health_atlas_view_system_ovarian, listOf(
            marker("uterine-tubes", 301, 106, 400), marker("ovaries", 320, 171, 400),
            marker("uterus", 241, 185, 400), marker("endometrium", 182, 155, 400),
            marker("cervix", 210, 266, 400), marker("vagina", 215, 326, 400)),
        BOOK + "27-2-anatomy-and-physiology-of-the-ovarian-reproductive-system")

    val all = listOf(sensory, respiratory, digestive, endocrine, immune, skin, nervous, cardio, testicular, ovarian)

    // Existing dedicated organ plates take precedence in HealthAtlasPlates.forId.
    fun forId(id: String): HealthAtlasPlate? = when (id) {
        "sensory", "eye", "ear", "nose", "tongue" -> sensory
        "respiratory", "nasal-cavity", "pharynx", "larynx", "diaphragm" -> respiratory
        "digestive", "salivary-glands", "parotid-glands", "submandibular-glands", "sublingual-glands" -> digestive
        "endocrine", "pituitary-gland", "thyroid-gland", "adrenal-glands" -> endocrine
        "immune", "thymus", "spleen", "lymph-nodes", "bone-marrow" -> immune
        "skin", "skin-organ", "epidermis", "dermis", "subcutaneous-tissue", "sebaceous-glands",
        "hair-follicles", "sweat-glands" -> skin
        "nervous", "spinal-cord", "spinal-nerves", "ganglia", "peripheral-nerves" -> nervous
        "cardio", "veins", "capillaries" -> cardio
        "male", "testes", "epididymis", "vas-deferens", "seminal-vesicles", "ejaculatory-ducts", "prostate" -> testicular
        "female", "ovaries", "uterine-tubes", "uterus", "endometrium", "cervix", "vagina" -> ovarian
        else -> null
    }
}
