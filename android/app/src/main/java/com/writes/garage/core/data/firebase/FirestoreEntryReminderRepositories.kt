package com.writes.garage.core.data.firebase

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.SetOptions
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.EntryRepository
import com.writes.garage.core.data.ReminderRepository
import com.writes.garage.core.model.Entry
import com.writes.garage.core.model.Reminder
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.tasks.await
import java.time.Instant
import java.util.UUID

/** `vehicles/{vehicleId}/entries/{id}`. The vehicle owner check lives in the rules (subcollection write = owner only). */
class FirestoreEntryRepository(
    private val db: FirebaseFirestore,
    private val auth: AuthRepository,
    private val clock: () -> Instant = Instant::now,
) : EntryRepository {
    /** Mirrors iOS `maxLogEntries`; the Log shows the most recent N. */
    private val maxEntries = 500L

    private fun col(vehicleId: String) = db.collection(FirestorePaths.vehicleEntries(vehicleId))

    override fun observeEntries(vehicleId: String): Flow<List<Entry>> = callbackFlow {
        val reg = col(vehicleId).orderBy("entryDate", Query.Direction.DESCENDING).limit(maxEntries)
            .addSnapshotListener { snap, err ->
                if (err != null) {
                    close(err)
                    return@addSnapshotListener
                }
                trySend(
                    snap?.documents.orEmpty().mapNotNull { d ->
                        FirestoreMappers.entryFromMap(d.id, vehicleId, FirestoreValueCodec.decodeMap(d.data))
                    },
                )
            }
        awaitClose { reg.remove() }
    }

    override fun observeEntry(vehicleId: String, entryId: String): Flow<Entry?> = callbackFlow {
        val reg = col(vehicleId).document(entryId).addSnapshotListener { snap, err ->
            if (err != null) {
                close(err)
                return@addSnapshotListener
            }
            trySend(snap?.takeIf { it.exists() }?.let {
                FirestoreMappers.entryFromMap(it.id, vehicleId, FirestoreValueCodec.decodeMap(it.data))
            })
        }
        awaitClose { reg.remove() }
    }.map { it }

    override suspend fun addEntry(entry: Entry): Entry {
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        val now = clock()
        val created = entry.copy(
            id = entry.id.ifBlank { UUID.randomUUID().toString() }, userId = uid, createdAt = now, updatedAt = now,
        )
        col(created.vehicleId).document(created.id)
            .set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.entryToMap(created))).await()
        return created
    }

    override suspend fun updateEntry(entry: Entry) {
        val map = FirestoreMappers.entryToMap(entry.copy(updatedAt = clock()), forUpdate = true)
        val data = FirestoreValueCodec.encodeForUpdate(map)
        // mergeFields (top-level) replaces `details` wholesale: a plain merge deep-merges nested maps and would
        // leave cleared fields and the previous type's keys on the server.
        col(entry.vehicleId).document(entry.id).set(data, SetOptions.mergeFields(data.keys.toList())).await()
    }

    override suspend fun deleteEntry(vehicleId: String, entryId: String) {
        col(vehicleId).document(entryId).delete().await()
    }
}

/** `vehicles/{vehicleId}/reminders/{id}`. */
class FirestoreReminderRepository(
    private val db: FirebaseFirestore,
    private val clock: () -> Instant = Instant::now,
) : ReminderRepository {
    private fun col(vehicleId: String) = db.collection(FirestorePaths.vehicleReminders(vehicleId))

    override fun observeReminders(vehicleId: String): Flow<List<Reminder>> = callbackFlow {
        val reg = col(vehicleId).addSnapshotListener { snap, err ->
            if (err != null) {
                close(err)
                return@addSnapshotListener
            }
            trySend(
                snap?.documents.orEmpty().mapNotNull { d ->
                    FirestoreMappers.reminderFromMap(d.id, vehicleId, FirestoreValueCodec.decodeMap(d.data))
                },
            )
        }
        awaitClose { reg.remove() }
    }

    override suspend fun addReminder(reminder: Reminder): Reminder {
        val created = reminder.copy(id = reminder.id.ifBlank { UUID.randomUUID().toString() }, createdAt = clock())
        col(created.vehicleId).document(created.id)
            .set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.reminderToMap(created))).await()
        return created
    }

    override suspend fun updateReminder(reminder: Reminder) {
        val map = FirestoreMappers.reminderToMap(reminder, forUpdate = true)
        col(reminder.vehicleId).document(reminder.id).set(FirestoreValueCodec.encodeForUpdate(map), SetOptions.merge()).await()
    }

    override suspend fun completeReminder(vehicleId: String, reminderId: String) {
        col(vehicleId).document(reminderId)
            .set(mapOf("completedAt" to FirestoreValueCodec.encode(clock())), SetOptions.merge()).await()
    }

    override suspend fun deleteReminder(vehicleId: String, reminderId: String) {
        col(vehicleId).document(reminderId).delete().await()
    }
}
