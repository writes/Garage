package com.writes.garage.feature.garage

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.writes.garage.core.model.FuelType
import com.writes.garage.feature.shared.ChoiceField
import com.writes.garage.feature.shared.ChoiceOption
import com.writes.garage.feature.shared.DateField
import com.writes.garage.feature.shared.EmptyState
import com.writes.garage.feature.shared.ErrorText
import com.writes.garage.feature.shared.FormTextField
import com.writes.garage.feature.shared.ProGate
import com.writes.garage.feature.shared.ScreenColumn
import com.writes.garage.feature.shared.SectionHeader
import com.writes.garage.feature.shared.appViewModel

@Composable
fun VehicleEditScreen(vehicleId: String?, onDone: () -> Unit, onUpgrade: () -> Unit = {}) {
    val vm = appViewModel(key = "vehicle-edit-$vehicleId") { VehicleEditViewModel(it.vehicles, it.purchases, vehicleId) }
    val s by vm.state.collectAsState()

    ScreenColumn(if (vehicleId == null) "Add vehicle" else "Edit vehicle") {
        if (s.loading) {
            item { CircularProgressIndicator() }
            return@ScreenColumn
        }
        if (s.notFound) {
            item { EmptyState("Vehicle not found.") }
            item { OutlinedButton(onClick = onDone) { Text("Back") } }
            return@ScreenColumn
        }
        if (vehicleId == null && s.limitReached) {
            item {
                ProGate(
                    isPro = false,
                    onUpgrade = onUpgrade,
                    lockedMessage = "Your plan includes ${s.limit} vehicle${if (s.limit == 1) "" else "s"}. Upgrade to Garage Pro to add more.",
                ) {}
            }
            item { OutlinedButton(onClick = onDone) { Text("Back") } }
            return@ScreenColumn
        }

        item { FormTextField("Nickname", s.nickname, { vm.edit("nickname", it) }, error = s.errors["nickname"]) }
        item { FormTextField("Make", s.make, { vm.edit("make", it) }, error = s.errors["make"], required = true) }
        item { FormTextField("Model", s.model, { vm.edit("model", it) }, error = s.errors["model"], required = true) }
        item {
            FormTextField(
                "Year", s.year, { vm.edit("year", it) },
                error = s.errors["year"], keyboardType = KeyboardType.Number, required = true,
            )
        }
        item {
            FormTextField(
                "Odometer (mi)", s.odometer, { vm.edit("odometer", it) },
                error = s.errors["odometer"], keyboardType = KeyboardType.Number, required = true,
            )
        }
        item { FormTextField("VIN", s.vin, { vm.edit("vin", it) }, error = s.errors["vin"]) }
        item { FormTextField("License plate", s.licensePlate, { vm.edit("licensePlate", it) }) }
        item { FormTextField("Color", s.color, { vm.edit("color", it) }) }
        item {
            ChoiceField(
                "Fuel type",
                listOf(ChoiceOption("", "Not set")) + FuelType.entries.map { ChoiceOption(it.wire, it.displayName) },
                s.fuelType,
                { vm.edit("fuelType", it) },
            )
        }

        item { SectionHeader("Ownership") }
        item { DateField("Purchase date", s.purchaseDate, { d -> vm.update { copy(purchaseDate = d) } }, clearable = true) }
        item {
            FormTextField(
                "Purchase price", s.purchasePrice, { vm.edit("purchasePrice", it) },
                error = s.errors["purchasePrice"], keyboardType = KeyboardType.Decimal,
            )
        }
        item {
            FormTextField(
                "Odometer at purchase", s.odometerAtPurchase, { vm.edit("odometerAtPurchase", it) },
                error = s.errors["odometerAtPurchase"], keyboardType = KeyboardType.Number,
            )
        }

        item { SectionHeader("Specs") }
        item { FormTextField("Engine oil type", s.engineOilType, { vm.edit("engineOilType", it) }) }
        item { FormTextField("Front tire size", s.tireSizeFront, { vm.edit("tireSizeFront", it) }) }
        item { FormTextField("Rear tire size", s.tireSizeRear, { vm.edit("tireSizeRear", it) }) }
        item { FormTextField("Weight class", s.weightClass, { vm.edit("weightClass", it) }) }
        item { FormTextField("Notes", s.notes, { vm.edit("notes", it) }, singleLine = false) }

        item { ErrorText(s.formError) }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { vm.save(onDone) }, enabled = !s.saving) { Text(if (s.saving) "Saving..." else "Save") }
                OutlinedButton(onClick = onDone) { Text("Cancel") }
            }
        }
    }
}
