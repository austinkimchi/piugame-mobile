package com.austinkimchi.mypiu

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import com.austinkimchi.mypiu.ui.AppViewModel
import com.austinkimchi.mypiu.ui.MyPiuApp
import com.austinkimchi.mypiu.ui.theme.MyPiuTheme

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels {
        AppViewModel.Factory((application as MyPIUApplication).container)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MyPiuTheme {
                MyPiuApp(
                    viewModel = viewModel,
                    openAuthorization = { url ->
                        CustomTabsIntent.Builder().build().launchUrl(this, url.toUri())
                    },
                )
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val callback = intent.dataString
            ?.takeIf { it.startsWith("mypiu://oauth/callback") }
            ?: return
        intent.data = null
        setIntent(intent)
        viewModel.handleOAuthCallback(callback)
    }
}
