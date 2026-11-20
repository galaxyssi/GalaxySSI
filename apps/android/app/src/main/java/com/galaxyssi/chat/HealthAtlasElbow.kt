package com.galaxyssi.chat

/** Horizontal forearm in static equilibrium, not a patient-specific strength model. */
internal object HealthAtlasElbow {
    const val GRAVITY = 9.8
    const val ARM_MASS = 2.5
    const val ARM_CENTRE_METRES = .16
    data class Forces(val loadWeight: Double, val armWeight: Double, val muscle: Double,
        val jointDown: Double, val torque: Double, val loadArmMetres: Double, val muscleArmMetres: Double)

    fun forces(loadKg: Double, loadArmCm: Double, muscleArmMm: Double): Forces {
        require(loadKg.isFinite() && loadKg in 0.0..10.0)
        require(loadArmCm.isFinite() && loadArmCm in 20.0..50.0)
        require(muscleArmMm.isFinite() && muscleArmMm in 20.0..60.0)
        val loadWeight = loadKg * GRAVITY
        val armWeight = ARM_MASS * GRAVITY
        val loadArm = loadArmCm / 100.0
        val muscleArm = muscleArmMm / 1000.0
        val torque = loadWeight * loadArm + armWeight * ARM_CENTRE_METRES
        val muscle = torque / muscleArm
        return Forces(loadWeight, armWeight, muscle, muscle - loadWeight - armWeight, torque, loadArm, muscleArm)
    }
}
