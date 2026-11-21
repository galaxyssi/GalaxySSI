package com.galaxyssi.chat

internal object HealthAtlasRegionalDetailPlates {
    val all = HealthAtlasOpticsDetailPlates.all + HealthAtlasKidneyRegionalPlates.all +
        HealthAtlasGallbladderAndSalivaryPlates.all + HealthAtlasUrinaryOutflowPlates.all +
        HealthAtlasCardiacOutflowPlates.all + HealthAtlasUpperAirwayBifurcationsPlates.all +
        HealthAtlasHearingBalancePlates.all + HealthAtlasNeuralRegionalPlates.all +
        HealthAtlasLongBoneAndShoulderPlates.all + HealthAtlasSkinLayersDetailPlates.all +
        HealthAtlasHeartChamberDetailPlates.all + HealthAtlasHeartValveDetailPlates.all +
        HealthAtlasOuterSensoryDetailPlates.all + HealthAtlasNephronStructureDetailPlates.all +
        HealthAtlasNeuralConnectionDetailPlates.all + HealthAtlasReproductiveAnatomyDetailPlates.all +
        HealthAtlasMajorMuscleDetailPlates.all + HealthAtlasLimbBoneDetailPlates.all +
        HealthAtlasSternumAndHandDetailPlates.all + HealthAtlasCardiacComparisonDetailPlates.all +
        HealthAtlasVascularInterfaceDetailPlates.all + HealthAtlasRenalOutletDetailPlates.all +
        HealthAtlasMaleDuctRouteDetailPlates.all + HealthAtlasAirwayDiaphragmDetailPlates.all +
        HealthAtlasDigestiveDuctDetailPlates.all + HealthAtlasPosteriorMuscleTendonDetailPlates.all +
        HealthAtlasPelvicSoftTissueDetailPlates.all
    private val byOwner = all.associateBy { it.owner }

    fun forId(id: String?) = byOwner[id]
}
