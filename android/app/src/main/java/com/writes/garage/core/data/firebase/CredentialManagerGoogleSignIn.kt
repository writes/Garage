package com.writes.garage.core.data.firebase

import android.content.Context
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.writes.garage.core.data.GoogleSignInProvider

/**
 * Google sign-in through Credential Manager. The web client id is the `default_web_client_id` string resource
 * that the google-services plugin generates from `google-services.json` (present only when the project has
 * Google sign-in enabled). When it is absent, [create] returns null and the sign-in button stays hidden.
 */
class CredentialManagerGoogleSignIn private constructor(private val serverClientId: String) : GoogleSignInProvider {

    override suspend fun requestIdToken(activityContext: Context): String {
        val option = GetGoogleIdOption.Builder()
            .setServerClientId(serverClientId)
            .setFilterByAuthorizedAccounts(false)
            .setAutoSelectEnabled(false)
            .build()
        val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
        val credential = CredentialManager.create(activityContext).getCredential(activityContext, request).credential
        if (credential is CustomCredential && credential.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
            return GoogleIdTokenCredential.createFrom(credential.data).idToken
        }
        throw IllegalStateException("Unexpected credential type: ${credential.type}")
    }

    companion object {
        /** Null when the project has no `default_web_client_id` (Google provider not configured). */
        fun create(context: Context): CredentialManagerGoogleSignIn? {
            val id = context.resources.getIdentifier("default_web_client_id", "string", context.packageName)
            if (id == 0) return null
            val value = context.getString(id)
            return value.takeIf { it.isNotBlank() }?.let(::CredentialManagerGoogleSignIn)
        }
    }
}
