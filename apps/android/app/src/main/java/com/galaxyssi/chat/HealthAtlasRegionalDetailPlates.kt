package com.galaxyssi.chat

internal object HealthAtlasRegionalDetailPlates {
    val all = HealthAtlasOpticsDetailPlates.all + HealthAtlasKidneyRegionalPlates.all +
        HealthAtlasGallbladderAndSalivaryPlates.all + HealthAtlasUrinaryOutflowPlates.all +
        HealthAtlasCardiacOutflowPlates.all + HealthAtlasUpperAirwayBifurcationsPlates.all +
        HealthAtlasHearingBalancePlates.all + HealthAtlasNeuralRegionalPlates.all +
        HealthAtlasLongBoneAndShoulderPlates.all
    private val byOwner = all.associateBy { it.owner }

    fun forId(id: String?) = byOwner[id]
}
