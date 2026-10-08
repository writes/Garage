package com.writes.garage.core.data.firebase

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.writes.garage.core.data.VehicleRecordRepository
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import java.util.UUID

/** How one record type maps onto `vehicles/{vehicleId}/<collection>/{id}`. */
class RecordCodec<T>(
    val collection: String,
    val id: (T) -> String,
    val vehicleId: (T) -> String,
    val withId: (T, String) -> T,
    val toMap: (T) -> Map<String, Any?>,
    val fromMap: (docId: String, vehicleId: String, map: Map<String, Any?>) -> T?,
    val limit: Long = 500,
)

/** Generic Firestore implementation; the vehicle owner check lives in the rules (subcollection write = owner only). */
class FirestoreRecordRepository<T>(
    private val db: FirebaseFirestore,
    private val codec: RecordCodec<T>,
) : VehicleRecordRepository<T> {
    private fun col(vehicleId: String) = db.collection("${FirestorePaths.VEHICLES}/$vehicleId/${codec.collection}")

    override fun observe(vehicleId: String): Flow<List<T>> = callbackFlow {
        val reg = col(vehicleId).limit(codec.limit).addSnapshotListener { snap, err ->
            if (err != null) {
                close(err)
                return@addSnapshotListener
            }
            trySend(
                snap?.documents.orEmpty().mapNotNull { d ->
                    codec.fromMap(d.id, vehicleId, FirestoreValueCodec.decodeMap(d.data))
                },
            )
        }
        awaitClose { reg.remove() }
    }

    override suspend fun upsert(item: T): T {
        val saved = if (codec.id(item).isBlank()) codec.withId(item, UUID.randomUUID().toString()) else item
        // Merge write: nulls clear the field, fields this client does not model survive.
        col(codec.vehicleId(saved)).document(codec.id(saved))
            .set(FirestoreValueCodec.encodeForUpdate(codec.toMap(saved)), SetOptions.merge()).await()
        return saved
    }

    override suspend fun delete(vehicleId: String, id: String) {
        col(vehicleId).document(id).delete().await()
    }
}

/** Codecs for the six record collections. */
object RecordCodecs {
    val gallery = RecordCodec<com.writes.garage.core.model.GalleryPhoto>(
        FirestorePaths.GALLERY, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::galleryToMap, RecordMappers::galleryFromMap,
    )
    val warranties = RecordCodec<com.writes.garage.core.model.Warranty>(
        FirestorePaths.WARRANTIES, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::warrantyToMap, RecordMappers::warrantyFromMap, limit = 20,
    )
    val parts = RecordCodec<com.writes.garage.core.model.SparePart>(
        FirestorePaths.PARTS_INVENTORY, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::partToMap, RecordMappers::partFromMap,
    )
    val detailing = RecordCodec<com.writes.garage.core.model.DetailingRecord>(
        FirestorePaths.DETAILING, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::detailingToMap, RecordMappers::detailingFromMap,
    )
    val recalls = RecordCodec<com.writes.garage.core.model.Recall>(
        FirestorePaths.RECALLS, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::recallToMap, RecordMappers::recallFromMap, limit = 50,
    )
    val wear = RecordCodec<com.writes.garage.core.model.WearSnapshot>(
        FirestorePaths.WEAR_SNAPSHOTS, { it.id }, { it.vehicleId }, { x, i -> x.copy(id = i) },
        RecordMappers::wearToMap, RecordMappers::wearFromMap,
    )
}
