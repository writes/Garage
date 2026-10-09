package com.writes.garage.feature

import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.FunctionsGateway
import com.writes.garage.core.data.PurchaseRepository
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.model.Entitlement
import com.writes.garage.core.model.PaywallPackage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Shared ordered call log so tests can assert "A happened before B". */
class CallLog {
    val calls = mutableListOf<String>()
    fun count(name: String) = calls.count { it == name }
}

/** Auth wrapper that records calls and can be told to fail. */
class RecordingAuth(
    private val inner: AuthRepository,
    private val log: CallLog = CallLog(),
    var googleFailure: Throwable? = null,
    var signOutFailure: Throwable? = null,
) : AuthRepository by inner {
    override suspend fun signInWithGoogle(idToken: String) {
        log.calls += "auth.signInWithGoogle"
        googleFailure?.let { throw it }
        inner.signInWithGoogle(idToken)
    }

    override suspend fun signOut() {
        log.calls += "auth.signOut"
        signOutFailure?.let { throw it }
        inner.signOut()
    }
}

/** Functions wrapper whose account/vehicle deletes are recorded, can fail, and can be held open. */
class RecordingFunctions(
    private val inner: FunctionsGateway,
    private val log: CallLog = CallLog(),
    var deleteFailure: Throwable? = null,
    /** When set, deleteAccount suspends until completed (to test the busy guard). */
    var gate: CompletableDeferred<Unit>? = null,
) : FunctionsGateway by inner {
    override suspend fun deleteAccount() {
        log.calls += "functions.deleteAccount"
        gate?.await()
        deleteFailure?.let { throw it }
        // Deliberately does NOT call inner.deleteAccount(): the demo gateway nulls the user itself, which would
        // mask a view model that forgets to sign out.
    }
}

/** A scripted PurchaseRepository: each operation can succeed (optionally flipping the entitlement) or throw. */
class FakePurchases(
    initial: Entitlement = Entitlement.FREE,
) : PurchaseRepository {
    private val _entitlement = MutableStateFlow(initial)
    override val entitlement: StateFlow<Entitlement> = _entitlement

    var purchaseGrantsPro = true
    var purchaseFailure: Throwable? = null
    var restoreGrantsPro = false
    var restoreFailure: Throwable? = null
    var packagesFailure: Throwable? = null
    var purchaseGate: CompletableDeferred<Unit>? = null
    var purchaseCalls = 0
    var restoreCalls = 0

    override suspend fun loadPackages(): List<PaywallPackage> {
        packagesFailure?.let { throw it }
        return listOf(PaywallPackage("annual", "p.annual", "Yearly", "\$29.99", "year"))
    }

    override suspend fun purchase(packageId: String) {
        purchaseCalls++
        purchaseGate?.await()
        purchaseFailure?.let { throw it }
        if (purchaseGrantsPro) _entitlement.value = Entitlement(isPro = true, productId = "p.$packageId")
    }

    override suspend fun restore() {
        restoreCalls++
        restoreFailure?.let { throw it }
        if (restoreGrantsPro) _entitlement.value = Entitlement(isPro = true)
    }
}

/** Entry repository whose reads/writes can be made to fail on demand. */
class FailingEntries(private val inner: com.writes.garage.core.data.EntryRepository) : com.writes.garage.core.data.EntryRepository by inner {
    var observeFailure: Throwable? = null
    var observeOneFailure: Throwable? = null
    var addFailure: Throwable? = null
    var updateFailure: Throwable? = null
    var deleteFailure: Throwable? = null

    override fun observeEntries(vehicleId: String) =
        observeFailure?.let { f -> kotlinx.coroutines.flow.flow<List<com.writes.garage.core.model.Entry>> { throw f } } ?: inner.observeEntries(vehicleId)

    override fun observeEntry(vehicleId: String, entryId: String) =
        observeOneFailure?.let { f -> kotlinx.coroutines.flow.flow<com.writes.garage.core.model.Entry?> { throw f } } ?: inner.observeEntry(vehicleId, entryId)

    override suspend fun addEntry(entry: com.writes.garage.core.model.Entry): com.writes.garage.core.model.Entry {
        addFailure?.let { throw it }
        return inner.addEntry(entry)
    }

    override suspend fun updateEntry(entry: com.writes.garage.core.model.Entry) {
        updateFailure?.let { throw it }
        inner.updateEntry(entry)
    }

    override suspend fun deleteEntry(vehicleId: String, entryId: String) {
        deleteFailure?.let { throw it }
        inner.deleteEntry(vehicleId, entryId)
    }
}

class FailingVehicles(private val inner: VehicleRepository) : VehicleRepository by inner {
    var deleteFailure: Throwable? = null
    var updateFailure: Throwable? = null
    var addFailure: Throwable? = null

    override suspend fun deleteVehicle(vehicleId: String) {
        deleteFailure?.let { throw it }
        inner.deleteVehicle(vehicleId)
    }

    override suspend fun updateVehicle(vehicle: com.writes.garage.core.model.Vehicle) {
        updateFailure?.let { throw it }
        inner.updateVehicle(vehicle)
    }

    override suspend fun addVehicle(vehicle: com.writes.garage.core.model.Vehicle): com.writes.garage.core.model.Vehicle {
        addFailure?.let { throw it }
        return inner.addVehicle(vehicle)
    }
}

class FailingReminders(private val inner: com.writes.garage.core.data.ReminderRepository) : com.writes.garage.core.data.ReminderRepository by inner {
    var addFailure: Throwable? = null
    var completeFailure: Throwable? = null
    var addCalls = 0
    var completeCalls = 0

    override suspend fun addReminder(reminder: com.writes.garage.core.model.Reminder): com.writes.garage.core.model.Reminder {
        addCalls++
        addFailure?.let { throw it }
        return inner.addReminder(reminder)
    }

    override suspend fun completeReminder(vehicleId: String, reminderId: String) {
        completeCalls++
        completeFailure?.let { throw it }
        inner.completeReminder(vehicleId, reminderId)
    }
}
