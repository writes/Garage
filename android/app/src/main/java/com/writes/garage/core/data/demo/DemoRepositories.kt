package com.writes.garage.core.data.demo

import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.data.StorageRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.domain.Constants
import com.writes.garage.core.domain.VehicleLimitPolicy
import com.writes.garage.core.domain.VehicleLimitReachedException
import com.writes.garage.core.model.AuthUser
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.PaywallPackage
import com.writes.garage.core.model.Reminder
import com.writes.garage.core.model.UserProfile
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update

class DemoAuthRepository(private val store: DemoStore) : AuthRepository {
    override val currentUser: StateFlow<AuthUser?> = store.user.asStateFlow()

    override suspend fun signInDemo() {
        store.user.value = AuthUser(
            uid = Constants.DEMO_USER_ID, email = "demo@garage.local", displayName = "Demo Driver", isDemo = true,
        )
    }

    override suspend fun signInWithGoogle(idToken: String) = signInDemo()

    override suspend fun signOut() {
        store.user.value = null
    }
}

class DemoProfileRepository(private val store: DemoStore) : ProfileRepository {
    override fun observeProfile(): Flow<UserProfile?> = store.profile

    override suspend fun updateProfile(profile: UserProfile) {
        store.profile.value = profile.copy(updatedAt = store.clock())
    }

    override suspend fun setAiConsent(granted: Boolean) {
        store.profile.update { it.copy(aiConsentGrantedAt = if (granted) store.clock() else null) }
    }
}

class DemoVehicleRepository(private val store: DemoStore) : VehicleRepository {
    override fun observeVehicles(): Flow<List<Vehicle>> =
        store.vehicles.map { list -> list.filter { it.deletedAt == null }.sortedBy { it.displayOrder } }

    override fun observeVehicle(vehicleId: String): Flow<Vehicle?> =
        store.vehicles.map { list -> list.firstOrNull { it.id == vehicleId && it.deletedAt == null } }

    override val activeVehicleId: StateFlow<String?> = store.activeVehicleId.asStateFlow()

    override suspend fun setActiveVehicle(vehicleId: String) {
        if (store.vehicles.value.any { it.id == vehicleId && it.deletedAt == null }) {
            store.activeVehicleId.value = vehicleId
        }
    }

    override suspend fun addVehicle(vehicle: Vehicle): Vehicle {
        val live = store.vehicles.value.count { it.deletedAt == null }
        val isPro = store.entitlement.value.isPro
        if (!VehicleLimitPolicy.canAddVehicle(live, isPro)) {
            throw VehicleLimitReachedException(VehicleLimitPolicy.limitFor(isPro))
        }
        val now = store.clock()
        val created = vehicle.copy(
            id = vehicle.id.ifBlank { store.newId("vehicle") },
            userId = store.profile.value.id,
            displayOrder = live,
            createdAt = now,
            updatedAt = now,
        )
        store.vehicles.update { it + created }
        if (store.activeVehicleId.value == null) store.activeVehicleId.value = created.id
        return created
    }

    override suspend fun updateVehicle(vehicle: Vehicle) {
        store.vehicles.update { list ->
            list.map { if (it.id == vehicle.id) vehicle.copy(updatedAt = store.clock()) else it }
        }
    }

    override suspend fun deleteVehicle(vehicleId: String) {
        val now = store.clock()
        store.vehicles.update { list -> list.map { if (it.id == vehicleId) it.copy(deletedAt = now) else it } }
        if (store.activeVehicleId.value == vehicleId) {
            store.activeVehicleId.value = store.vehicles.value.firstOrNull { it.deletedAt == null }?.id
        }
    }
}

class DemoEntryRepository(private val store: DemoStore) : EntryRepository {
    override fun observeEntries(vehicleId: String): Flow<List<Entry>> =
        store.entries.map { list -> list.filter { it.vehicleId == vehicleId }.sortedByDescending { it.entryDate } }

    override fun observeEntry(vehicleId: String, entryId: String): Flow<Entry?> =
        store.entries.map { list -> list.firstOrNull { it.vehicleId == vehicleId && it.id == entryId } }

    override suspend fun addEntry(entry: Entry): Entry {
        val now = store.clock()
        val created = entry.copy(
            id = entry.id.ifBlank { store.newId("entry") },
            userId = store.profile.value.id,
            createdAt = now,
            updatedAt = now,
        )
        store.entries.update { it + created }
        return created
    }

    override suspend fun updateEntry(entry: Entry) {
        store.entries.update { list ->
            list.map { if (it.id == entry.id) entry.copy(updatedAt = store.clock()) else it }
        }
    }

    override suspend fun deleteEntry(vehicleId: String, entryId: String) {
        store.entries.update { list -> list.filterNot { it.vehicleId == vehicleId && it.id == entryId } }
    }
}

class DemoReminderRepository(private val store: DemoStore) : ReminderRepository {
    override fun observeReminders(vehicleId: String): Flow<List<Reminder>> =
        store.reminders.map { list -> list.filter { it.vehicleId == vehicleId } }

    override suspend fun addReminder(reminder: Reminder): Reminder {
        val created = reminder.copy(id = reminder.id.ifBlank { store.newId("reminder") }, createdAt = store.clock())
        store.reminders.update { it + created }
        return created
    }

    override suspend fun updateReminder(reminder: Reminder) {
        store.reminders.update { list -> list.map { if (it.id == reminder.id) reminder else it } }
    }

    override suspend fun completeReminder(vehicleId: String, reminderId: String) {
        val now = store.clock()
        store.reminders.update { list ->
            list.map { if (it.vehicleId == vehicleId && it.id == reminderId) it.copy(completedAt = now) else it }
        }
    }

    override suspend fun deleteReminder(vehicleId: String, reminderId: String) {
        store.reminders.update { list -> list.filterNot { it.vehicleId == vehicleId && it.id == reminderId } }
    }
}

/** No real storage in demo: returns a synthetic path so receipt flows can proceed. */
class DemoStorageRepository(private val store: DemoStore) : StorageRepository {
    override suspend fun uploadAttachment(
        vehicleId: String,
        localUri: String,
        contentType: String,
        entryId: String?,
    ): String = "demo/${store.profile.value.id}/$vehicleId/${store.newId("attachment")}"

    override suspend fun readAsBase64(localUri: String, contentType: String): String = "ZGVtby1yZWNlaXB0"

    override suspend fun deleteAttachment(storagePath: String) = Unit
}

class DemoPurchaseRepository(private val store: DemoStore) : PurchaseRepository {
    override val entitlement: StateFlow<Entitlement> = store.entitlement.asStateFlow()

    override suspend fun loadPackages(): List<PaywallPackage> = listOf(
        PaywallPackage("annual", Constants.ANNUAL_PLAN_ID, "Garage Pro - Yearly", "\$29.99", "year"),
        PaywallPackage("monthly", Constants.MONTHLY_PLAN_ID, "Garage Pro - Monthly", "\$3.99", "month"),
    )

    override suspend fun purchase(packageId: String) {
        store.entitlement.value = Entitlement(isPro = true, productId = "demo.$packageId", willRenew = true)
    }

    override suspend fun restore() = Unit

    /** Demo-only affordance to flip back to Free and exercise the vehicle limit. */
    fun setPro(isPro: Boolean) {
        store.entitlement.value = if (isPro) Entitlement(isPro = true, productId = "demo.pro") else Entitlement.FREE
    }
}
