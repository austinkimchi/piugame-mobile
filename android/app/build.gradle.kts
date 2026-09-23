plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val configuredVersionCode = providers.environmentVariable("MYPIU_VERSION_CODE").orNull?.trim()
val releaseVersionCode = configuredVersionCode?.toIntOrNull()?.takeIf { it in 1..2_100_000_000 }
    ?: if (configuredVersionCode == null) 1 else throw GradleException("MYPIU_VERSION_CODE must be between 1 and 2100000000")
val configuredVersionName = providers.environmentVariable("MYPIU_VERSION_NAME").orNull?.trim()
val releaseVersionName = configuredVersionName?.takeIf { it.isNotEmpty() }
    ?: if (configuredVersionName == null) "0.1.0" else throw GradleException("MYPIU_VERSION_NAME must not be blank")

val uploadStoreFile = providers.environmentVariable("MYPIU_UPLOAD_STORE_FILE").orNull?.trim()
val uploadStorePassword = providers.environmentVariable("MYPIU_UPLOAD_STORE_PASSWORD").orNull
val uploadKeyAlias = providers.environmentVariable("MYPIU_UPLOAD_KEY_ALIAS").orNull?.trim()
val uploadKeyPassword = providers.environmentVariable("MYPIU_UPLOAD_KEY_PASSWORD").orNull
val uploadSigningValues = listOf(uploadStoreFile, uploadStorePassword, uploadKeyAlias, uploadKeyPassword)
val configuredUploadSigningValues = uploadSigningValues.count { !it.isNullOrBlank() }

if (configuredUploadSigningValues !in listOf(0, uploadSigningValues.size)) {
    throw GradleException("Release signing requires all MYPIU_UPLOAD_* environment variables")
}

val hasUploadSigning = configuredUploadSigningValues == uploadSigningValues.size

android {
    namespace = "com.austinkimchi.mypiu"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.austinkimchi.mypiu"
        minSdk = 26
        targetSdk = 37
        versionCode = releaseVersionCode
        versionName = releaseVersionName

        buildConfigField("String", "MYPIU_BASE_URL", "\"https://mypiu.austin.kim\"")
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    signingConfigs {
        if (hasUploadSigning) {
            create("upload") {
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (hasUploadSigning) {
                signingConfig = signingConfigs.getByName("upload")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")

    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("androidx.browser:browser:1.10.0")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-adaptive-navigation-suite")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.core:core-ktx:1.19.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.11.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.11.0")
    implementation("androidx.work:work-runtime:2.11.2")
    implementation("io.coil-kt.coil3:coil-compose:3.3.0")
    implementation("io.coil-kt.coil3:coil-network-okhttp:3.3.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.0")
    implementation("com.squareup.okhttp3:okhttp-java-net-cookiejar:5.5.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("org.jsoup:jsoup:1.23.2")

    debugImplementation("androidx.compose.ui:ui-tooling")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
