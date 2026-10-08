package com.writes.garage.feature.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun ProfileScreen(onBack: () -> Unit) {
    val vm = appViewModel { ProfileViewModel(it.profile) }
    val s by vm.state.collectAsState()

    ScreenColumn("Profile") {
        s.email?.let { item { Text(it, style = MaterialTheme.typography.bodyMedium) } }
        item { SectionHeader("Owner") }
        item { FormTextField("Name", s.name, { v -> vm.edit { copy(name = v) } }) }
        item { FormTextField("Address", s.address, { v -> vm.edit { copy(address = v) } }, singleLine = false) }
        item { FormTextField("Phone", s.phone, { v -> vm.edit { copy(phone = v) } }, keyboardType = KeyboardType.Phone) }
        item { SectionHeader("Insurance") }
        item { FormTextField("Insurance company", s.insuranceCompany, { v -> vm.edit { copy(insuranceCompany = v) } }) }
        item { FormTextField("Policy number", s.policyNumber, { v -> vm.edit { copy(policyNumber = v) } }) }
        item { ErrorText(s.error) }
        if (s.saved) item { Text("Profile saved", color = MaterialTheme.colorScheme.primary) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = vm::save, enabled = s.loaded && !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                OutlinedButton(onClick = onBack) { Text("Back") }
            }
        }
    }
}
