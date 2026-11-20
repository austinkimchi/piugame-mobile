package com.austinkimchi.mypiu.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import com.austinkimchi.mypiu.R
import com.austinkimchi.mypiu.core.model.MyPiuPerformanceDashboard
import com.austinkimchi.mypiu.core.model.PiuGameVersion
import java.util.Locale

internal data class ResultArtworkBadge(val text: String, val label: String, val resourceId: Int?)
internal data class ResultArtwork(val grade: ResultArtworkBadge?, val plate: ResultArtworkBadge?)

internal fun resultArtwork(
    grade: String?,
    plate: String?,
    version: PiuGameVersion?,
    stageBreak: Boolean = false,
): ResultArtwork {
    if (stageBreak) return ResultArtwork(ResultArtworkBadge("Stage Break", "Stage Break", null), null)
    val resources = when (version) {
        PiuGameVersion.PHOENIX -> phoenixResults
        PiuGameVersion.PHOENIX_2 -> phoenix2Results
        null -> emptyMap()
    }
    val rawGrade = grade?.trim()?.lowercase(Locale.ROOT).orEmpty()
    val failed = rawGrade.startsWith("x_")
    val code = rawGrade.removePrefix("x_").replace(Regex("\\+$"), "_p")
    val gradeText = code.removeSuffix("_p").replace('_', ' ').uppercase(Locale.ROOT)
        .let { if (code.endsWith("_p")) "$it+" else it }.ifBlank { "Played" }
    val plateCode = plate?.trim()?.lowercase(Locale.ROOT).orEmpty().removePrefix("s_")
    val plateText = plateCode.uppercase(Locale.ROOT)
    return ResultArtwork(
        grade = ResultArtworkBadge(
            text = gradeText,
            label = if (rawGrade.isBlank()) "Played; grade unavailable"
                else "${if (failed) "Failed grade" else "Grade"} $gradeText",
            resourceId = resources["grade:${if (failed) "x_" else ""}$code"],
        ),
        plate = plateCode.takeIf { it.isNotBlank() }?.let {
            ResultArtworkBadge(plateText, "Plate $plateText", resources["plate:$plateCode"])
        },
    )
}

@Composable
internal fun PerformanceResultArtwork(play: MyPiuPerformanceDashboard.Play, version: PiuGameVersion?) {
    val artwork = resultArtwork(play.grade, play.plate, version, play.stageBreak)
    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        artwork.grade?.let { ResultArtworkImage(it, isGrade = true) }
        artwork.plate?.let { ResultArtworkImage(it, isGrade = false) }
    }
}

@Composable
private fun ResultArtworkImage(badge: ResultArtworkBadge, isGrade: Boolean) {
    var imageFailed by remember(badge.resourceId) { mutableStateOf(false) }
    if (badge.resourceId != null && !imageFailed) {
        // Integer resource IDs decode from the APK: no network request, account record or URL.
        AsyncImage(
            model = badge.resourceId,
            contentDescription = badge.label,
            contentScale = ContentScale.Fit,
            modifier = Modifier.size(width = 96.dp, height = if (isGrade) 57.dp else 29.dp),
            onError = { imageFailed = true },
        )
    } else {
        Text(
            badge.text,
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.clearAndSetSemantics { contentDescription = badge.label },
        )
    }
}

// Only verified originals from android/piu-result-artwork-manifest.json; no generated asset URLs.

private val phoenixResults = mapOf(
    "grade:sss_p" to R.drawable.piu_phoenix_grade_sss_p,
    "grade:sss" to R.drawable.piu_phoenix_grade_sss,
    "grade:ss_p" to R.drawable.piu_phoenix_grade_ss_p,
    "grade:ss" to R.drawable.piu_phoenix_grade_ss,
    "grade:s_p" to R.drawable.piu_phoenix_grade_s_p,
    "grade:s" to R.drawable.piu_phoenix_grade_s,
    "grade:aaa_p" to R.drawable.piu_phoenix_grade_aaa_p,
    "grade:aaa" to R.drawable.piu_phoenix_grade_aaa,
    "grade:aa_p" to R.drawable.piu_phoenix_grade_aa_p,
    "grade:aa" to R.drawable.piu_phoenix_grade_aa,
    "grade:a_p" to R.drawable.piu_phoenix_grade_a_p,
    "grade:a" to R.drawable.piu_phoenix_grade_a,
    "grade:b" to R.drawable.piu_phoenix_grade_b,
    "grade:c" to R.drawable.piu_phoenix_grade_c,
    "grade:d" to R.drawable.piu_phoenix_grade_d,
    "grade:f" to R.drawable.piu_phoenix_grade_f,
    "grade:x_sss_p" to R.drawable.piu_phoenix_grade_x_sss_p,
    "grade:x_sss" to R.drawable.piu_phoenix_grade_x_sss,
    "grade:x_ss_p" to R.drawable.piu_phoenix_grade_x_ss_p,
    "grade:x_ss" to R.drawable.piu_phoenix_grade_x_ss,
    "grade:x_s_p" to R.drawable.piu_phoenix_grade_x_s_p,
    "grade:x_s" to R.drawable.piu_phoenix_grade_x_s,
    "grade:x_aaa_p" to R.drawable.piu_phoenix_grade_x_aaa_p,
    "grade:x_aaa" to R.drawable.piu_phoenix_grade_x_aaa,
    "grade:x_aa_p" to R.drawable.piu_phoenix_grade_x_aa_p,
    "grade:x_aa" to R.drawable.piu_phoenix_grade_x_aa,
    "grade:x_a_p" to R.drawable.piu_phoenix_grade_x_a_p,
    "grade:x_a" to R.drawable.piu_phoenix_grade_x_a,
    "grade:x_b" to R.drawable.piu_phoenix_grade_x_b,
    "grade:x_c" to R.drawable.piu_phoenix_grade_x_c,
    "grade:x_d" to R.drawable.piu_phoenix_grade_x_d,
    "grade:x_f" to R.drawable.piu_phoenix_grade_x_f,
    "plate:pg" to R.drawable.piu_phoenix_plate_pg,
    "plate:ug" to R.drawable.piu_phoenix_plate_ug,
    "plate:eg" to R.drawable.piu_phoenix_plate_eg,
    "plate:sg" to R.drawable.piu_phoenix_plate_sg,
    "plate:mg" to R.drawable.piu_phoenix_plate_mg,
    "plate:tg" to R.drawable.piu_phoenix_plate_tg,
    "plate:fg" to R.drawable.piu_phoenix_plate_fg,
    "plate:rg" to R.drawable.piu_phoenix_plate_rg,
)

private val phoenix2Results = mapOf(
    "grade:sss_p" to R.drawable.piu_phoenix2_grade_sss_p,
    "grade:sss" to R.drawable.piu_phoenix2_grade_sss,
    "grade:ss_p" to R.drawable.piu_phoenix2_grade_ss_p,
    "grade:ss" to R.drawable.piu_phoenix2_grade_ss,
    "grade:s_p" to R.drawable.piu_phoenix2_grade_s_p,
    "grade:s" to R.drawable.piu_phoenix2_grade_s,
    "grade:aaa_p" to R.drawable.piu_phoenix2_grade_aaa_p,
    "grade:aaa" to R.drawable.piu_phoenix2_grade_aaa,
    "grade:aa_p" to R.drawable.piu_phoenix2_grade_aa_p,
    "grade:aa" to R.drawable.piu_phoenix2_grade_aa,
    "grade:a_p" to R.drawable.piu_phoenix2_grade_a_p,
    "grade:a" to R.drawable.piu_phoenix2_grade_a,
    "grade:b" to R.drawable.piu_phoenix2_grade_b,
    "grade:c" to R.drawable.piu_phoenix2_grade_c,
    "grade:d" to R.drawable.piu_phoenix2_grade_d,
    "grade:f" to R.drawable.piu_phoenix2_grade_f,
    "grade:x_sss_p" to R.drawable.piu_phoenix2_grade_x_sss_p,
    "grade:x_sss" to R.drawable.piu_phoenix2_grade_x_sss,
    "grade:x_ss_p" to R.drawable.piu_phoenix2_grade_x_ss_p,
    "grade:x_ss" to R.drawable.piu_phoenix2_grade_x_ss,
    "grade:x_s_p" to R.drawable.piu_phoenix2_grade_x_s_p,
    "grade:x_s" to R.drawable.piu_phoenix2_grade_x_s,
    "grade:x_aaa_p" to R.drawable.piu_phoenix2_grade_x_aaa_p,
    "grade:x_aaa" to R.drawable.piu_phoenix2_grade_x_aaa,
    "grade:x_aa_p" to R.drawable.piu_phoenix2_grade_x_aa_p,
    "grade:x_aa" to R.drawable.piu_phoenix2_grade_x_aa,
    "grade:x_a_p" to R.drawable.piu_phoenix2_grade_x_a_p,
    "grade:x_a" to R.drawable.piu_phoenix2_grade_x_a,
    "grade:x_b" to R.drawable.piu_phoenix2_grade_x_b,
    "grade:x_c" to R.drawable.piu_phoenix2_grade_x_c,
    "grade:x_d" to R.drawable.piu_phoenix2_grade_x_d,
    "grade:x_f" to R.drawable.piu_phoenix2_grade_x_f,
    "plate:pg" to R.drawable.piu_phoenix2_plate_pg,
    "plate:ug" to R.drawable.piu_phoenix2_plate_ug,
    "plate:eg" to R.drawable.piu_phoenix2_plate_eg,
    "plate:sg" to R.drawable.piu_phoenix2_plate_sg,
    "plate:mg" to R.drawable.piu_phoenix2_plate_mg,
    "plate:tg" to R.drawable.piu_phoenix2_plate_tg,
    "plate:fg" to R.drawable.piu_phoenix2_plate_fg,
    "plate:rg" to R.drawable.piu_phoenix2_plate_rg,
)
