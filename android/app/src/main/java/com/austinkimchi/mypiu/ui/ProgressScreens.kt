package com.austinkimchi.mypiu.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.TrendingUp
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.PerformanceProgressSummary
import com.austinkimchi.mypiu.core.model.PiuProfile
import java.text.NumberFormat

@Composable
fun ProgressScreen(
    state: PerformanceUiState,
    localProfile: PiuProfile?,
    localRecentPlayCount: Int,
    onRefresh: () -> Unit,
    onOpenPumbility: () -> Unit,
) {
    val performance = state.dashboard
    val profile = performance?.profile
    when {
        profile != null -> PerformanceProgressContent(
            performance = performance,
            profile = profile,
            isLoading = state.isLoading,
            error = state.error,
            onRefresh = onRefresh,
            onOpenPumbility = onOpenPumbility,
        )
        localProfile != null -> SnapshotProgressContent(
            profile = localProfile,
            recentPlayCount = localRecentPlayCount,
            isLoading = state.isLoading,
            error = state.error,
            onRefresh = onRefresh,
        )
        state.isLoading -> CenteredProgress("Loading progress")
        else -> ProgressUnavailable(
            connected = state.isConnected,
            error = state.error,
            onRefresh = onRefresh,
        )
    }
}

@Composable
private fun PerformanceProgressContent(
    performance: MyPiuPerformanceDashboard,
    profile: MyPiuPerformanceDashboard.Profile,
    isLoading: Boolean,
    error: String?,
    onRefresh: () -> Unit,
    onOpenPumbility: () -> Unit,
) {
    val summary = PerformanceProgressSummary.from(profile)
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        if (isLoading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        error?.let { message -> item { ProgressError(message, onRefresh) } }
        item { CompletionPanel(summary, profile.displayName) }
        item {
            ProgressSection("Score health") {
                MetricGrid(
                    listOf(
                        ProgressMetric(
                            "Pumbility",
                            formatDecimal(profile.pumbilityScore),
                            changeLabel(performance.totals.pumbilityChange24Hours),
                            Icons.AutoMirrored.Filled.TrendingUp,
                            MaterialTheme.colorScheme.tertiary,
                        ),
                        ProgressMetric(
                            "Average best",
                            formatInteger(performance.totals.averageBestScore),
                            changeLabel(performance.totals.averageBestScoreChange24Hours),
                            Icons.Default.BarChart,
                            MaterialTheme.colorScheme.primary,
                        ),
                    ),
                )
                OutlinedButton(onClick = onOpenPumbility, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.AutoMirrored.Filled.List, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Pumbility breakdown")
                }
            }
        }
        item {
            ProgressSection("Momentum") {
                MetricGrid(
                    listOf(
                        ProgressMetric("Today", formatInteger(performance.totals.upscoresToday), "Upscored charts", Icons.Default.Bolt, MaterialTheme.colorScheme.secondary),
                        ProgressMetric("This week", formatInteger(performance.totals.upscoresThisWeek), "Upscored charts", Icons.Default.CalendarMonth, MaterialTheme.colorScheme.primary),
                        ProgressMetric("This month", formatInteger(performance.totals.upscoresThisMonth), "Upscored charts", Icons.Default.CalendarMonth, MaterialTheme.colorScheme.tertiary),
                        ProgressMetric("All time", formatInteger(performance.totals.upscores), "Upscored charts", Icons.Default.EmojiEvents, MaterialTheme.colorScheme.tertiary),
                    ),
                )
            }
        }
        item {
            ProgressSection("Coverage") {
                MetricGrid(
                    listOf(
                        ProgressMetric("Tracked charts", formatInteger(performance.totals.trackedCharts), "Saved chart bests", Icons.Default.Layers, MaterialTheme.colorScheme.primary),
                        ProgressMetric("Recent plays", formatInteger(performance.totals.trackedPlays), "Stored attempts", Icons.Default.History, MaterialTheme.colorScheme.secondary),
                        ProgressMetric("Play count", formatInteger(summary.playCount), "PIUGAME total", Icons.AutoMirrored.Filled.DirectionsRun, MaterialTheme.colorScheme.tertiary),
                        ProgressMetric("Recent session", formatInteger(performance.totals.recentlyPlayed), "Plays", Icons.Default.PlayCircle, MaterialTheme.colorScheme.secondary),
                    ),
                )
            }
        }
    }
}

@Composable
private fun SnapshotProgressContent(
    profile: PiuProfile,
    recentPlayCount: Int,
    isLoading: Boolean,
    error: String?,
    onRefresh: () -> Unit,
) {
    val summary = PerformanceProgressSummary.from(profile)
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        if (isLoading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        error?.let { message -> item { ProgressError(message, onRefresh) } }
        item { CompletionPanel(summary, profile.displayName) }
        item {
            ProgressSection("On-device snapshot") {
                MetricGrid(
                    listOf(
                        ProgressMetric("Pumbility", formatDecimal(profile.pumbilityScore), null, Icons.AutoMirrored.Filled.TrendingUp, MaterialTheme.colorScheme.tertiary),
                        ProgressMetric("Rating", formatInteger(profile.rating), null, Icons.Default.BarChart, MaterialTheme.colorScheme.primary),
                        ProgressMetric("Play count", formatInteger(summary.playCount), null, Icons.AutoMirrored.Filled.DirectionsRun, MaterialTheme.colorScheme.tertiary),
                        ProgressMetric("Recent plays", formatInteger(recentPlayCount), "On this device", Icons.Default.History, MaterialTheme.colorScheme.secondary),
                    ),
                )
            }
        }
    }
}

@Composable
private fun CompletionPanel(summary: PerformanceProgressSummary, displayName: String) {
    Surface(
        modifier = Modifier.fillMaxWidth().semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(8.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(displayName, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text("Chart completion", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Text(formatPercent(summary.completionPercent), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                if (summary.clearedCharts != null && summary.totalCharts != null) {
                    Text(
                        "${formatInteger(summary.clearedCharts)} / ${formatInteger(summary.totalCharts)}",
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            summary.completionFraction?.let { fraction ->
                LinearProgressIndicator(progress = { fraction }, modifier = Modifier.fillMaxWidth())
            }
            summary.remainingCharts?.let { remaining ->
                Text(
                    "${formatInteger(remaining)} charts remaining",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun ProgressSection(title: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        content()
    }
}

@Composable
private fun MetricGrid(metrics: List<ProgressMetric>) {
    val fontScale = LocalDensity.current.fontScale
    BoxWithConstraints {
        val columnCount = if (maxWidth >= 520.dp && fontScale < 1.5f) 2 else 1
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            metrics.chunked(columnCount).forEach { rowMetrics ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    rowMetrics.forEach { metric -> MetricTile(metric, Modifier.weight(1f)) }
                    repeat(columnCount - rowMetrics.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun MetricTile(metric: ProgressMetric, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.heightIn(min = 112.dp).semantics(mergeDescendants = true) {},
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        shape = RoundedCornerShape(8.dp),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(metric.icon, contentDescription = null, tint = metric.tint, modifier = Modifier.size(20.dp))
            Text(metric.value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Black)
            Text(metric.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            metric.detail?.let {
                Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
fun PumbilityBreakdownScreen(performance: MyPiuPerformanceDashboard) {
    val charts = remember(performance.topCharts) {
        performance.topCharts
            .filter { it.topPumbilityScore != null }
            .sortedBy { it.topPlayRank ?: Int.MAX_VALUE }
    }
    val contribution = remember(charts) { charts.sumOf { it.topPumbilityScore ?: 0.0 } }
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            MetricGrid(
                listOf(
                    ProgressMetric("Pumbility", formatDecimal(performance.profile?.pumbilityScore), null, Icons.AutoMirrored.Filled.TrendingUp, MaterialTheme.colorScheme.tertiary),
                    ProgressMetric("Chart total", formatDecimal(contribution), null, Icons.Default.BarChart, MaterialTheme.colorScheme.primary),
                ),
            )
        }
        item { Text("Contributing charts", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold) }
        if (charts.isEmpty()) {
            item { Text("No Pumbility charts are available yet.", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            itemsIndexed(charts, key = { _, chart -> chart.id }) { index, chart ->
                PumbilityChartRow(chart)
                if (index < charts.lastIndex) HorizontalDivider()
            }
        }
    }
}

@Composable
private fun PumbilityChartRow(chart: MyPiuPerformanceDashboard.Chart) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            chart.topPlayRank?.let { "#$it" } ?: "-",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.width(34.dp),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(chart.songName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(chart.displayChartToken, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(formatDecimal(chart.topPumbilityScore), fontWeight = FontWeight.Black)
            Text(formatInteger(chart.bestScore), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ProgressUnavailable(connected: Boolean, error: String?, onRefresh: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            if (connected) "Progress unavailable" else "Connect MyPIU or PIUGAME",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
        )
        Text(
            error ?: if (connected) {
                "Refresh your performance to load progress."
            } else {
                "Connect an account from Home to start tracking progress."
            },
            modifier = Modifier.padding(top = 8.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (connected) {
            Button(onClick = onRefresh, modifier = Modifier.padding(top = 16.dp)) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Retry")
            }
        }
    }
}

@Composable
private fun ProgressError(message: String, onRefresh: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.errorContainer, shape = RoundedCornerShape(8.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(message, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onErrorContainer)
            OutlinedButton(onClick = onRefresh) { Text("Retry") }
        }
    }
}

private data class ProgressMetric(
    val title: String,
    val value: String,
    val detail: String?,
    val icon: ImageVector,
    val tint: Color,
)

private fun formatInteger(value: Int?): String = value?.let(NumberFormat.getIntegerInstance()::format) ?: "-"

private fun formatDecimal(value: Double?): String = value?.let {
    NumberFormat.getNumberInstance().apply { maximumFractionDigits = 2 }.format(it)
} ?: "-"

private fun formatPercent(value: Double?): String = value?.let {
    "${NumberFormat.getNumberInstance().apply { maximumFractionDigits = 1 }.format(it)}%"
} ?: "-"

private fun changeLabel(value: Double?): String? = value?.let {
    "${if (it >= 0) "+" else ""}${formatDecimal(it)} / 24h"
}
