package com.austinkimchi.mypiu.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.Star
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.SubcomposeAsyncImage
import com.austinkimchi.mypiu.BuildConfig
import com.austinkimchi.mypiu.core.model.CatalogChartMode
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.JudgmentCounts
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.SongChartPerformance
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CatalogScreen(
    state: CatalogUiState,
    imageUrl: (CatalogSong) -> String?,
    onQueryChange: (String) -> Unit,
    onFeedChange: (CatalogFeed) -> Unit,
    onVersionChange: (PiuGameVersion) -> Unit,
    onRefresh: () -> Unit,
    onLoadMore: () -> Unit,
    onToggleFavorite: (CatalogSong) -> Unit,
    onSongClick: (CatalogSong) -> Unit,
) {
    val focusManager = LocalFocusManager.current
    Column(
        modifier = Modifier.fillMaxSize().widthIn(max = 900.dp),
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                CatalogFeed.entries.forEachIndexed { index, feed ->
                    SegmentedButton(
                        selected = state.feed == feed,
                        onClick = { onFeedChange(feed) },
                        enabled = !feed.requiresAccount || state.isMyPiuConnected,
                        shape = SegmentedButtonDefaults.itemShape(index, CatalogFeed.entries.size),
                        label = { Text(feed.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    )
                }
            }
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                PiuGameVersion.entries.forEachIndexed { index, version ->
                    SegmentedButton(
                        selected = state.version == version,
                        onClick = { onVersionChange(version) },
                        shape = SegmentedButtonDefaults.itemShape(index, PiuGameVersion.entries.size),
                        label = { Text(version.displayName) },
                    )
                }
            }
            if (state.feed == CatalogFeed.CATALOG) {
                OutlinedTextField(
                    value = state.query,
                    onValueChange = onQueryChange,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    label = { Text("Search songs") },
                    leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                    trailingIcon = {
                        if (state.query.isNotEmpty()) {
                            IconButton(onClick = { onQueryChange("") }) {
                                Icon(Icons.Default.Clear, contentDescription = "Clear search")
                            }
                        }
                    },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus() }),
                )
            }
        }

        if (state.isLoading && state.listing.songs.isNotEmpty()) {
            LinearProgressIndicator(Modifier.fillMaxWidth())
        }

        when {
            state.isLoading && state.listing.songs.isEmpty() -> CenteredProgress("Loading songs")
            state.error != null && state.listing.songs.isEmpty() -> CatalogMessage(
                title = "Catalog unavailable",
                message = state.error,
                actionLabel = "Try again",
                onAction = onRefresh,
            )
            state.listing.songs.isEmpty() -> CatalogMessage(
                title = when (state.feed) {
                    CatalogFeed.CATALOG -> "No songs found"
                    CatalogFeed.RECOMMENDATIONS -> "No recommendations yet"
                    CatalogFeed.FAVORITES -> "No favorite songs"
                },
                message = when {
                    state.isShowingCachedData -> "No matching songs are available in the offline cache."
                    state.feed == CatalogFeed.RECOMMENDATIONS -> "Sync more plays to build recommendations."
                    state.feed == CatalogFeed.FAVORITES -> "Favorite songs will appear here."
                    else -> "Try a different search."
                },
                actionLabel = null,
                onAction = null,
            )
            else -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 20.dp),
            ) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "${NumberFormat.getIntegerInstance().format(state.listing.total)} ${state.feed.label.lowercase()}",
                            style = MaterialTheme.typography.labelLarge,
                            modifier = Modifier.weight(1f),
                        )
                        if (state.isShowingCachedData) {
                            Text(
                                "OFFLINE",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.secondary,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }
                itemsIndexed(state.listing.songs, key = { _, song -> song.slug }) { index, song ->
                    CatalogSongRow(
                        song = song,
                        imageUrl = imageUrl(song),
                        canFavorite = state.isMyPiuConnected,
                        isUpdatingFavorite = song.slug in state.updatingFavorites,
                        onClick = { onSongClick(song) },
                        onToggleFavorite = { onToggleFavorite(song) },
                    )
                    HorizontalDivider(Modifier.padding(start = 104.dp))
                    if (index >= state.listing.songs.lastIndex - 4 && state.listing.nextCursor != null) {
                        LaunchedEffect(state.listing.nextCursor) { onLoadMore() }
                    }
                }
                if (state.isLoadingMore) {
                    item {
                        Box(Modifier.fillMaxWidth().height(64.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(Modifier.size(28.dp))
                        }
                    }
                } else if (state.paginationError != null) {
                    item {
                        Button(onClick = onLoadMore, modifier = Modifier.padding(16.dp).fillMaxWidth()) {
                            Icon(Icons.Default.Refresh, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Retry loading more")
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CatalogSongRow(
    song: CatalogSong,
    imageUrl: String?,
    canFavorite: Boolean,
    isUpdatingFavorite: Boolean,
    onClick: () -> Unit,
    onToggleFavorite: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        SongArtwork(imageUrl, Modifier.size(76.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    song.title,
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (song.isPremium) {
                    Icon(
                        Icons.Default.EmojiEvents,
                        contentDescription = "Premium",
                        tint = Color(0xFFC28719),
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
            Text(
                song.artist,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            song.recommendedChartToken?.let {
                Text(
                    "Recommended $it",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }
            Text(
                song.chartSummary.take(7).joinToString("  "),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (canFavorite) {
            IconButton(onClick = onToggleFavorite, enabled = !isUpdatingFavorite) {
                if (isUpdatingFavorite) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                } else {
                    Icon(
                        imageVector = if (song.isFavorite) Icons.Default.Star else Icons.Outlined.Star,
                        contentDescription = if (song.isFavorite) "Remove from favorites" else "Add to favorites",
                        tint = if (song.isFavorite) Color(0xFFC28719) else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
fun SongDetailScreen(
    song: CatalogSong,
    imageUrl: String?,
    version: PiuGameVersion,
    isMyPiuConnected: Boolean,
    isUpdatingFavorite: Boolean,
    onToggleFavorite: () -> Unit,
    onChartClick: (String) -> Unit,
) {
    val uriHandler = LocalUriHandler.current
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 760.dp),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                SongArtwork(
                    imageUrl,
                    Modifier.fillMaxWidth().widthIn(max = 260.dp).aspectRatio(1f).align(Alignment.CenterHorizontally),
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        song.title,
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.Black,
                        modifier = Modifier.weight(1f),
                    )
                    if (song.isPremium) {
                        Icon(Icons.Default.EmojiEvents, contentDescription = "Premium", tint = Color(0xFFC28719))
                    }
                    Spacer(Modifier.weight(1f))
                    if (isMyPiuConnected) {
                        IconButton(onClick = onToggleFavorite, enabled = !isUpdatingFavorite) {
                            if (isUpdatingFavorite) {
                                CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(
                                    if (song.isFavorite) Icons.Default.Star else Icons.Outlined.Star,
                                    contentDescription = if (song.isFavorite) "Remove from favorites" else "Add to favorites",
                                    tint = if (song.isFavorite) Color(0xFFC28719) else MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
                Text(
                    song.artist,
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        item {
            Column {
                song.bpm?.let { MetadataRow(Icons.Default.Speed, "BPM", it) }
                song.folder?.let { MetadataRow(Icons.Default.Folder, "Folder", it) }
                song.series?.let { MetadataRow(Icons.Default.Layers, "Series", it) }
            }
        }

        item {
            Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                Text("Charts", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                CatalogChartMode.entries.forEach { mode ->
                    val charts = song.charts(mode)
                    if (charts.isNotEmpty()) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                mode.title,
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                charts.forEach { token ->
                                    ChartBadge(
                                        token = token,
                                        isRecommended = song.recommendedChartToken.equals(token, ignoreCase = true),
                                        enabled = isMyPiuConnected,
                                        onClick = { onChartClick(token) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if (song.tags.isNotEmpty()) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text("Tags", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(song.tags.joinToString(" · "), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        item {
            Button(
                onClick = { uriHandler.openUri("${BuildConfig.MYPIU_BASE_URL}/songs/${song.slug}") },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Icon(Icons.Default.OpenInBrowser, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Open on MyPIU")
            }
        }
    }
}

@Composable
private fun MetadataRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(label, modifier = Modifier.weight(0.4f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, modifier = Modifier.weight(0.6f), fontWeight = FontWeight.SemiBold, textAlign = TextAlign.End)
    }
    HorizontalDivider()
}

@Composable
private fun ChartBadge(token: String, isRecommended: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val color = when (token.firstOrNull()?.uppercaseChar()) {
        'S' -> MaterialTheme.colorScheme.primary
        'D' -> MaterialTheme.colorScheme.tertiary
        else -> MaterialTheme.colorScheme.secondary
    }
    Surface(
        modifier = Modifier
            .widthIn(min = 64.dp)
            .height(48.dp)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        shape = RoundedCornerShape(6.dp),
        color = color,
        border = if (isRecommended) BorderStroke(3.dp, Color(0xFFFFC247)) else null,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(token, color = Color.White, fontWeight = FontWeight.Black)
        }
    }
}

@Composable
fun ChartHistoryScreen(
    song: CatalogSong,
    chartToken: String,
    sessionKey: String,
    state: ChartHistoryUiState?,
    onLoad: () -> Unit,
    onRetry: () -> Unit,
) {
    LaunchedEffect(song.slug, chartToken, sessionKey) { onLoad() }
    when {
        state == null || state.songSlug != song.slug || state.chartToken != chartToken || state.isLoading -> {
            CenteredProgress("Loading chart history")
        }
        state.error != null -> CatalogMessage(
            title = "History unavailable",
            message = state.error,
            actionLabel = "Try again",
            onAction = onRetry,
        )
        state.performance == null -> CatalogMessage(
            title = "No tracked plays",
            message = "No attempts have been synced for this chart.",
            actionLabel = null,
            onAction = null,
        )
        else -> ChartHistoryList(song, chartToken, state.performance)
    }
}

@Composable
private fun ChartHistoryList(song: CatalogSong, chartToken: String, performance: SongChartPerformance) {
    LazyColumn(
        modifier = Modifier.fillMaxSize().widthIn(max = 760.dp),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ChartBadge(chartToken, isRecommended = false, enabled = false, onClick = {})
                Column {
                    Text(song.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text(song.artist, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        performance.stats?.let { stats ->
            item {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Summary", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    SummaryRow("Best score", scoreLabel(stats.bestScore))
                    SummaryRow(
                        "Latest score",
                        if (performance.latestPlay?.isFailed == true || stats.latestStageBreak) "FAILED" else scoreLabel(stats.latestScore),
                    )
                    SummaryRow("Tracked attempts", NumberFormat.getIntegerInstance().format(stats.recentPlayCount))
                    SummaryRow("Stage breaks", NumberFormat.getIntegerInstance().format(stats.stageBreakCount))
                }
            }
        }
        item {
            Text("Attempts", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        if (performance.history.isEmpty()) {
            item { Text("No recent attempts", color = MaterialTheme.colorScheme.onSurfaceVariant) }
        } else {
            items(performance.history.asReversed(), key = SongChartPerformance.Attempt::id) { attempt ->
                AttemptRow(attempt)
                HorizontalDivider()
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(label, modifier = Modifier.weight(1f), color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun AttemptRow(attempt: SongChartPerformance.Attempt) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f)) {
                Text(gradeLabel(attempt.grade), fontWeight = FontWeight.Bold)
                Text(
                    dateLabel(attempt.playedAt),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                if (attempt.isFailed) "FAILED" else scoreLabel(attempt.score),
                fontWeight = FontWeight.Black,
                color = if (attempt.isFailed) MaterialTheme.colorScheme.secondary else Color.Unspecified,
            )
        }
        JudgmentRow(attempt.judgments)
    }
}

@Composable
private fun JudgmentRow(judgments: JudgmentCounts) {
    val values = listOf(
        "Perfect" to judgments.perfect,
        "Great" to judgments.great,
        "Good" to judgments.good,
        "Bad" to judgments.bad,
        "Miss" to judgments.miss,
    ).filter { it.second != null }
    if (values.isEmpty()) return
    FlowRow(horizontalArrangement = Arrangement.spacedBy(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        values.forEach { (label, value) ->
            Column {
                Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(NumberFormat.getIntegerInstance().format(value), style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun SongArtwork(url: String?, modifier: Modifier) {
    Box(
        modifier = modifier.clip(RoundedCornerShape(6.dp)).background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        if (url == null) {
            Icon(Icons.Default.MusicNote, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                loading = { CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) },
                error = {
                    Icon(Icons.Default.MusicNote, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
                },
            )
        }
    }
}

@Composable
private fun CenteredProgress(label: String) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
            CircularProgressIndicator()
            Text(label, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun CatalogMessage(
    title: String,
    message: String,
    actionLabel: String?,
    onAction: (() -> Unit)?,
) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
        Column(
            modifier = Modifier.widthIn(max = 420.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(message, color = MaterialTheme.colorScheme.onSurfaceVariant, textAlign = TextAlign.Center)
            if (actionLabel != null && onAction != null) {
                Button(onClick = onAction) {
                    Icon(Icons.Default.Refresh, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text(actionLabel)
                }
            }
        }
    }
}

private val SongChartPerformance.Attempt.isFailed: Boolean
    get() = stageBreak || grade?.trim()?.lowercase()?.startsWith("x_") == true

private fun gradeLabel(value: String?): String {
    var grade = value?.trim()?.lowercase().orEmpty()
    if (grade.startsWith("x_")) grade = grade.removePrefix("x_")
    if (grade.isEmpty()) return "Played"
    val isPlus = grade.endsWith("_p")
    if (isPlus) grade = grade.removeSuffix("_p")
    return grade.replace('_', ' ').uppercase() + if (isPlus) "+" else ""
}

private fun scoreLabel(value: Int?): String = value?.let(NumberFormat.getIntegerInstance()::format) ?: "-"

private fun dateLabel(value: String?): String {
    if (value == null) return "Time unavailable"
    val instant = runCatching { Instant.parse(value) }.getOrNull() ?: return value
    return DateTimeFormatter.ofPattern("MMM d, yyyy, h:mm a")
        .withZone(ZoneId.systemDefault())
        .format(instant)
}
