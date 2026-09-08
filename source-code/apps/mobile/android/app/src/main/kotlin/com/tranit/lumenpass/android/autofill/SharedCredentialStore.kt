package com.tranit.lumenpass.android.autofill

import android.content.Context
import android.util.Log
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Data class describing a single credential cached for autofill.
 */
data class AutofillCredential(
    val id: String,
    val title: String,
    val username: String,
    val password: String,
    val url: String,
    val otpAuthUrl: String? = null,
    val hasPasskey: Boolean = false,
    val passkeyCredentialIdB64url: String? = null,
    val passkeyPrivateKeyPem: String? = null,
    val passkeyRpId: String? = null,
    val passkeyUserHandleB64url: String? = null,
) {
    val canAssertPasskey: Boolean
        get() = hasPasskey &&
            !passkeyCredentialIdB64url.isNullOrBlank() &&
            !passkeyPrivateKeyPem.isNullOrBlank() &&
            !passkeyRpId.isNullOrBlank()

    /** Best-effort extraction of a domain from the credential URL. */
    val domain: String
        get() = when {
            url.isBlank() -> title.lowercase()
            else -> try {
                val parsed = java.net.URI(if (url.contains("://")) url else "https://$url")
                parsed.host?.lowercase()
                    ?: url.substringAfter("://").substringBefore('/').lowercase()
            } catch (_: Throwable) {
                url.lowercase()
            }
        }
}

/**
 * App-private, at-rest-encrypted cache of credentials used by the
 * LumenPass autofill service. Written by the main app on vault unlock,
 * read by [LumenPassAutofillService] on fill requests.
 */
class SharedCredentialStore(private val context: Context) {

    private val file: File
        get() = File(context.noBackupFilesDir, "lumenpass_autofill_credentials.json.enc")

    private fun encryptedFile(): EncryptedFile {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        return EncryptedFile.Builder(
            context,
            file,
            masterKey,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB,
        ).build()
    }

    fun save(credentials: List<AutofillCredential>) {
        if (file.exists()) file.delete()
        try {
            val arr = JSONArray()
            for (c in credentials) {
                val obj = JSONObject()
                    .put("id", c.id)
                    .put("title", c.title)
                    .put("username", c.username)
                    .put("password", c.password)
                    .put("url", c.url)
                    .put("hasPasskey", c.hasPasskey)
                if (!c.otpAuthUrl.isNullOrBlank()) {
                    obj.put("otpAuthUrl", c.otpAuthUrl)
                }
                if (!c.passkeyCredentialIdB64url.isNullOrBlank()) {
                    obj.put("passkeyCredentialIdB64url", c.passkeyCredentialIdB64url)
                }
                if (!c.passkeyPrivateKeyPem.isNullOrBlank()) {
                    obj.put("passkeyPrivateKeyPem", c.passkeyPrivateKeyPem)
                }
                if (!c.passkeyRpId.isNullOrBlank()) {
                    obj.put("passkeyRpId", c.passkeyRpId)
                }
                if (!c.passkeyUserHandleB64url.isNullOrBlank()) {
                    obj.put("passkeyUserHandleB64url", c.passkeyUserHandleB64url)
                }
                arr.put(obj)
            }
            encryptedFile().openFileOutput().use { out ->
                out.write(arr.toString().toByteArray(Charsets.UTF_8))
                out.flush()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to write autofill cache", t)
        }
    }

    fun load(): List<AutofillCredential> {
        if (!file.exists()) return emptyList()
        return try {
            val bytes = encryptedFile().openFileInput().use { it.readBytes() }
            val arr = JSONArray(String(bytes, Charsets.UTF_8))
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    add(
                        AutofillCredential(
                            id = obj.optString("id"),
                            title = obj.optString("title"),
                            username = obj.optString("username"),
                            password = obj.optString("password"),
                            url = obj.optString("url"),
                            otpAuthUrl = obj.optString("otpAuthUrl").ifBlank { null },
                            hasPasskey = obj.optBoolean("hasPasskey", false),
                            passkeyCredentialIdB64url = obj.optString("passkeyCredentialIdB64url").ifBlank { null },
                            passkeyPrivateKeyPem = obj.optString("passkeyPrivateKeyPem").ifBlank { null },
                            passkeyRpId = obj.optString("passkeyRpId").ifBlank { null },
                            passkeyUserHandleB64url = obj.optString("passkeyUserHandleB64url").ifBlank { null },
                        )
                    )
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to read autofill cache", t)
            emptyList()
        }
    }

    fun clear() {
        if (file.exists()) file.delete()
    }

    companion object {
        private const val TAG = "LumenPassAutofill"
    }
}
