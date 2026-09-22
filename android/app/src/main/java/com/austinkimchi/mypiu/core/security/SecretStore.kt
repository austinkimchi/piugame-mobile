package com.austinkimchi.mypiu.core.security

interface SecretStore {
    fun put(key: String, value: String)
    fun get(key: String): String?
    fun remove(key: String)
}
