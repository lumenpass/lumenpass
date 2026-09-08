package com.tranit.lumenpass.android.autofill

import android.app.assist.AssistStructure
import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.InlinePresentation
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.util.Log
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import android.widget.inline.InlinePresentationSpec
import androidx.annotation.RequiresApi
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import com.tranit.lumenpass.android.R

@RequiresApi(Build.VERSION_CODES.O)
class LumenPassAutofillService : AutofillService() {

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback,
    ) {
        Log.d(TAG, ">>> onFillRequest called")

        val contexts = request.fillContexts
        val structure = contexts.lastOrNull()?.structure
        if (structure == null) {
            Log.d(TAG, "  structure is null – returning null")
            callback.onSuccess(null)
            return
        }

        Log.d(TAG, "  activityComponent=${structure.activityComponent}")
        Log.d(TAG, "  windowNodeCount=${structure.windowNodeCount}")

        val parsed = parse(structure)
        Log.d(TAG, "  parsed: domain=${parsed.domain} pkg=${parsed.packageName} " +
            "usernameId=${parsed.usernameId} passwordId=${parsed.passwordId}")

        if (parsed.usernameId == null && parsed.passwordId == null) {
            Log.d(TAG, "  no username/password fields found – returning null")
            callback.onSuccess(null)
            return
        }

        val store = SharedCredentialStore(applicationContext).load()
        Log.d(TAG, "  credential store size=${store.size}")
        if (store.isEmpty()) {
            Log.d(TAG, "  store is empty – returning null")
            callback.onSuccess(null)
            return
        }

        val matches = matchCredentials(parsed, store)
        Log.d(TAG, "  matched credentials: ${matches.size}")
        if (matches.isEmpty()) {
            Log.d(TAG, "  no matches – returning null")
            callback.onSuccess(null)
            return
        }

        val inlineSpecs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            request.inlineSuggestionsRequest?.inlinePresentationSpecs
        } else null
        Log.d(TAG, "  inlineSpecs count=${inlineSpecs?.size ?: 0}")

        val responseBuilder = FillResponse.Builder()
        var datasetCount = 0
        matches.forEachIndexed { index, credential ->
            val spec = inlineSpecs?.getOrNull(index.coerceAtMost((inlineSpecs.size - 1).coerceAtLeast(0)))
            val dataset = buildDataset(parsed, credential, spec)
            if (dataset != null) {
                responseBuilder.addDataset(dataset)
                datasetCount++
            }
        }
        Log.d(TAG, "  returning FillResponse with $datasetCount datasets")
        callback.onSuccess(responseBuilder.build())
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        callback.onSuccess()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Parsing
    // ─────────────────────────────────────────────────────────────────────────

    private data class Parsed(
        val domain: String?,
        val packageName: String?,
        val usernameId: AutofillId?,
        val passwordId: AutofillId?,
    )

    private fun parse(structure: AssistStructure): Parsed {
        var usernameId: AutofillId? = null
        var passwordId: AutofillId? = null
        var domain: String? = null
        val packageName: String? = structure.activityComponent?.packageName

        fun traverse(node: AssistStructure.ViewNode) {
            val webDomain = node.webDomain
            if (!webDomain.isNullOrBlank() && domain.isNullOrBlank()) {
                domain = webDomain.lowercase()
            }

            val hints = node.autofillHints?.toSet() ?: emptySet()

            val htmlAttrs = mutableListOf<String>()
            node.htmlInfo?.let { html ->
                val attrs = html.attributes
                if (attrs != null) {
                    for (pair in attrs) {
                        val key = pair.first?.lowercase() ?: continue
                        val value = pair.second?.lowercase() ?: continue
                        if (key in setOf(
                                "type", "autocomplete", "name", "id",
                                "ua-autofill-hints", "computed-autofill-hints",
                                "crowdsourcing-autofill-hints",
                            )) {
                            htmlAttrs.add(value)
                        }
                    }
                }
            }

            val hintStr = (hints + listOfNotNull(
                node.hint,
                node.idEntry,
            ) + htmlAttrs).joinToString(" ") { it.toString().lowercase() }

            val inputVariation = node.inputType and 0x00000FF0
            val isPasswordByType = inputVariation ==
                android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                inputVariation ==
                android.text.InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                inputVariation ==
                android.text.InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD

            val isPassword = isPasswordByType ||
                hintStr.contains("password") ||
                hintStr.contains("current-password") ||
                hintStr.contains("new-password") ||
                hints.contains(View.AUTOFILL_HINT_PASSWORD)

            val isUsername = hintStr.contains("email") ||
                hintStr.contains("user") ||
                hintStr.contains("login") ||
                hintStr.contains("account") ||
                hints.contains(View.AUTOFILL_HINT_USERNAME) ||
                hints.contains(View.AUTOFILL_HINT_EMAIL_ADDRESS)

            val id = node.autofillId
            if (id != null) {
                if (isPassword && passwordId == null) passwordId = id
                else if (isUsername && usernameId == null) usernameId = id
            }
            for (i in 0 until node.childCount) traverse(node.getChildAt(i))
        }

        for (i in 0 until structure.windowNodeCount) {
            traverse(structure.getWindowNodeAt(i).rootViewNode)
        }

        return Parsed(
            domain = domain,
            packageName = packageName,
            usernameId = usernameId,
            passwordId = passwordId,
        )
    }

    private fun matchCredentials(
        parsed: Parsed,
        credentials: List<AutofillCredential>,
    ): List<AutofillCredential> {
        val targetDomain = parsed.domain
        val targetPackage = parsed.packageName?.lowercase()

        val scored = credentials.map { c ->
            val cDomain = c.domain
            val score = when {
                targetDomain != null && cDomain.isNotEmpty() &&
                    (cDomain.contains(targetDomain) || targetDomain.contains(cDomain)) -> 3
                targetPackage != null && cDomain.isNotEmpty() &&
                    targetPackage.contains(cDomain) -> 2
                else -> 0
            }
            c to score
        }
        val strong = scored.filter { it.second > 0 }.sortedByDescending { it.second }
        return if (strong.isNotEmpty()) {
            strong.map { it.first }
        } else {
            credentials
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dataset construction
    // ─────────────────────────────────────────────────────────────────────────

    private fun buildDataset(
        parsed: Parsed,
        credential: AutofillCredential,
        inlineSpec: InlinePresentationSpec?,
    ): Dataset? {
        val packageName = packageName ?: return null

        val title = credential.title.ifBlank { credential.url.ifBlank { credential.username } }
        val subtitle = credential.username.ifBlank { credential.url }

        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_2)
        presentation.setTextViewText(android.R.id.text1, title)
        presentation.setTextViewText(android.R.id.text2, subtitle)

        val builder = Dataset.Builder(presentation)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlineSpec != null) {
            try {
                val imeStyle = inlineSpec.style
                if (UiVersions.getVersions(imeStyle).contains(UiVersions.INLINE_UI_VERSION_1)) {
                    val attribution = PendingIntent.getActivity(
                        this, 0,
                        Intent(this, Class.forName("com.tranit.lumenpass.android.MainActivity")),
                        PendingIntent.FLAG_IMMUTABLE,
                    )
                    val slice = InlineSuggestionUi
                        .newContentBuilder(attribution)
                        .setTitle(title)
                        .setSubtitle(subtitle)
                        .setStartIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
                        .build()
                        .slice
                    builder.setInlinePresentation(
                        InlinePresentation(slice, inlineSpec, false)
                    )
                    Log.d(TAG, "  inline presentation set for: $title")
                }
            } catch (e: Throwable) {
                Log.w(TAG, "  inline presentation failed", e)
            }
        }

        var added = false
        parsed.usernameId?.let {
            builder.setValue(it, AutofillValue.forText(credential.username))
            added = true
        }
        parsed.passwordId?.let {
            builder.setValue(it, AutofillValue.forText(credential.password))
            added = true
        }
        return if (added) builder.build() else null
    }

    companion object {
        private const val TAG = "LumenPassAutofill"
    }
}
