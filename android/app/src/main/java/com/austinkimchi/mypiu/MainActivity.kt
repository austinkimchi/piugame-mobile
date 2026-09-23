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
import com.austinkimchi.mypiu.ui.CatalogViewModel
import com.austinkimchi.mypiu.ui.MyPiuApp
import com.austinkimchi.mypiu.ui.PerformanceViewModel
import com.austinkimchi.mypiu.ui.theme.MyPiuTheme

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels {
        AppViewModel.Factory(
            container = (application as MyPIUApplication).container,
            restoreOnInit = intent.myPiuOAuthCallback() == null,
        )
    }
    private val catalogViewModel: CatalogViewModel by viewModels {
        CatalogViewModel.Factory((application as MyPIUApplication).container)
    }
    private val performanceViewModel: PerformanceViewModel by viewModels {
        PerformanceViewModel.Factory((application as MyPIUApplication).container)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MyPiuTheme {
                MyPiuApp(
                    viewModel = viewModel,
                    catalogViewModel = catalogViewModel,
                    performanceViewModel = performanceViewModel,
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

    override fun onResume() {
        super.onResume()
        performanceViewModel.onAppResumed()
    }

    private fun handleIntent(intent: Intent) {
        val callback = intent.myPiuOAuthCallback() ?: return
        intent.data = null
        setIntent(intent)
        viewModel.handleOAuthCallback(callback)
    }
}

private fun Intent.myPiuOAuthCallback(): String? {
    val uri = data ?: return null
    return uri.toString().takeIf {
        uri.scheme == "mypiu" && uri.host == "oauth" && uri.path == "/callback"
    }
}
