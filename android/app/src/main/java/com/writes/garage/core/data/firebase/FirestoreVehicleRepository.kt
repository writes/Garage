package com.writes.garage.core.data.firebase

import android.content.SharedPreferences
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.CrashReporter
import com.writes.garage.core.data.NoopCrashReporter
import com.writes.garage.core.data.VehicleRepository
import com.writes.garage.core.domain.VehicleLimitPolicy
import com.writes.garage.core.domain.VehicleLimitReachedException
import com.writes.garage.core.model.Vehicle
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.UUID

/** The server disagrees with the local plan check (usually a not-yet-decremented counter after a recent delete). */
class VehicleCountSyncException :
    IllegalStateException("Couldn't add the vehicle — your vehicle count is still syncing. Please try again in a moment.")

/**
 * `vehicles/{id}` (owner field `userId`). Create is the RULES-1 *counted* batch; delete is a client tombstone
 * (`deletedAt`) followed by the `deleteVehicle` callable that purges + decrements. Never a client hard delete.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FirestoreVehicleRepository(
    private val db: FirebaseFirestore,
    private val auth: AuthRepository,
    private val isPro: () -> Boolean,
    private val purge: suspend (vehicleId: String) -> Unit,
    private val prefs: SharedPreferences? = null,
    private val crash: CrashReporter = NoopCrashReporter,
    private val clock: () -> Instant = Instant::now,
) : VehicleRepository {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val _active = MutableStateFlow(runCatching { prefs?.getString(PREF_ACTIVE, null) }.getOrNull())
    override val activeVehicleId: StateFlow<String?> = _active.asStateFlow()

    private fun uid(): String = auth.currentUser.value?.uid ?: error("Not signed in")

    private fun vehicles() = db.collection(FirestorePaths.VEHICLES)

    private fun vehiclesFlow(uid: String): Flow<List<Vehicle>> = callbackFlow {
        val reg = vehicles().whereEqualTo("userId", uid).addSnapshotListener { snap, err ->
            if (err != null) {
                close(err)
                return@addSnapshotListener
            }
            val list = snap?.documents.orEmpty().mapNotNull { d ->
                FirestoreMappers.vehicleFromMap(d.id, FirestoreValueCodec.decodeMap(d.data))
            }
            trySend(list)
        }
        awaitClose { reg.remove() }
    }

    override fun observeVehicles(): Flow<List<Vehicle>> = auth.currentUser.flatMapLatest { user ->
        if (user == null) flowOf(emptyList()) else vehiclesFlow(user.uid)
    }.map { list -> list.filter { it.deletedAt == null }.sortedBy { it.displayOrder } }

    override fun observeVehicle(vehicleId: String): Flow<Vehicle?> = observeVehicles().map { l -> l.firstOrNull { it.id == vehicleId } }

    override suspend fun setActiveVehicle(vehicleId: String) {
        _active.value = vehicleId
        runCatching { prefs?.edit()?.putString(PREF_ACTIVE, vehicleId)?.apply() }
    }

    override suspend fun addVehicle(vehicle: Vehicle): Vehicle {
        val uid = uid()
        // Local precheck (UX); the rules + counter are authoritative.
        val live = vehicles().whereEqualTo("userId", uid).get().await().documents.count { it.get("deletedAt") == null }
        val pro = isPro()
        if (!VehicleLimitPolicy.canAddVehicle(live, pro)) throw VehicleLimitReachedException(VehicleLimitPolicy.limitFor(pro))

        val now = clock()
        val created = vehicle.copy(
            id = vehicle.id.ifBlank { UUID.randomUUID().toString() },
            userId = uid, displayOrder = live, createdAt = now, updatedAt = now, deletedAt = null,
        )
        val vehicleRef = vehicles().document(created.id)
        val userRef = db.collection(FirestorePaths.USERS).document(uid)
        val batch = db.batch()
        batch.set(vehicleRef, FirestoreValueCodec.encodeForCreate(FirestoreMappers.vehicleToMap(created)))
        batch.set(
            userRef,
            FirestoreValueCodec.encodeForCreate(FirestoreMappers.countedCreateUserFields(created.id)) +
                mapOf("vehicleCount" to FieldValue.increment(1)),
            SetOptions.merge(),
        )
        try {
            batch.commit().await()
        } catch (e: FirebaseFirestoreException) {
            if (e.code == FirebaseFirestoreException.Code.PERMISSION_DENIED) {
                crash.record(e)
                scope.launch { retryPendingPurges() }
                throw VehicleCountSyncException()
            }
            throw e
        }
        if (_active.value == null) setActiveVehicle(created.id)
        return created
    }

    override suspend fun updateVehicle(vehicle: Vehicle) {
        val map = FirestoreMappers.vehicleToMap(vehicle.copy(updatedAt = clock()), forUpdate = true)
        // userId is immutable under the rules; never re-send id/userId changes beyond their current values.
        vehicles().document(vehicle.id).set(FirestoreValueCodec.encodeForUpdate(map), SetOptions.merge()).await()
    }

    override suspend fun deleteVehicle(vehicleId: String) {
        vehicles().document(vehicleId)
            .set(FirestoreValueCodec.encode(FirestoreMappers.tombstoneFields(clock())) as Map<*, *>, SetOptions.merge())
            .await()
        if (_active.value == vehicleId) {
            _active.value = null
            runCatching { prefs?.edit()?.remove(PREF_ACTIVE)?.apply() }
        }
        // Best effort: the tombstone already hides the vehicle; a failed purge is healed by retryPendingPurges().
        scope.launch {
            runCatching { purge(vehicleId) }.onFailure { crash.record(it) }
        }
    }

    /** Re-purges any still-tombstoned vehicle (e.g. an offline delete or a failed callable). */
    suspend fun retryPendingPurges() {
        val uid = auth.currentUser.value?.uid ?: return
        runCatching {
            val docs = vehicles().whereEqualTo("userId", uid).limit(20).get().await().documents
            for (d in docs.filter { it.get("deletedAt") != null }) {
                runCatching { purge(d.id) }.onFailure { crash.record(it) }
            }
        }.onFailure { crash.record(it) }
    }

    private companion object {
        const val PREF_ACTIVE = "active_vehicle_id"
    }
}
