package com.writes.garage.feature.voice

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.writes.garage.feature.shared.AiConsentDialog
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.LocalAppContainer
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.shared.ProposalEditor
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun VoiceScreen(onDone: () -> Unit, onUpgrade: () -> Unit) {
    val vm = appViewModel { VoiceViewModel(it.vehicles, it.profile, it.functions, it.entries) }
    val s by vm.state.collectAsState()
    val entitlement by LocalAppContainer.current.purchases.entitlement.collectAsState()
    val context = LocalContext.current

    val speech = remember {
        SpeechController(
            context,
            object : SpeechController.Callbacks {
                override fun onStarted() = vm.onListeningStarted()
                override fun onPartial(text: String) = vm.onPartial(text)
                override fun onResult(text: String) = vm.onSpeechResult(text)
                override fun onError(message: String) = vm.onSpeechError(message)
                override fun onStopped() = Unit
            },
        )
    }
    DisposableEffect(speech) { onDispose { speech.destroy() } }

    val micPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) speech.start() else vm.reportError("Microphone permission denied. You can type the transcript instead.")
    }
    fun startListening() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            speech.start()
        } else {
            micPermission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    if (s.needsConsent) AiConsentDialog(onGrant = vm::grantConsent, onDismiss = vm::dismissConsent)

    if (!entitlement.isPro) {
        // Same rule as iOS (and the server's `pro_required`): voice entry is a Pro feature.
        ScreenColumn("Voice entry") {
            item {
                ProGate(isPro = false, onUpgrade = onUpgrade, lockedMessage = "Voice entry is a Garage Pro feature.") {}
            }
            item { OutlinedButton(onClick = onDone) { Text("Back") } }
        }
        return
    }

    ScreenColumn("Voice entry") {
        if (s.busy) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        val form = s.form
        val proposal = s.proposal
        if (proposal == null || form == null) {
            if (!s.hasConsent) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("AI processing is off", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "Your transcript is sent to Garage's AI service (Claude) to draft a log entry. " +
                                    "Nothing is saved until you confirm, and you can revoke this in Settings.",
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Button(onClick = vm::grantConsent) { Text("Allow AI processing") }
                        }
                    }
                }
            } else {
                item {
                    Text(
                        "Say what you did, e.g. \"Changed the oil at 82,000 miles for 90 dollars\". " +
                            "Review the draft before it is saved.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (s.listening) {
                            Button(onClick = speech::stop) { Text("Stop") }
                        } else {
                            Button(onClick = ::startListening, enabled = !s.busy) { Text("Speak") }
                        }
                    }
                }
                if (s.listening) {
                    item { Text(s.partial.ifEmpty { "Listening..." }, style = MaterialTheme.typography.bodyLarge) }
                }
                item {
                    OutlinedTextField(
                        value = s.transcript, onValueChange = vm::setTranscript, label = { Text("Transcript") },
                        modifier = Modifier.fillMaxWidth(), minLines = 2,
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = vm::interpret, enabled = !s.busy && !s.listening && s.transcript.isNotBlank()) {
                            Text("Interpret")
                        }
                        OutlinedButton(onClick = onDone) { Text(if (s.saved) "Done" else "Cancel") }
                    }
                }
                if (s.saved) {
                    item { Text("Entry saved.", color = MaterialTheme.colorScheme.primary) }
                    item { OutlinedButton(onClick = vm::recordAnother) { Text("Add another") } }
                }
            }
        } else {
            item { SectionHeader("Review") }
            item {
                Text(
                    "Heard: \"${proposal.transcript}\" (confidence ${(proposal.confidence * 100).toInt()}%). " +
                        "Edit anything that's off; nothing is saved until you confirm.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            item { ProposalEditor(state = form, onChange = vm::updateForm) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::confirm, enabled = !s.busy) { Text("Confirm and save") }
                    OutlinedButton(onClick = vm::discard, enabled = !s.busy) { Text("Discard") }
                }
            }
        }
        item { ErrorText(s.error) }
    }
}
