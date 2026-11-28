package com.galaxyssi.chat

// Input grammar, independent of the device's display locale.
internal val teamClinicalIdentifierField = Regex(
    """(?i)(?:\b(?:MRN|patient (?:id|name)|medical record number)|患者姓名|病历号|病歷號|住院号|住院號)\s*[:：=#]\s*\S"""
)
