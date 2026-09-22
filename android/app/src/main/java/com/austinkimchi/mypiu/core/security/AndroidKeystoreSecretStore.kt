package com.austinkimchi.mypiu.core.security

import android.annotation.SuppressLint
import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

@SuppressLint("UseKtx")
class AndroidKeystoreSecretStore(context: Context) : SecretStore {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    private val lock = Any()

    override fun put(key: String, value: String) = synchronized(lock) {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val encrypted = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        val payload = listOf(
            FORMAT_VERSION,
            Base64.encodeToString(cipher.iv, Base64.NO_WRAP or Base64.URL_SAFE),
            Base64.encodeToString(encrypted, Base64.NO_WRAP or Base64.URL_SAFE),
        ).joinToString(".")
        check(preferences.edit().putString(key, payload).commit()) {
            "Android could not persist encrypted app data."
        }
    }

    override fun get(key: String): String? = synchronized(lock) {
        val payload = preferences.getString(key, null) ?: return null
        val parts = payload.split('.', limit = 3)
        check(parts.size == 3 && parts[0] == FORMAT_VERSION) {
            "Encrypted app data has an unsupported format."
        }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        val iv = Base64.decode(parts[1], Base64.NO_WRAP or Base64.URL_SAFE)
        val encrypted = Base64.decode(parts[2], Base64.NO_WRAP or Base64.URL_SAFE)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        String(cipher.doFinal(encrypted), Charsets.UTF_8)
    }

    override fun remove(key: String) = synchronized(lock) {
        check(preferences.edit().remove(key).commit()) {
            "Android could not remove encrypted app data."
        }
    }

    private fun secretKey(): SecretKey {
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setRandomizedEncryptionRequired(true)
                    .build(),
            )
            generateKey()
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "com.austinkimchi.mypiu.secrets.v1"
        const val PREFERENCES_NAME = "encrypted_secrets"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val FORMAT_VERSION = "v1"
        const val GCM_TAG_BITS = 128
    }
}
