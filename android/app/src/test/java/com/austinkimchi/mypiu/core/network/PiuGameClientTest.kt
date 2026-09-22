package com.austinkimchi.mypiu.core.network

import org.junit.Assert.assertThrows
import org.junit.Test

class PiuGameClientTest {
    @Test
    fun acceptsAuthenticatedProfileMarkup() {
        validateAuthenticatedProfile("<main class='subProfile_wrap'></main>")
    }

    @Test
    fun identifiesLoginFormAsDefinitiveAuthenticationFailure() {
        val html = """
            <form action="/bbs/login_check.php">
              <input name="mb_id">
              <input name="mb_password" type="password">
            </form>
        """.trimIndent()

        assertThrows(PiuGameException.AuthenticationFailed::class.java) {
            validateAuthenticatedProfile(html)
        }
    }

    @Test
    fun treatsUnrecognizedMarkupAsTransientInvalidResponse() {
        val html = "<html><title>Temporarily unavailable</title><body>Maintenance</body></html>"

        assertThrows(PiuGameException.InvalidResponse::class.java) {
            validateAuthenticatedProfile(html)
        }
    }
}
