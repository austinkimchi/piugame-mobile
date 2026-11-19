package com.austinkimchi.mypiu.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.austinkimchi.mypiu.core.model.JudgmentCounts
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceSession
import com.austinkimchi.mypiu.core.model.RecentPlay
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

private enum class ActivitySection(val label: String) {
    RECENT("Recent"),
    BEST("Best"),
}

@Composable
fun ActivityScreen(
    state: PerformanceUiState,
    localRecentPlays: List<RecentPlay>,
    onRefresh: () -> Unit,
    onOpenSession: () -> Unit,
) {
    val dashboard = state.dashboard
    var section by rememberSaveable { mutableStateOf(ActivitySection.RECENT) }

    when {
        state.isLoading && dashboard == null -> CenteredActivityProgress("Loading activity")
        dashboard == null && localRecentPlays.isNotEmpty() -> LocalActivityList(localRecentPlays, state.error)
        dashboard == null -> ActivityUnavailable(state.isConnected, state.error, onRefresh)
        else -> LazyColumn(
            modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        ) {
            item {
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
                    ActivitySection.entries.forEachIndexed { index, item ->
                        SegmentedButton(
                            selected = section == item,
                            onClick = { section = item },
                            shape = SegmentedButtonDefaults.itemShape(index, ActivitySection.entries.size),
                            label = { Text(item.label) },
                        )
                    }
                }
            }
            state.error?.let { message ->
                item {
                    ActivityError(message, onRefresh, Modifier.padding(bottom = 12.dp))
                }
            }
            if (section == ActivitySection.RECENT) {
                item {
                    FilledTonalButton(
                        onClick = onOpenSession,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp),
                    ) {
                        Icon(Icons.Default.History, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Recent session")
                    }
                }
                if (dashboard.recentPlays.isEmpty()) {
                    item { EmptyActivity("No recent plays") }
                } else {
                    itemsIndexed(dashboard.recentPlays, key = { _, play -> play.id }) { index, play ->
                        PerformancePlayRow(play)
                        if (index < dashboard.recentPlays.lastIndex) HorizontalDivider()
                    }
                }
            } else if (dashboard.topCharts.isEmpty()) {
                item { EmptyActivity("No chart bests") }
            } else {
                itemsIndexed(dashboard.topCharts, key = { _, chart -> chart.id }) { index, chart ->
                    PerformanceChartRow(chart)
                    if (index < dashboard.topCharts.lastIndex) HorizontalDivider()
                }
            }
        }
    }
}

@Composable
private fun LocalActivityList(plays: List<RecentPlay>, error: String?) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
    ) {
        item {
            Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text("Recently played", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(
                    "On-device PIUGAME snapshot",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        error?.let { message ->
            item {
                Text(
                    message,
                    modifier = Modifier.padding(bottom = 12.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
        itemsIndexed(plays, key = { _, play -> play.id }) { index, play ->
            LocalPerformancePlayRow(play)
            if (index < plays.lastIndex) HorizontalDivider()
        }
    }
}

@Composable
fun PerformanceSessionsScreen(
    state: PerformanceUiState,
    onLoad: () -> Unit,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    artworkUrl: (String) -> String?,
    onOpenSession: (MyPiuPerformanceSession) -> Unit,
    onOpenPlay: (MyPiuPerformanceSession, MyPiuPerformanceDashboard.Play) -> Unit,
) {
    LaunchedEffect(state.accountScope) { onLoad() }

    when {
        !state.isConnected -> ActivityUnavailable(connected = false, message = null, onRefresh = onRefresh)
        state.sessions.isEmpty() && !state.isSessionLoaded && state.sessionError == null -> {
            CenteredActivityProgress("Loading sessions")
        }
        state.sessions.isEmpty() && !state.isSessionLoaded && state.sessionError != null -> ActivityUnavailable(
            connected = true,
            message = state.sessionError,
            onRefresh = onRefresh,
            title = "Sessions unavailable",
        )
        else -> LazyColumn(
            modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        ) {
            state.sessionSavedAtEpochMillis?.let { savedAt ->
                item {
                    Text("Saved history from ${java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT).format(java.util.Date(savedAt))}",
                        style = MaterialTheme.typography.bodySmall)
                }
            }
            if (state.isSessionLoading) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text("Updating sessions")
                    }
                }
            }
            state.sessionError?.let { message ->
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Couldn’t update sessions. Showing the last loaded history.")
                        Text(message, style = MaterialTheme.typography.bodySmall)
                        Button(onClick = onRefresh) { Text("Try Again") }
                    }
                }
            }
            if (state.sessions.isEmpty()) {
                item { EmptyActivity("No sessions yet", Modifier.fillMaxWidth()) }
            }
            itemsIndexed(
                state.sessions,
                key = { index, session -> session.id.ifBlank { "${session.summary.endedAt}:$index" } },
            ) { index, session ->
                SessionRow(
                    session = session,
                    artworkUrl = artworkUrl,
                    onClick = { onOpenSession(session) },
                    onOpenPlay = { play -> onOpenPlay(session, play) },
                )
                if (index < state.sessions.lastIndex) HorizontalDivider()
                if (index >= state.sessions.lastIndex - 3 && state.nextSessionOffset != null) {
                    LaunchedEffect(state.nextSessionOffset, state.isSessionLoading, state.sessionPaginationError) {
                        if (!state.isSessionLoading && !state.isSessionLoadingMore && state.sessionPaginationError == null) {
                            onLoadMore()
                        }
                    }
                }
            }
            if (state.isSessionLoadingMore) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(20.dp),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        CircularProgressIndicator()
                    }
                }
            } else if (state.sessionPaginationError != null) {
                item {
                    Button(onClick = onLoadMore, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp)) {
                        Icon(Icons.Default.Refresh, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Retry loading more")
                    }
                }
            }
        }
    }
}

@Composable
fun PerformanceSessionScreen(
    session: MyPiuPerformanceSession,
    onOpenPlay: (MyPiuPerformanceDashboard.Play) -> Unit,
) {
    val summary = session.summary
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 860.dp),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
    ) {
        session.arcadeName?.takeIf(String::isNotBlank)?.let { arcadeName ->
            item {
                Text(
                    "Location · $arcadeName",
                    modifier = Modifier.padding(vertical = 8.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        item {
            Text(
                "Summary",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 16.dp, bottom = 6.dp),
            )
        }
        item { SessionClearSummaryRow(summary) }
        item { SessionSummaryRow("Average score", formatActivityInteger(summary.averageScore)) }
        item { SessionSummaryRow("Best score", formatActivityInteger(summary.bestScore)) }
        item { SessionSummaryRow("Unique charts", formatActivityInteger(summary.distinctCharts)) }
        item { SessionSummaryRow("Duration", durationLabel(summary.durationMinutes)) }
        item {
            Text(
                "Plays (${sessionModeSummary(session.plays)})",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(top = 22.dp, bottom = 6.dp),
            )
        }
        if (session.plays.isEmpty()) {
            item { EmptyActivity("No plays in this session") }
        } else {
            itemsIndexed(session.plays, key = { _, play -> play.id }) { index, play ->
                PerformancePlayRow(play, onClick = { onOpenPlay(play) })
                if (index < session.plays.lastIndex) HorizontalDivider()
            }
        }
    }
}

@Composable
private fun SessionRow(
    session: MyPiuPerformanceSession,
    artworkUrl: (String) -> String?,
    onClick: () -> Unit,
    onOpenPlay: (MyPiuPerformanceDashboard.Play) -> Unit,
) {
    val summary = session.summary
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 7.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(sessionTimestampLabel(summary.endedAt), fontWeight = FontWeight.Bold)
            session.arcadeName?.takeIf(String::isNotBlank)?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "Clear ${summary.clearCount}/${summary.playCount}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "(${formatPercent(summary.clearRate)})",
                    style = MaterialTheme.typography.bodySmall,
                    color = clearRateColor(summary.clearRate) ?: MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "· ${sessionModeSummary(session.plays)}",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(session.plays, key = { it.id }) { play ->
                SessionPlayArtwork(
                    play = play,
                    artworkUrl = artworkUrl(play.songName),
                    onClick = { onOpenPlay(play) },
                )
            }
        }
    }
}

@Composable
private fun SessionPlayArtwork(
    play: MyPiuPerformanceDashboard.Play,
    artworkUrl: String?,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier.width(56.dp).clickable(onClick = onClick).semantics(mergeDescendants = true) {},
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SongArtwork(play.songImageUrl ?: artworkUrl, Modifier.size(56.dp))
        Text(
            play.displayChartToken,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Bold,
            maxLines = 1,
        )
    }
}

@Composable
private fun SessionClearSummaryRow(summary: MyPiuPerformanceSession.Summary) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("Clear", modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text("${summary.clearCount}/${summary.playCount} (", fontWeight = FontWeight.Bold)
        Text(
            formatPercent(summary.clearRate),
            fontWeight = FontWeight.Bold,
            color = clearRateColor(summary.clearRate) ?: MaterialTheme.colorScheme.onSurface,
        )
        Text(")", fontWeight = FontWeight.Bold)
    }
    HorizontalDivider()
}

@Composable
private fun SessionSummaryRow(title: String, value: String, valueColor: Color? = null) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Bold, color = valueColor ?: MaterialTheme.colorScheme.onSurface)
    }
    HorizontalDivider()
}

@Composable
private fun PerformancePlayRow(
    play: MyPiuPerformanceDashboard.Play,
    onClick: (() -> Unit)? = null,
) {
    val failed = performancePlayIsFailed(play.grade, play.stageBreak)
    val grade = performanceGradeLabel(play.grade)
    val score = if (failed) "FAILED" else formatActivityInteger(play.score)
    val clickModifier = onClick?.let { Modifier.clickable(onClick = it) } ?: Modifier
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(clickModifier)
            .padding(vertical = 10.dp)
            .clearAndSetSemantics {
                contentDescription = listOf(
                    play.songName,
                    performanceChartTokenAccessibilityLabel(play.displayChartToken),
                    grade,
                    score,
                    performanceDateLabel(play.playedAt),
                ).joinToString()
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(play.songName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                "$grade / ${performanceDateLabel(play.playedAt)}",
                style = MaterialTheme.typography.bodySmall,
                color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            ChartTokenBadge(play.displayChartToken)
            Text(
                score,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
fun PerformancePlayDetailScreen(
    play: MyPiuPerformanceDashboard.Play,
    artworkUrl: String? = null,
) {
    val failed = performancePlayIsFailed(play.grade, play.stageBreak)
    val score = if (failed) "FAILED" else formatActivityInteger(play.score)
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 720.dp),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item {
            Row(
                verticalAlignment = Alignment.Top,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                SongArtwork(play.songImageUrl ?: artworkUrl, Modifier.size(96.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    Text(play.songName, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Black)
                    ChartTokenBadge(play.displayChartToken)
                    Text(
                        performanceDateLabel(play.playedAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        item {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                tonalElevation = 1.dp,
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("RESULT", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(
                        score,
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Black,
                        color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
                    )
                    Text(performanceGradeLabel(play.grade), style = MaterialTheme.typography.labelLarge)
                }
            }
        }
        play.judgments?.let { judgments ->
            item {
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(8.dp),
                    tonalElevation = 1.dp,
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("JUDGMENTS", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        JudgmentBreakdown(judgments)
                    }
                }
            }
        }
    }
}

@Composable
private fun JudgmentBreakdown(judgments: JudgmentCounts) {
    val values = listOf(
        "Perfect" to judgments.perfect,
        "Great" to judgments.great,
        "Good" to judgments.good,
        "Bad" to judgments.bad,
        "Miss" to judgments.miss,
    ).filter { it.second != null }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        values.forEach { (label, value) ->
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(formatActivityInteger(value), fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun LocalPerformancePlayRow(play: RecentPlay) {
    val failed = performancePlayIsFailed(play.grade, play.stageBreak)
    val grade = performanceGradeLabel(play.grade)
    val score = if (failed) "FAILED" else formatActivityInteger(play.score)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .clearAndSetSemantics {
                contentDescription = listOf(
                    play.songName,
                    performanceChartTokenAccessibilityLabel(play.chartToken),
                    grade,
                    score,
                    play.playedAt ?: "Time unavailable",
                ).joinToString()
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(play.songName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                "$grade / ${play.playedAt ?: "Time unavailable"}",
                style = MaterialTheme.typography.bodySmall,
                color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            ChartTokenBadge(play.chartToken)
            Text(
                score,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Bold,
                color = if (failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}

@Composable
private fun PerformanceChartRow(chart: MyPiuPerformanceDashboard.Chart) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .clearAndSetSemantics {
                contentDescription = listOfNotNull(
                    chart.songName,
                    chart.topPlayRank?.let { "Rank $it" },
                    performanceChartTokenAccessibilityLabel(chart.displayChartToken),
                    performanceGradeLabel(chart.bestGrade),
                    formatActivityInteger(chart.bestScore),
                    chart.delta?.takeIf { it > 0 }?.let { "Improved by ${formatActivityInteger(it)}" },
                ).joinToString()
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        chart.topPlayRank?.let {
            Text("#$it", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(chart.songName, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    performanceGradeLabel(chart.bestGrade),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                chart.delta?.takeIf { it > 0 }?.let {
                    Text(
                        "+${formatActivityInteger(it)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(5.dp)) {
            ChartTokenBadge(chart.displayChartToken)
            Text(formatActivityInteger(chart.bestScore), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun ChartTokenBadge(token: String) {
    Surface(color = MaterialTheme.colorScheme.inverseSurface, shape = RoundedCornerShape(4.dp)) {
        Text(
            token,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 4.dp),
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold,
            color = MaterialTheme.colorScheme.inverseOnSurface,
        )
    }
}

@Composable
private fun CenteredActivityProgress(label: String) {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator()
        Text(label, modifier = Modifier.padding(top = 12.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ActivityUnavailable(
    connected: Boolean,
    message: String?,
    onRefresh: () -> Unit,
    title: String = if (connected) "Activity unavailable" else "Connect MyPIU",
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(
            message ?: if (connected) "Refresh to load your activity." else "Connect your account from Home to see activity.",
            modifier = Modifier.padding(top = 8.dp),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (connected) {
            Button(onClick = onRefresh, modifier = Modifier.padding(top = 16.dp)) {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Try again")
            }
        }
    }
}

@Composable
private fun ActivityError(message: String, onRefresh: () -> Unit, modifier: Modifier = Modifier) {
    Surface(modifier = modifier, color = MaterialTheme.colorScheme.errorContainer, shape = RoundedCornerShape(8.dp)) {
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

@Composable
private fun EmptyActivity(message: String, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Default.History, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(message, modifier = Modifier.padding(top = 10.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

internal fun performanceGradeLabel(value: String?): String {
    var grade = value?.trim()?.lowercase().orEmpty()
    if (grade.startsWith("x_")) grade = grade.removePrefix("x_")
    if (grade.isEmpty()) return "Played"
    val isPlus = grade.endsWith("_p")
    if (isPlus) grade = grade.removeSuffix("_p")
    return grade.replace('_', ' ').uppercase() + if (isPlus) "+" else ""
}

internal fun performancePlayIsFailed(grade: String?, stageBreak: Boolean): Boolean =
    stageBreak || grade?.trim()?.lowercase()?.startsWith("x_") == true

internal fun performanceChartTokenAccessibilityLabel(token: String): String {
    val normalized = token.trim().uppercase()
    val prefix = normalized.firstOrNull() ?: return token
    var level = normalized.drop(1)
    val isPlus = level.endsWith('+')
    if (isPlus) level = level.dropLast(1)
    if (level.isEmpty() || level.any { !it.isDigit() }) return token
    val spokenLevel = level + if (isPlus) " plus" else ""
    return when (prefix) {
        'S' -> "Single level $spokenLevel"
        'D' -> "Double level $spokenLevel"
        'C' -> "Co-op level $spokenLevel"
        else -> token
    }
}

internal fun performanceDateLabel(value: String?): String {
    if (value == null) return "Time unavailable"
    return runCatching {
        DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
            .format(Instant.parse(value).atZone(ZoneId.systemDefault()))
    }.getOrDefault(value)
}

internal fun performanceSessionDayLabel(value: String): String = runCatching {
    DateTimeFormatter.ofPattern("MMM d, yyyy")
        .format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault("Session")

private fun sessionTimestampLabel(value: String): String = runCatching {
    DateTimeFormatter.ofPattern("MMM d, h:mm a")
        .format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)

private fun sessionModeSummary(plays: List<MyPiuPerformanceDashboard.Play>): String {
    val counts = plays.groupingBy { play ->
        when (play.mode?.trim()?.lowercase()?.firstOrNull()) {
            's' -> "single"
            'd' -> "double"
            'c' -> "co-op"
            else -> "other"
        }
    }.eachCount()
    val order = listOf("single", "double", "co-op", "other")
    return order.mapNotNull { mode ->
        counts[mode]?.takeIf { it > 0 }?.let { count ->
            val label = when {
                mode == "co-op" || mode == "other" -> mode
                count == 1 -> mode
                else -> "${mode}s"
            }
            "$count $label"
        }
    }.joinToString().ifEmpty { "0 plays" }
}

private fun formatActivityInteger(value: Int?): String = value?.let(NumberFormat.getIntegerInstance()::format) ?: "-"

private fun formatPercent(value: Double?): String = value?.let {
    "${NumberFormat.getNumberInstance().apply { maximumFractionDigits = 0 }.format(it)}%"
} ?: "-"

private fun durationLabel(minutes: Int): String {
    val safeMinutes = minutes.coerceAtLeast(0)
    val hours = safeMinutes / 60
    val remainingMinutes = safeMinutes % 60
    return when {
        hours == 0 -> "$remainingMinutes min"
        remainingMinutes == 0 -> "$hours hr"
        else -> "$hours hr $remainingMinutes min"
    }
}

@Composable
private fun clearRateColor(value: Double?): Color? = when {
    value == null -> null
    value >= 80 -> MaterialTheme.colorScheme.primary
    value < 50 -> MaterialTheme.colorScheme.error
    else -> MaterialTheme.colorScheme.tertiary
}
