package com.douhua.jifen.screen.tools

import android.media.AudioAttributes
import android.media.SoundPool
import com.douhua.jifen.util.VibrationHelper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.douhua.jifen.R
import com.douhua.jifen.analytics.AnalyticsEventNames
import com.douhua.jifen.analytics.trackToolEvent
import com.douhua.jifen.helpers.responsiveHorizontalPadding
import com.douhua.jifen.ui.theme.Primary
import com.douhua.jifen.ui.theme.AppSpacing
import com.douhua.jifen.ui.theme.LocalAppColors
import com.douhua.jifen.util.rememberGlobalSoundEnabled
import com.douhua.jifen.util.rememberGlobalVibrationEnabled
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun WhistleToolScreen(onBack: () -> Unit = {}) {
    val context = LocalContext.current
    val appColors = LocalAppColors.current
    val soundEnabled = rememberGlobalSoundEnabled()
    val vibrationEnabled = rememberGlobalVibrationEnabled()
    val isTabletLike = com.douhua.jifen.helpers.isTablet()
    val scope = rememberCoroutineScope()
    var isPlayingShort by remember { mutableStateOf(false) }
    var isPlayingLong by remember { mutableStateOf(false) }

    fun trackWhistle(actionName: String) {
        trackToolEvent(
            context = context,
            eventName = AnalyticsEventNames.TOOL_ACTION,
            toolId = "whistle",
            actionName = actionName
        )
    }

    val soundPool = remember {
        SoundPool.Builder().setMaxStreams(1)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            ).build()
    }
    var whistleSoundId by remember { mutableIntStateOf(0) }
    var buzzerSoundId by remember { mutableIntStateOf(0) }
    DisposableEffect(context) {
        var pendingWhistle = 0
        var pendingBuzzer = 0
        soundPool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) {
                when (sampleId) {
                    pendingWhistle -> whistleSoundId = sampleId
                    pendingBuzzer -> buzzerSoundId = sampleId
                }
            }
        }
        pendingWhistle = soundPool.load(context, R.raw.whistle, 1)
        pendingBuzzer = soundPool.load(context, R.raw.buzzer, 1)
        onDispose { soundPool.release() }
    }

    ToolPageMaxWidthShell(
        Modifier
            .fillMaxSize()
            .background(appColors.background),
        limitMainContentWidth = true,
        fullWidthOverlay = {
            ToolOverlayBackButton(
                onBack = onBack,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = responsiveHorizontalPadding(), top = AppSpacing.lg)
            )
        }
    ) {
        if (isTabletLike) {
            Row(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(32.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                WhistleCard(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .height(280.dp),
                    title = stringResource(R.string.whistle_short),
                    emoji = "🔊",
                    active = isPlayingShort,
                    baseColor = Primary,
                    onClick = {
                        if (isPlayingShort || isPlayingLong) return@WhistleCard
                        trackWhistle("short_whistle")
                        isPlayingShort = true
                        VibrationHelper.vibrateCustom(context, 80L, vibrationEnabled)
                        if (soundEnabled && whistleSoundId > 0) soundPool.play(whistleSoundId, 1f, 1f, 1, 0, 1f)
                        scope.launch {
                            delay(1200)
                            isPlayingShort = false
                        }
                    }
                )

                WhistleCard(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .height(280.dp),
                    title = stringResource(R.string.whistle_long),
                    emoji = "📯",
                    active = isPlayingLong,
                    baseColor = Color(0xFFF44336),
                    onClick = {
                        if (isPlayingShort || isPlayingLong) return@WhistleCard
                        trackWhistle("long_whistle")
                        isPlayingLong = true
                        VibrationHelper.vibrateCustom(context, 150L, vibrationEnabled)
                        if (soundEnabled && buzzerSoundId > 0) soundPool.play(buzzerSoundId, 1f, 1f, 1, 0, 1f)
                        scope.launch {
                            delay(2200)
                            isPlayingLong = false
                        }
                    }
                )
            }
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(start = 48.dp, end = 48.dp, top = 32.dp, bottom = 32.dp),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                WhistleCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(192.dp),
                    title = stringResource(R.string.whistle_short),
                    emoji = "🔊",
                    active = isPlayingShort,
                    baseColor = Primary,
                    onClick = {
                        if (isPlayingShort || isPlayingLong) return@WhistleCard
                        trackWhistle("short_whistle")
                        isPlayingShort = true
                        VibrationHelper.vibrateCustom(context, 80L, vibrationEnabled)
                        if (soundEnabled && whistleSoundId > 0) soundPool.play(whistleSoundId, 1f, 1f, 1, 0, 1f)
                        scope.launch {
                            delay(1200)
                            isPlayingShort = false
                        }
                    }
                )

                Spacer(modifier = Modifier.height(24.dp))

                WhistleCard(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(192.dp),
                    title = stringResource(R.string.whistle_long),
                    emoji = "📯",
                    active = isPlayingLong,
                    baseColor = Color(0xFFF44336),
                    onClick = {
                        if (isPlayingShort || isPlayingLong) return@WhistleCard
                        trackWhistle("long_whistle")
                        isPlayingLong = true
	                        VibrationHelper.vibrateCustom(context, 150L, vibrationEnabled)
                        if (soundEnabled && buzzerSoundId > 0) soundPool.play(buzzerSoundId, 1f, 1f, 1, 0, 1f)
                        scope.launch {
                            delay(2200)
                            isPlayingLong = false
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun WhistleCard(
    modifier: Modifier,
    title: String,
    emoji: String,
    active: Boolean,
    baseColor: Color,
    onClick: () -> Unit
) {
    val appColors = LocalAppColors.current
    Card(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .clickable(onClick = onClick)
            .border(
                width = if (active) 3.dp else 1.dp,
                color = if (active) baseColor else baseColor.copy(alpha = 0.35f),
                shape = RoundedCornerShape(16.dp)
            ),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = if (active) baseColor.copy(alpha = 0.3f) else baseColor.copy(alpha = 0.1f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(text = emoji, fontSize = 64.sp, modifier = Modifier.size(88.dp))
            Text(
                text = title,
                color = if (active || appColors.isDark) Color.White else appColors.textPrimary,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
}
