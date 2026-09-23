package com.austinkimchi.mypiu.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.austinkimchi.mypiu.R
import com.austinkimchi.mypiu.core.model.CatalogSong
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuProfile
import com.austinkimchi.mypiu.core.model.RecentPlay
import java.text.NumberFormat
import kotlinx.serialization.json.Json

private val catalogSongJson = Json { ignoreUnknownKeys = true }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyPiuApp(
    viewModel: AppViewModel,
    catalogViewModel: CatalogViewModel,
    performanceViewModel: PerformanceViewModel,
    openAuthorization: (String) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    val catalogState by catalogViewModel.state.collectAsStateWithLifecycle()
    val performanceState by performanceViewModel.state.collectAsStateWithLifecycle()
    val performanceDashboard = performanceState.dashboard
    var destination by rememberSaveable { mutableStateOf(AppDestination.HOME) }
    var showingPumbility by rememberSaveable { mutableStateOf(false) }
    var selectedSessionId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSessionPlayId by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSongSlug by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedChartToken by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSongVersionName by rememberSaveable { mutableStateOf<String?>(null) }
    var selectedSongFallbackJson by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingDisconnection by remember { mutableStateOf<AccountDisconnection?>(null) }
    val selectedPerformanceSession = selectedSessionId?.let { selectedId ->
        performanceState.sessions.firstOrNull { session ->
            session.id == selectedId || (session.id.isBlank() && session.summary.endedAt == selectedId)
        }
    }
    val selectedSessionPlay = selectedSessionPlayId?.let { selectedId ->
        selectedPerformanceSession?.plays?.firstOrNull { it.id == selectedId }
    }
    val selectedSongFallback = remember(selectedSongFallbackJson) {
        selectedSongFallbackJson?.let { runCatching { catalogSongJson.decodeFromString<CatalogSong>(it) }.getOrNull() }
    }
    val listedSong = selectedSongSlug?.let(catalogViewModel::song)
    val selectedSong = listedSong ?: selectedSongFallback
        ?.takeIf { it.slug == selectedSongSlug }
        ?.let { fallback ->
            catalogState.detailFavoriteStates[fallback.slug]
                ?.let { fallback.copy(isFavorite = it) }
                ?: fallback
        }
    val selectedSongVersion = selectedSongVersionName?.let { savedName ->
        PiuGameVersion.entries.firstOrNull { it.serialName == savedName }
    }
    var selectedVersionReady by remember(selectedSongSlug, selectedSongVersion) {
        mutableStateOf(selectedSongSlug == null)
    }
    val isRestoringSelectedVersion = selectedSong != null &&
        (!selectedVersionReady || (selectedSongVersion != null && catalogState.version != selectedSongVersion))
    val catalogAccountId = state.account?.id ?: state.accountId
    val preferredCatalogVersion = state.account?.piuGameVersion ?: state.accountPiuGameVersion ?: state.piuVersion

    fun refreshProgress() {
        if (state.isBusy || performanceState.isLoading) return
        when {
            state.isPiuConnected -> viewModel.refresh()
            performanceState.isConnected -> performanceViewModel.refresh()
        }
    }

    fun navigateBack() {
        if (selectedSessionPlayId != null) {
            selectedSessionPlayId = null
        } else if (selectedSessionId != null) {
            selectedSessionId = null
        } else if (showingPumbility) {
            showingPumbility = false
        } else if (selectedChartToken != null) {
            selectedChartToken = null
        } else {
            selectedSongSlug = null
            selectedSongVersionName = null
            selectedSongFallbackJson = null
        }
    }

    BackHandler(
        enabled = selectedSongSlug != null || showingPumbility || selectedSessionId != null,
        onBack = ::navigateBack,
    )

    LaunchedEffect(selectedSong) {
        if (selectedSong != null) selectedSongFallbackJson = catalogSongJson.encodeToString(selectedSong)
    }
    LaunchedEffect(showingPumbility, performanceDashboard) {
        if (showingPumbility && performanceDashboard == null) showingPumbility = false
    }
    LaunchedEffect(selectedPerformanceSession) {
        if (selectedPerformanceSession == null) selectedSessionPlayId = null
    }
    LaunchedEffect(
        catalogAccountId,
        state.isMyPiuConnected,
        preferredCatalogVersion,
    ) {
        catalogViewModel.updateSession(
            accountId = catalogAccountId,
            connected = state.isMyPiuConnected,
            preferredVersion = preferredCatalogVersion,
        )
        performanceViewModel.updateSession(
            accountId = catalogAccountId,
            connected = state.isMyPiuConnected,
        )
    }
    LaunchedEffect(selectedSongSlug, selectedSongVersion, catalogState.version) {
        if (selectedSongSlug != null && selectedSongVersion != null && catalogState.version != selectedSongVersion) {
            selectedVersionReady = false
            catalogViewModel.setVersion(selectedSongVersion)
        } else {
            selectedVersionReady = true
        }
    }
    LaunchedEffect(state.isBusy) {
        if (!state.isBusy) catalogViewModel.start()
    }
    LaunchedEffect(destination, state.isBusy) {
        if (
            (destination == AppDestination.PROGRESS || destination == AppDestination.ACTIVITY) &&
            !state.isBusy
        ) {
            performanceViewModel.start()
        }
    }
    LaunchedEffect(catalogState.sessionInvalidated) {
        if (catalogState.sessionInvalidated) {
            viewModel.reconcileConnectionState()
            catalogViewModel.acknowledgeSessionInvalidation()
        }
    }
    LaunchedEffect(performanceState.sessionInvalidated) {
        if (performanceState.sessionInvalidated) {
            viewModel.reconcileConnectionState()
            performanceViewModel.acknowledgeSessionInvalidation()
        }
    }

    NavigationSuiteScaffold(
        navigationSuiteItems = {
            AppDestination.entries.forEach { item ->
                item(
                    selected = destination == item,
                    onClick = {
                        destination = item
                        selectedSongSlug = null
                        selectedChartToken = null
                        showingPumbility = false
                        selectedSessionId = null
                        selectedSessionPlayId = null
                        selectedSongVersionName = null
                        selectedSongFallbackJson = null
                    },
                    icon = {
                        Icon(
                            imageVector = when (item) {
                                AppDestination.HOME -> Icons.Default.Home
                                AppDestination.PROGRESS -> Icons.Default.PieChart
                                AppDestination.ACTIVITY -> Icons.Default.History
                                AppDestination.SONGS -> Icons.Default.MusicNote
                            },
                            contentDescription = null,
                        )
                    },
                    label = { Text(item.label) },
                )
            }
        },
    ) {
        Scaffold(
            topBar = {
            TopAppBar(
                title = {
                    Text(
                        when {
                            selectedSessionPlay != null -> selectedSessionPlay.songName
                            selectedPerformanceSession != null -> performanceSessionDayLabel(
                                selectedPerformanceSession.summary.endedAt,
                            )
                            showingPumbility -> "Pumbility"
                            selectedChartToken != null -> selectedChartToken.orEmpty()
                            selectedSong != null -> selectedSong.title
                            destination == AppDestination.SONGS -> "Songs"
                            destination == AppDestination.PROGRESS -> "Progress"
                            destination == AppDestination.ACTIVITY -> "Sessions"
                            else -> "MyPIU"
                        },
                        fontWeight = FontWeight.Black,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    if (selectedSongSlug != null || showingPumbility || selectedSessionId != null) {
                        IconButton(onClick = ::navigateBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                        }
                    } else {
                        Image(
                            painter = painterResource(R.drawable.mypiu_icon),
                            contentDescription = null,
                            modifier = Modifier.padding(start = 12.dp).size(36.dp).clip(RoundedCornerShape(6.dp)),
                        )
                    }
                },
                actions = {
                    if (
                        !showingPumbility && destination != AppDestination.ACTIVITY &&
                        (selectedSong == null || selectedChartToken != null)
                    ) {
                        IconButton(
                            onClick = {
                                when {
                                    selectedChartToken != null && selectedSong != null -> {
                                        catalogViewModel.loadChartHistory(
                                            selectedSong,
                                            selectedChartToken.orEmpty(),
                                            force = true,
                                        )
                                    }
                                    destination == AppDestination.SONGS -> catalogViewModel.refresh()
                                    destination == AppDestination.PROGRESS -> refreshProgress()
                                    destination == AppDestination.ACTIVITY -> refreshProgress()
                                    else -> viewModel.refresh()
                                }
                            },
                            enabled = when {
                                selectedChartToken != null -> {
                                    !isRestoringSelectedVersion && !catalogState.chartHistory.orDefaultLoading
                                }
                                destination == AppDestination.SONGS -> !catalogState.isLoading
                                destination == AppDestination.PROGRESS -> !state.isBusy && when {
                                    performanceState.isConnected -> !performanceState.isLoading
                                    else -> state.isPiuConnected
                                }
                                destination == AppDestination.ACTIVITY -> !state.isBusy && when {
                                    performanceState.isConnected -> !performanceState.isLoading
                                    else -> state.isPiuConnected
                                }
                                else -> state.isPiuConnected && !state.isBusy
                            },
                        ) {
                            Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                        }
                    }
                },
            )
            },
        ) { contentPadding ->
            Box(
                modifier = Modifier.fillMaxSize().padding(contentPadding),
                contentAlignment = Alignment.TopCenter,
            ) {
                when {
                destination == AppDestination.HOME -> HomeContent(
                    state = state,
                    viewModel = viewModel,
                    openAuthorization = openAuthorization,
                    onDisconnectMyPiu = { pendingDisconnection = AccountDisconnection.MYPIU },
                    onDisconnectPiuGame = { pendingDisconnection = AccountDisconnection.PIUGAME },
                )
                destination == AppDestination.PROGRESS && showingPumbility && performanceDashboard != null -> {
                    PumbilityBreakdownScreen(performanceDashboard)
                }
                destination == AppDestination.PROGRESS -> ProgressScreen(
                    state = performanceState,
                    localProfile = state.profile,
                    localRecentPlayCount = state.recentPlays.size,
                    onRefresh = ::refreshProgress,
                    onOpenPumbility = { showingPumbility = true },
                )
                destination == AppDestination.ACTIVITY && selectedSessionPlay != null -> {
                    PerformancePlayDetailScreen(
                        play = selectedSessionPlay,
                        artworkUrl = catalogViewModel.artworkUrl(selectedSessionPlay.songName),
                    )
                }
                destination == AppDestination.ACTIVITY && selectedPerformanceSession != null -> {
                    PerformanceSessionScreen(
                        session = selectedPerformanceSession,
                        onOpenPlay = { play -> selectedSessionPlayId = play.id },
                    )
                }
                destination == AppDestination.ACTIVITY -> PerformanceSessionsScreen(
                    state = performanceState,
                    onLoad = performanceViewModel::loadSession,
                    onRefresh = { performanceViewModel.loadSession(force = true) },
                    onLoadMore = performanceViewModel::loadMoreSessions,
                    artworkUrl = catalogViewModel::artworkUrl,
                    onOpenSession = { session ->
                        selectedSessionId = session.id.ifBlank { session.summary.endedAt }
                    },
                    onOpenPlay = { session, play ->
                        selectedSessionId = session.id.ifBlank { session.summary.endedAt }
                        selectedSessionPlayId = play.id
                    },
                )
                selectedSong == null -> CatalogScreen(
                    state = catalogState,
                    imageUrl = catalogViewModel::imageUrl,
                    onQueryChange = catalogViewModel::setQuery,
                    onSortChange = catalogViewModel::setSort,
                    onFeedChange = catalogViewModel::setFeed,
                    onVersionChange = catalogViewModel::setVersion,
                    onRefresh = catalogViewModel::refresh,
                    onLoadMore = catalogViewModel::loadMore,
                    onToggleFavorite = catalogViewModel::toggleFavorite,
                    onSongClick = {
                        selectedSongFallbackJson = catalogSongJson.encodeToString(it)
                        selectedSongVersionName = catalogState.version.serialName
                        selectedSongSlug = it.slug
                    },
                )
                isRestoringSelectedVersion -> CenteredProgress("Loading song")
                selectedChartToken == null -> SongDetailScreen(
                    song = selectedSong,
                    imageUrl = catalogViewModel.imageUrl(selectedSong),
                    version = catalogState.version,
                    isMyPiuConnected = catalogState.isMyPiuConnected,
                    isUpdatingFavorite = selectedSong.slug in catalogState.updatingFavorites,
                    onToggleFavorite = { catalogViewModel.toggleFavorite(selectedSong) },
                    onChartClick = { selectedChartToken = it },
                )
                else -> ChartHistoryScreen(
                    song = selectedSong,
                    chartToken = selectedChartToken.orEmpty(),
                    sessionKey = "${catalogState.cacheScope}:${catalogState.version.serialName}",
                    state = catalogState.chartHistory,
                    onLoad = { catalogViewModel.loadChartHistory(selectedSong, selectedChartToken.orEmpty()) },
                    onRetry = {
                        catalogViewModel.loadChartHistory(selectedSong, selectedChartToken.orEmpty(), force = true)
                    },
                )
                }
                if (state.isBusy) {
                    LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
                }
            }
        }
    }
    catalogState.favoriteError?.let { message ->
        AlertDialog(
            onDismissRequest = catalogViewModel::dismissFavoriteError,
            title = { Text("Couldn't update favorite") },
            text = { Text(message) },
            confirmButton = {
                TextButton(onClick = catalogViewModel::dismissFavoriteError) { Text("OK") }
            },
        )
    }
    pendingDisconnection?.let { action ->
        AlertDialog(
            onDismissRequest = { pendingDisconnection = null },
            title = { Text(action.title) },
            text = { Text(action.message) },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDisconnection = null
                        when (action) {
                            AccountDisconnection.MYPIU -> viewModel.disconnectMyPiu()
                            AccountDisconnection.PIUGAME -> viewModel.disconnectPiu()
                        }
                    },
                ) { Text(action.buttonLabel) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDisconnection = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun HomeContent(
    state: AppUiState,
    viewModel: AppViewModel,
    openAuthorization: (String) -> Unit,
    onDisconnectMyPiu: () -> Unit,
    onDisconnectPiuGame: () -> Unit,
) {
    LazyColumn(
        modifier = Modifier.fillMaxWidth().widthIn(max = 760.dp),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        item { ConnectionHeader(state) }
        state.message?.let { message -> item { StatusMessage(message) } }
        state.profile?.let { profile -> item { PlayerSummary(profile) } }
        item {
            MyPiuConnection(
                state = state,
                onAuthorize = { provider -> viewModel.authorizationUrl(provider)?.let(openAuthorization) },
                onDisconnect = onDisconnectMyPiu,
            )
        }
        item {
            PiuConnection(
                state = state,
                onConnect = viewModel::connectPiu,
                onDisconnect = onDisconnectPiuGame,
            )
        }
        if (state.recentPlays.isNotEmpty()) {
            item { SectionTitle("Recently played", "${state.recentPlays.size} plays") }
            items(state.recentPlays, key = RecentPlay::id) { play -> RecentPlayRow(play) }
        }
    }
}

private enum class AppDestination(val label: String) {
    HOME("Home"),
    ACTIVITY("Sessions"),
    PROGRESS("Progress"),
    SONGS("Songs"),
}

private enum class AccountDisconnection(
    val title: String,
    val message: String,
    val buttonLabel: String,
) {
    MYPIU(
        "Disconnect MyPIU?",
        "This signs MyPIU out on this device. Your synced data and MyPIU account remain available.",
        "Disconnect MyPIU",
    ),
    PIUGAME(
        "Disconnect PIUGAME?",
        "Saved PIUGAME credentials and on-device play data will be removed. Your PIUGAME account is not deleted.",
        "Disconnect PIUGAME",
    ),
}

private val ChartHistoryUiState?.orDefaultLoading: Boolean
    get() = this?.isLoading == true

@Composable
private fun ConnectionHeader(state: AppUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = state.profile?.displayName
                ?: state.account?.username?.takeIf { it.isNotBlank() }
                ?: "Your player dashboard",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Black,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            ConnectionBadge("MyPIU", state.isMyPiuConnected)
            ConnectionBadge("PIUGAME", state.isPiuConnected)
        }
    }
}

@Composable
private fun ConnectionBadge(label: String, connected: Boolean) {
    val container = if (connected) MaterialTheme.colorScheme.primaryContainer else MaterialTheme.colorScheme.surfaceVariant
    Surface(color = container, shape = RoundedCornerShape(6.dp)) {
        Row(
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = if (connected) Icons.Default.CheckCircle else Icons.Default.Warning,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
            Text(label, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun StatusMessage(message: String) {
    Surface(
        color = MaterialTheme.colorScheme.secondaryContainer,
        shape = RoundedCornerShape(6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(message, modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun PlayerSummary(profile: PiuProfile) {
    val metrics = listOf(
        "Pumbility" to (profile.pumbilityScore?.let { NumberFormat.getNumberInstance().format(it) } ?: "-"),
        "Rating" to (profile.rating?.let { NumberFormat.getIntegerInstance().format(it) } ?: "-"),
        "Plays" to (profile.playCount?.let { NumberFormat.getIntegerInstance().format(it) } ?: "-"),
    )
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle("Player summary", profile.titleName)
        if (LocalDensity.current.fontScale >= 1.5f) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                metrics.forEach { (label, value) -> Metric(label, value, Modifier.fillMaxWidth()) }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                metrics.forEach { (label, value) -> Metric(label, value, Modifier.weight(1f)) }
            }
        }
    }
}

@Composable
private fun Metric(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.semantics(mergeDescendants = true) {},
        tonalElevation = 1.dp,
        shape = RoundedCornerShape(6.dp),
    ) {
        Column(Modifier.padding(10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Black, maxLines = 1)
        }
    }
}

@Composable
private fun MyPiuConnection(
    state: AppUiState,
    onAuthorize: (MyPiuAuthProvider) -> Unit,
    onDisconnect: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider()
        SectionTitle("MyPIU account", state.account?.username?.takeIf { it.isNotBlank() } ?: "Username not set")
        if (state.isMyPiuConnected) {
            FilledTonalButton(onClick = onDisconnect, enabled = !state.isBusy) {
                Icon(Icons.Default.AccountCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Sign out")
            }
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MyPiuAuthProvider.entries.forEach { provider ->
                    Button(onClick = { onAuthorize(provider) }, enabled = !state.isBusy) {
                        Icon(Icons.Default.AccountCircle, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text(provider.displayName)
                    }
                }
            }
        }
    }
}

@Composable
private fun PiuConnection(
    state: AppUiState,
    onConnect: (String, String, PiuGameVersion) -> Unit,
    onDisconnect: () -> Unit,
) {
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var version by remember { mutableStateOf(PiuGameVersion.PHOENIX_2) }
    LaunchedEffect(state.isPiuConnected) {
        if (state.isPiuConnected) {
            username = ""
            password = ""
        }
    }
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        HorizontalDivider()
        SectionTitle("PIUGAME", state.profile?.username)
        if (state.isPiuConnected) {
            FilledTonalButton(onClick = onDisconnect, enabled = !state.isBusy) {
                Icon(Icons.Default.AccountCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Disconnect")
            }
        } else {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                PiuGameVersion.entries.forEachIndexed { index, candidate ->
                    SegmentedButton(
                        selected = candidate == version,
                        onClick = { version = candidate },
                        shape = SegmentedButtonDefaults.itemShape(index, PiuGameVersion.entries.size),
                        label = { Text(candidate.displayName) },
                    )
                }
            }
            OutlinedTextField(
                value = username,
                onValueChange = { username = it },
                label = { Text("PIUGAME username") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text, imeAction = ImeAction.Next),
                modifier = Modifier.fillMaxWidth(),
            )
            OutlinedTextField(
                value = password,
                onValueChange = { password = it },
                label = { Text("Password") },
                singleLine = true,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onConnect(username, password, version) },
                enabled = username.isNotBlank() && password.isNotEmpty() && !state.isBusy,
            ) {
                Icon(Icons.Default.CheckCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Connect")
            }
        }
    }
}

@Composable
private fun SectionTitle(title: String, detail: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        detail?.let {
            Text(
                it,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun RecentPlayRow(play: RecentPlay) {
    val failed = performancePlayIsFailed(play.grade, play.stageBreak)
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clearAndSetSemantics {
                contentDescription = listOf(
                    play.songName,
                    performanceChartTokenAccessibilityLabel(play.chartToken),
                    if (failed) "Failed" else play.score?.let(NumberFormat.getIntegerInstance()::format)
                        ?: "Score unavailable",
                    play.playedAt ?: "Time unavailable",
                ).joinToString()
            },
        shape = RoundedCornerShape(6.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Surface(color = MaterialTheme.colorScheme.primaryContainer, shape = RoundedCornerShape(4.dp)) {
                Text(
                    play.chartToken,
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 7.dp),
                    fontWeight = FontWeight.Black,
                )
            }
            Column(Modifier.weight(1f)) {
                Text(play.songName, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    play.playedAt ?: "Time unavailable",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            Text(
                if (failed) "FAILED" else play.score?.let(NumberFormat.getIntegerInstance()::format) ?: "-",
                color = if (failed) MaterialTheme.colorScheme.error else Color.Unspecified,
                fontWeight = FontWeight.Black,
            )
        }
    }
}
