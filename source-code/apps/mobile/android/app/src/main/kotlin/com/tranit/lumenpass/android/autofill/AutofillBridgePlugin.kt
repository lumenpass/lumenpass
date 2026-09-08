package com.tranit.lumenpass.android.autofill

import android.app.Activity
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.view.autofill.AutofillManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AutofillBridgePlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    private var channel: MethodChannel? = null
    private var applicationContext: Context? = null
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@AutofillBridgePlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        applicationContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }
    override fun onDetachedFromActivity() { activity = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error("NO_CONTEXT", "Plugin not attached", null)
            return
        }

        when (call.method) {
            "getStatus" -> result.success(statusFor(context))
            "syncCredentials" -> {
                @Suppress("UNCHECKED_CAST")
                val list = call.argument<List<Map<String, Any?>>>("credentials") ?: emptyList()
                val credentials = list.mapNotNull { m ->
                    val id = m["id"] as? String ?: return@mapNotNull null
                    val password = (m["password"] as? String) ?: ""
                    val pkCred = (m["passkeyCredentialIdB64url"] as? String)?.trim().orEmpty()
                    val pkPem = (m["passkeyPrivateKeyPem"] as? String)?.trim().orEmpty()
                    val pkRp = (m["passkeyRpId"] as? String)?.trim().orEmpty()
                    val canPasskey = pkCred.isNotEmpty() && pkPem.isNotEmpty() && pkRp.isNotEmpty()
                    if (password.isEmpty() && (m["username"] as? String).isNullOrBlank() && !canPasskey) {
                        return@mapNotNull null
                    }
                    AutofillCredential(
                        id = id,
                        title = (m["title"] as? String) ?: "",
                        username = (m["username"] as? String) ?: "",
                        password = password,
                        url = (m["url"] as? String) ?: "",
                        otpAuthUrl = m["otpAuthUrl"] as? String,
                        hasPasskey = (m["hasPasskey"] as? Boolean) == true,
                        passkeyCredentialIdB64url = pkCred.ifBlank { null },
                        passkeyPrivateKeyPem = pkPem.ifBlank { null },
                        passkeyRpId = pkRp.ifBlank { null },
                        passkeyUserHandleB64url = (m["passkeyUserHandleB64url"] as? String)?.trim()?.ifBlank { null },
                    )
                }
                SharedCredentialStore(context).save(credentials)
                result.success(null)
            }
            "clearCredentials" -> {
                SharedCredentialStore(context).clear()
                result.success(null)
            }
            "openSystemSettings" -> {
                val ok = openSystemSettings(context)
                result.success(ok)
            }
            "getChromeThirdPartyMode" -> {
                val pkg = call.argument<String>("package") ?: CHROME_STABLE_PACKAGE
                result.success(getChromeThirdPartyMode(context, pkg))
            }
            "openChromeAutofillSettings" -> {
                val pkg = call.argument<String>("package")
                val ok = openChromeAutofillSettings(context, pkg)
                result.success(ok)
            }
            else -> result.notImplemented()
        }
    }

    private fun statusFor(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return "notSupported"
        val manager = context.getSystemService(AutofillManager::class.java) ?: return "notSupported"
        if (!manager.isAutofillSupported) return "notSupported"
        return if (manager.hasEnabledAutofillServices()) "enabled" else "disabled"
    }

    private fun openSystemSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val launcher: Context = activity ?: context

        // Build an ordered list of intents to try.
        //
        // ACTION_REQUEST_SET_AUTOFILL_SERVICE has two distinct behaviours:
        //   * With `data = package:<us>` it asks the system to make LumenPass
        //     the active autofill service. If we're NOT the active service it
        //     shows a confirmation dialog (nice for enabling). But if we're
        //     ALREADY the active service the picker returns RESULT_OK and
        //     finishes immediately without showing any UI — so the button
        //     appears to do nothing.
        //   * Without any data it opens the autofill service picker list,
        //     letting the user view/switch/disable providers regardless of the
        //     current state.
        //
        // So only use the targeted (package) intent when we still need the user
        // to enable us; otherwise open the picker so there's always visible UI.
        val enabled = statusFor(context) == "enabled"
        val intents = buildList {
            if (!enabled) {
                add(
                    Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE).apply {
                        data = Uri.parse("package:${context.packageName}")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                )
            }
            add(
                Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            add(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }

        for (intent in intents) {
            try {
                launcher.startActivity(intent)
                return true
            } catch (e: Throwable) {
                Log.d(TAG, "Failed to open autofill settings via $intent", e)
            }
        }
        return false
    }

    private fun getChromeThirdPartyMode(context: Context, chromePackage: String): String {
        return try {
            val uri = Uri.Builder()
                .scheme(ContentResolver.SCHEME_CONTENT)
                .authority(chromePackage + CONTENT_PROVIDER_NAME)
                .path(THIRD_PARTY_MODE_PATH)
                .build()

            val cursor = context.contentResolver.query(
                uri,
                arrayOf(THIRD_PARTY_MODE_COLUMN),
                null,
                null,
                null,
            )

            if (cursor == null) return "unknown"

            cursor.use {
                if (!it.moveToFirst()) return@use "unknown"
                val index = it.getColumnIndex(THIRD_PARTY_MODE_COLUMN)
                if (index == -1) return@use "unknown"
                if (it.getInt(index) == 0) "disabled" else "enabled"
            }
        } catch (e: Throwable) {
            Log.d(TAG, "Cannot query Chrome 3P mode for $chromePackage", e)
            "unknown"
        }
    }

    private fun openChromeAutofillSettings(context: Context, chromePackage: String?): Boolean {
        val intent = Intent(Intent.ACTION_APPLICATION_PREFERENCES).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_APP_BROWSER)
            addCategory(Intent.CATEGORY_PREFERENCE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (!chromePackage.isNullOrBlank()) {
                setPackage(chromePackage)
            }
        }
        val launcher: Context = activity ?: context
        return try {
            if (chromePackage.isNullOrBlank()) {
                launcher.startActivity(Intent.createChooser(intent, "Select Browser").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                })
            } else {
                launcher.startActivity(intent)
            }
            true
        } catch (_: Throwable) {
            false
        }
    }

    companion object {
        private const val TAG = "LumenPassAutofill"
        private const val CHANNEL_NAME = "lumenpass/autofill"
        private const val CHROME_STABLE_PACKAGE = "com.android.chrome"
        private const val CONTENT_PROVIDER_NAME = ".AutofillThirdPartyModeContentProvider"
        private const val THIRD_PARTY_MODE_COLUMN = "autofill_third_party_state"
        private const val THIRD_PARTY_MODE_PATH = "autofill_third_party_mode"
    }
}
