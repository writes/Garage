package com.writes.garage.core.data

import com.writes.garage.core.model.Reminder
import kotlinx.coroutines.flow.Flow

interface ReminderRepository {
    fun observeReminders(vehicleId: String): Flow<List<Reminder>>

    suspend fun addReminder(reminder: Reminder): Reminder

    suspend fun updateReminder(reminder: Reminder)

    suspend fun completeReminder(vehicleId: String, reminderId: String)

    suspend fun deleteReminder(vehicleId: String, reminderId: String)
}
