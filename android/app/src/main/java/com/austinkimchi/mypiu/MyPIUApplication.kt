package com.austinkimchi.mypiu

import android.app.Application

class MyPIUApplication : Application() {
    val container: AppContainer by lazy { AppContainer(this) }
}
