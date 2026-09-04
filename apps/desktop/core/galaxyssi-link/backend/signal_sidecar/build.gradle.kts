plugins {
    application
}

dependencies {
    implementation("org.signal:libsignal-client:0.86.5")
    implementation("org.json:json:20250517")
}

application {
    mainClass.set("com.galaxyssi.link.SignalSidecar")
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
