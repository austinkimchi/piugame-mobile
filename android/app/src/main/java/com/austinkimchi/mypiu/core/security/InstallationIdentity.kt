package com.austinkimchi.mypiu.core.security

import android.annotation.SuppressLint
import android.content.Context
import java.util.UUID

@SuppressLint("UseKtx")
class InstallationIdentity(context: Context) {
    private val preferences = context.getSharedPreferences("installation", Context.MODE_PRIVATE)

    fun current(): String {
        preferences.getString(KEY, null)?.let { return it }
        val identifier = UUID.randomUUID().toString()
        check(preferences.edit().putString(KEY, identifier).commit()) {
            "Android could not persist the installation identity."
        }
        return identifier
    }

    private companion object {
        const val KEY = "installation_id"
    }
}
