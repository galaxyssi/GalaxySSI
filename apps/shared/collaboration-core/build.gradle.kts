plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin {
    compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
}
java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

// Android supplies org.json. The headless adapter's implementation is not published to App.
val replay by sourceSets.creating
dependencies {
    compileOnly("org.json:json:20250517")
    add(replay.implementationConfigurationName, sourceSets.main.get().output)
    add(replay.implementationConfigurationName, "org.json:json:20250517")
    testImplementation(replay.output)
    testImplementation("org.json:json:20250517")
    testImplementation("junit:junit:4.13.2")
}

tasks.register<JavaExec>("replay") {
    group = "verification"
    description = "Replay workflow selection/materialization from JSON stdin; does not execute agents."
    classpath = replay.runtimeClasspath
    mainClass.set("com.galaxyssi.collaboration.WorkflowReplayKt")
    standardInput = System.`in`
}
