plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "jp.jphacks.astera"
    compileSdk = 35
    defaultConfig {
        applicationId = "jp.jphacks.astera"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildTypes { release { isMinifyEnabled = false } }
}
dependencies {
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.core:core-ktx:1.16.0")
}
val bundleWeb by tasks.registering(Sync::class) {
    from("../web/dist")
    into("src/main/assets/web")
    doFirst { require(file("../web/dist/index.html").exists()) { "先に Android/web で npm ci && npm run build を実行してください" } }
}
tasks.named("preBuild") { dependsOn(bundleWeb) }
