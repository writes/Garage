package com.writes.garage.feature.receipt

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.writes.garage.core.model.ReceiptQuota
import com.writes.garage.feature.shared.AiConsentDialog
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.ProposalEditor
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel
import java.io.File

private const val MAX_PICK = 3

@Composable
fun ReceiptScreen(onDone: () -> Unit) {
    val vm = appViewModel { ReceiptViewModel(it.vehicles, it.profile, it.storage, it.functions, it.entries, isPro = { it.purchases.entitlement.value.isPro }) }
    val s by vm.state.collectAsState()
    val context = LocalContext.current

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(MAX_PICK)) { uris ->
        vm.scan(uris.map { PickedImage(it.toString(), context.contentResolver.getType(it) ?: "image/jpeg") })
    }
    var captureUri by rememberSaveable { mutableStateOf<Uri?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = captureUri
        captureUri = null
        if (ok && uri != null) vm.scan(listOf(PickedImage(uri.toString(), "image/jpeg")))
    }
    fun launchCamera() {
        runCatching { newCaptureUri(context) }
            .onSuccess { captureUri = it; camera.launch(it) }
            .onFailure { vm.reportError("Couldn't start the camera.") }
    }
    // Declaring CAMERA in the manifest makes ACTION_IMAGE_CAPTURE require the runtime grant.
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else vm.reportError("Camera permission denied. You can still choose a photo from your library.")
    }

    if (s.needsConsent) AiConsentDialog(onGrant = vm::grantConsent, onDismiss = vm::dismissConsent)

    ScreenColumn("Scan receipt") {
        item { QuotaCard(s.quota) }
        if (s.busy) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    s.busyLabel?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                }
            }
        }
        val form = s.form
        val proposal = s.proposal
        if (proposal == null || form == null) {
            if (!s.hasConsent) {
                item { ConsentGate(onAllow = vm::grantConsent) }
            } else {
                item {
                    Text(
                        "Take a photo of a service receipt or choose up to $MAX_PICK from your library. " +
                            "You review everything before it is saved.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            enabled = !s.busy && !s.quotaExhausted,
                            onClick = {
                                if (!vm.requireConsent()) return@Button
                                if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                                    PackageManager.PERMISSION_GRANTED
                                ) {
                                    launchCamera()
                                } else {
                                    cameraPermission.launch(Manifest.permission.CAMERA)
                                }
                            },
                        ) { Text("Take photo") }
                        OutlinedButton(
                            enabled = !s.busy && !s.quotaExhausted,
                            onClick = {
                                if (vm.requireConsent()) {
                                    picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                                }
                            },
                        ) { Text("Choose photo") }
                    }
                }
            }
            if (s.saved) {
                item { Text("Entry saved.", color = MaterialTheme.colorScheme.primary) }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = vm::scanAnother) { Text("Scan another") }
                        Button(onClick = onDone) { Text("Done") }
                    }
                }
            } else {
                item { OutlinedButton(onClick = onDone) { Text("Cancel") } }
            }
        } else {
            item { SectionHeader("Review") }
            item {
                Text(
                    "Check the fields the AI filled in. Nothing is saved until you confirm. " +
                        "Confidence ${(proposal.confidence * 100).toInt()}%.",
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (proposal.lineItems.isNotEmpty()) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text("Line items", style = MaterialTheme.typography.labelLarge)
                            proposal.lineItems.forEach { Text("- $it", style = MaterialTheme.typography.bodySmall) }
                        }
                    }
                }
            }
            item { ProposalEditor(state = form, onChange = vm::updateForm) }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = vm::confirm, enabled = !s.busy) { Text(if (s.entrySaved) "Retry confirm" else "Confirm and save") }
                    if (!s.entrySaved) OutlinedButton(onClick = vm::discard, enabled = !s.busy) { Text("Discard") }
                }
            }
        }
        item { ErrorText(s.error) }
    }
}

@Composable
private fun ConsentGate(onAllow: () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("AI processing is off", style = MaterialTheme.typography.titleMedium)
            Text(
                "Receipt photos are sent to Garage's AI service (Claude) to draft a log entry. " +
                    "Nothing is saved until you confirm, and you can revoke this in Settings.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(onClick = onAllow) { Text("Allow AI processing") }
        }
    }
}

@Composable
private fun QuotaCard(q: ReceiptQuota?) {
    if (q == null) return
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp)) {
            Text(
                "${q.remaining} of ${q.monthlyLimit} receipt saves left" + if (q.isPro) " this month" else "",
                style = MaterialTheme.typography.titleSmall,
            )
            if (q.creditBalance > 0) Text("+ ${q.creditBalance} purchased credits", style = MaterialTheme.typography.bodySmall)
            if (q.remaining <= 0 && q.creditBalance <= 0) {
                Text("Out of scans. Upgrade to Pro or buy credits.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

/** A fresh jpeg in the FileProvider-shared `capture/` cache dir; stale captures (>1h) are swept first. */
private fun newCaptureUri(context: Context): Uri {
    val dir = File(context.cacheDir, "capture").apply { mkdirs() }
    val cutoff = System.currentTimeMillis() - 60 * 60 * 1000L
    dir.listFiles()?.filter { it.lastModified() < cutoff }?.forEach { it.delete() }
    val file = File(dir, "receipt-${System.currentTimeMillis()}.jpg")
    return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
}
