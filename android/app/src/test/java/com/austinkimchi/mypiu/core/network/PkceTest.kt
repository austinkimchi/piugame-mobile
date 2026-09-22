package com.austinkimchi.mypiu.core.network

import org.junit.Assert.assertEquals
import org.junit.Test

class PkceTest {
    @Test
    fun challengeMatchesRfc7636() {
        val verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", pkceChallenge(verifier))
    }
}
