package com.austinkimchi.mypiu.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF176B3A),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD1F2DB),
    onPrimaryContainer = Color(0xFF082D1A),
    secondary = Color(0xFF9D342E),
    onSecondary = Color.White,
    tertiary = Color(0xFF485D92),
    background = Color(0xFFF4F7F2),
    surface = Color(0xFFFBFDF9),
    surfaceVariant = Color(0xFFE4E9E1),
    outline = Color(0xFF737A72),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF8DD5A4),
    onPrimary = Color(0xFF00391C),
    secondary = Color(0xFFFFB4AC),
    tertiary = Color(0xFFB9C7FF),
    background = Color(0xFF111411),
    surface = Color(0xFF171B17),
    surfaceVariant = Color(0xFF3F473F),
)

@Composable
fun MyPiuTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content,
    )
}
