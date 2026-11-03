plugins { `java-library` }

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
}

val upstream by configurations.creating
// Android otherwise selects Java's classes-directory variant, bypassing the
// merged JAR and dropping the unchanged upstream runtime classes.
val packagedRuntime by configurations.creating {
    isCanBeConsumed = true
    isCanBeResolved = false
}
val paho = "org.eclipse.paho:org.eclipse.paho.client.mqttv3:1.2.5"
dependencies {
    upstream(paho)
    compileOnly(paho)
    testImplementation("junit:junit:4.13.2")
    testCompileOnly(paho)
    testRuntimeOnly(paho)
}

// Ship one implementation of each class. Keep the original API, wire protocol,
// resources and license while replacing only the three worker lifecycle classes.
tasks.jar {
    from({ upstream.map { zipTree(it) } }) {
        exclude("org/eclipse/paho/client/mqttv3/internal/CommsCallback*.class")
        exclude("org/eclipse/paho/client/mqttv3/internal/CommsSender*.class")
        exclude("org/eclipse/paho/client/mqttv3/internal/CommsReceiver*.class")
        exclude("META-INF/MANIFEST.MF")
        exclude("META-INF/*.SF", "META-INF/*.RSA", "META-INF/*.DSA")
    }
}
artifacts.add(packagedRuntime.name, tasks.jar)
