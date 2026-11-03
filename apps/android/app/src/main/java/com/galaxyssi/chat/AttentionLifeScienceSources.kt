package com.galaxyssi.chat

/** Independent discovery facets avoid requiring every biological term in the same news story. */
internal object AttentionLifeScienceSources {
    const val TOPIC = "protein_life_sciences"
    val feeds = listOf(
        "https://www.ipd.uw.edu/feed/",
        "https://news.mit.edu/rss/topic/biology-and-genetics",
        "https://journals.plos.org/plosbiology/feed/atom",
        "https://www.nature.com/nsmb.rss",
        "https://www.nature.com/ncb.rss",
        "https://www.nature.com/ng.rss",
        "https://www.nature.com/nrd.rss",
        "https://www.nature.com/nchembio.rss",
        "https://www.nature.com/nbt.rss",
        "https://journals.plos.org/plosgenetics/feed/atom",
        "https://journals.plos.org/ploscompbiol/feed/atom",
        "https://news.mit.edu/rss/topic/drug-discovery",
        "https://elifesciences.org/rss/recent.xml",
        "https://rss.arxiv.org/rss/q-bio.BM",
        "https://rss.arxiv.org/rss/q-bio"
    )
    val queries = listOf(
        "\"protein structure\" OR \"protein folding\" OR enzymes",
        "\"protein design\" OR RFdiffusion OR ProteinMPNN",
        "\"cell biology\" OR organelles OR \"stem cells\"",
        "\"drug discovery\" OR \"drug design\" OR \"molecular docking\"",
        "genomics OR \"DNA repair\" OR CRISPR",
        "\"RNA biology\" OR mRNA OR ribosomes",
        "\"synthetic biology\" OR \"metabolic engineering\"",
        "\"structural biology\" OR \"cryo-EM\" OR proteomics",
        "biochemistry OR metabolism OR \"cell signaling\"",
        "immunology OR vaccines OR immunotherapy",
        "microbiology OR microbiome OR bacteriology",
        "\"developmental biology\" OR organoids OR \"regenerative medicine\"",
        "\"gene therapy\" OR \"genetic engineering\" OR \"genome editing\"",
        "\"cancer biology\" OR \"targeted therapy\" OR \"tumor biology\"",
        "neuroscience OR neurobiology OR synapses",
        "pharmacogenomics OR pharmacokinetics OR \"biologic medicines\""
    )
    private val words = listOf("proteins?", "enzymes?", "peptides?", "antibod(?:y|ies)", "proteomics",
        "biology", "biological", "biotechnology", "biochemistry", "biomolecular", "biomolecules?",
        "organelle[s]?", "mitochondri[a-z]*", "ribosomes?", "stem cells?", "cell biology", "cell therapy",
        "drug (?:design|discovery|development)", "molecular docking", "therapeutics?", "pharmacology",
        "DNA", "RNA", "mRNA", "tRNA", "rRNA", "siRNA", "microRNA", "genom(?:e|es|ics)",
        "genetics?", "genes?", "CRISPR", "transcriptomics", "epigenetics", "synthetic biology",
        "metabolic engineering", "AlphaFold", "RFdiffusion", "ProteinMPNN", "cryo-EM",
        "metabolism", "cell signall?ing", "immunology", "vaccines?", "immunotherapy", "microbiology",
        "microbiomes?", "bacteriology", "organoids?", "regenerative medicine", "gene therapy", "genetic engineering",
        "genome editing", "cancer biology", "targeted therapy", "tumou?r biology", "neuroscience", "neurobiology",
        "synapses?", "pharmacogenomics", "pharmacokinetics", "biologic medicines?")
    private val english = Regex("\\b(?:" + words.joinToString("|") + ")\\b", RegexOption.IGNORE_CASE)
    private val chinese = listOf("\u86cb\u767d", "\u751f\u7269", "\u751f\u547d\u79d1\u5b66", "\u9176",
        "\u591a\u80bd", "\u6297\u4f53", "\u7ec6\u80de", "\u7ebf\u7c92\u4f53", "\u6838\u7cd6\u4f53", "\u57fa\u56e0",
        "\u6838\u9178", "\u9057\u4f20", "\u8f6c\u5f55", "\u836f\u7269\u8bbe\u8ba1", "\u836f\u7269\u53d1\u73b0",
        "\u65b0\u836f\u7814\u53d1", "\u51b7\u51bb\u7535\u955c", "\u5206\u5b50\u5bf9\u63a5",
        "\u514d\u75ab", "\u75ab\u82d7", "\u5fae\u751f\u7269", "\u83cc\u7fa4", "\u80bf\u7624", "\u518d\u751f\u533b\u5b66",
        "\u795e\u7ecf\u79d1\u5b66", "\u4ee3\u8c22", "\u836f\u7406", "\u7c7b\u5668\u5b98", "\u9776\u5411\u6cbb\u7597")

    fun matches(text: String) = english.containsMatchIn(text) || chinese.any { text.contains(it, ignoreCase = true) }
}
