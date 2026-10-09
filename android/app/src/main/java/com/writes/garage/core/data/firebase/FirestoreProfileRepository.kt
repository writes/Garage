package com.writes.garage.core.data.firebase

import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.SetOptions
import com.writes.garage.core.data.AuthRepository
import com.writes.garage.core.data.ProfileRepository
import com.writes.garage.core.model.UserProfile
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.tasks.await
import java.time.Instant

/**
 * `users/{uid}` client-owned fields. `subscription`, `vehicleCount` and `lastVehicleOp` are server/batch owned and
 * are never written here (the rules would reject it).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class FirestoreProfileRepository(
    private val db: FirebaseFirestore,
    private val auth: AuthRepository,
    private val clock: () -> Instant = Instant::now,
) : ProfileRepository {
    private fun doc(uid: String) = db.collection(FirestorePaths.USERS).document(uid)

    override fun observeProfile(): Flow<UserProfile?> = auth.currentUser.flatMapLatest { user ->
        if (user == null) {
            flowOf(null)
        } else {
            callbackFlow {
                val reg = doc(user.uid).addSnapshotListener { snap, err ->
                    if (err != null) {
                        close(err)
                        return@addSnapshotListener
                    }
                    val data = FirestoreValueCodec.decodeMap(snap?.data)
                    trySend(FirestoreMappers.profileFromMap(user.uid, user.email, data))
                }
                awaitClose { reg.remove() }
            }
        }
    }

    override suspend fun updateProfile(profile: UserProfile) {
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        doc(uid).set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.profileFormFields(profile, clock())), SetOptions.merge()).await()
    }

    override suspend fun setAnalyticsOptOut(optOut: Boolean) {
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        doc(uid).set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.analyticsOptOutFields(optOut, clock())), SetOptions.merge()).await()
    }

    override suspend fun setThemeId(themeId: String?) {
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        doc(uid).set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.themeFields(themeId, clock())), SetOptions.merge()).await()
    }

    override suspend fun setAiConsent(granted: Boolean) {
        val uid = auth.currentUser.value?.uid ?: error("Not signed in")
        doc(uid).set(FirestoreValueCodec.encodeForCreate(FirestoreMappers.aiConsentFields(granted, clock())), SetOptions.merge()).await()
    }
}
