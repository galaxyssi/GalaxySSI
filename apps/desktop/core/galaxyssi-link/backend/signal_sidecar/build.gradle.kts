plugins {
    application
}

dependencies {
    implementation("org.signal:libsignal-client:0.86.5")
    implementation("org.json:json:20250517")
    implementation("org.xerial:sqlite-jdbc:3.53.4.0")
}

application {
    mainClass.set("com.galaxyssi.link.SignalSidecar")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

tasks.register<JavaExec>("verifySignalConcurrency") {
    classpath = sourceSets.main.get().runtimeClasspath
    mainClass.set("com.galaxyssi.link.SignalConcurrencyProbe")
}

tasks.register<JavaExec>("verifySignalAtomicReceive") {
    classpath = sourceSets.main.get().runtimeClasspath
    mainClass.set("com.galaxyssi.link.SignalAtomicReceiveProbe")
}
