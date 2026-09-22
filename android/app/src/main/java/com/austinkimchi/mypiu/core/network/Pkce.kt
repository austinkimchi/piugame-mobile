package com.austinkimchi.mypiu.core.network

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64

internal fun pkceChallenge(verifier: String): String = Base64.getUrlEncoder()
    .withoutPadding()
    .encodeToString(
        MessageDigest.getInstance("SHA-256")
            .digest(verifier.toByteArray(StandardCharsets.US_ASCII)),
    )
