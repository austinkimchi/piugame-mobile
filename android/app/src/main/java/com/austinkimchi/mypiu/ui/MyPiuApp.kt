package com.austinkimchi.mypiu.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Warning
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
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.austinkimchi.mypiu.R
import com.austinkimchi.mypiu.core.model.MyPiuAuthProvider
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import com.austinkimchi.mypiu.core.model.PiuProfile
import com.austinkimchi.mypiu.core.model.RecentPlay
import java.text.NumberFormat

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MyPiuApp(
    viewModel: AppViewModel,
    openAuthorization: (String) -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("MyPIU", fontWeight = FontWeight.Black) },
                navigationIcon = {
                    Image(
                        painter = painterResource(R.drawable.mypiu_icon),
                        contentDescription = null,
                        modifier = Modifier.padding(start = 12.dp).size(36.dp).clip(RoundedCornerShape(6.dp)),
                    )
                },
                actions = {
                    IconButton(
                        onClick = viewModel::refresh,
                        enabled = state.isPiuConnected && !state.isBusy,
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "Sync now")
                    }
                },
            )
        },
    ) { contentPadding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(contentPadding),
            contentAlignment = Alignment.TopCenter,
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().widthIn(max = 760.dp),
                contentPadding = PaddingValues(horizontal = 20.dp, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                item {
                    ConnectionHeader(state)
                }
                state.message?.let { message ->
                    item { StatusMessage(message) }
                }
                state.profile?.let { profile ->
                    item { PlayerSummary(profile) }
                }
                item {
                    MyPiuConnection(
                        state = state,
                        onAuthorize = { provider ->
                            viewModel.authorizationUrl(provider)?.let(openAuthorization)
                        },
                        onDisconnect = viewModel::disconnectMyPiu,
                    )
                }
                item {
                    PiuConnection(
                        state = state,
                        onConnect = viewModel::connectPiu,
                        onDisconnect = viewModel::disconnectPiu,
                    )
                }
                if (state.recentPlays.isNotEmpty()) {
                    item {
                        SectionTitle("Recently played", "${state.recentPlays.size} plays")
                    }
                    items(state.recentPlays, key = RecentPlay::id) { play -> RecentPlayRow(play) }
                }
            }
            if (state.isBusy) {
                LinearProgressIndicator(Modifier.fillMaxWidth().align(Alignment.TopCenter))
            }
        }
    }
}

@Composable
private fun ConnectionHeader(state: AppUiState) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(
            text = state.profile?.displayName ?: state.account?.name ?: "Your player dashboard",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Black,
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
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
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionTitle("Player summary", profile.titleName)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric("Pumbility", profile.pumbilityScore?.let { NumberFormat.getNumberInstance().format(it) } ?: "-", Modifier.weight(1f))
            Metric("Rating", profile.rating?.let { NumberFormat.getIntegerInstance().format(it) } ?: "-", Modifier.weight(1f))
            Metric("Plays", profile.playCount?.let { NumberFormat.getIntegerInstance().format(it) } ?: "-", Modifier.weight(1f))
        }
    }
}

@Composable
private fun Metric(label: String, value: String, modifier: Modifier = Modifier) {
    Surface(modifier = modifier, tonalElevation = 1.dp, shape = RoundedCornerShape(6.dp)) {
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
        SectionTitle("MyPIU account", state.account?.email)
        if (state.isMyPiuConnected) {
            FilledTonalButton(onClick = onDisconnect, enabled = !state.isBusy) {
                Icon(Icons.Default.AccountCircle, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Sign out")
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
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
            Text(it, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun RecentPlayRow(play: RecentPlay) {
    Card(
        modifier = Modifier.fillMaxWidth(),
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
                if (play.stageBreak) "BREAK" else play.score?.let(NumberFormat.getIntegerInstance()::format) ?: "-",
                color = if (play.stageBreak) MaterialTheme.colorScheme.secondary else Color.Unspecified,
                fontWeight = FontWeight.Black,
            )
        }
    }
}
