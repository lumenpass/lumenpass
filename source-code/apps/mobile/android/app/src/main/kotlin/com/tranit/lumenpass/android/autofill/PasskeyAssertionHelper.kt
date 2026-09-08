package com.tranit.lumenpass.android.autofill

import android.util.Base64
import java.security.KeyFactory
import java.security.MessageDigest
import java.security.Signature
import java.security.interfaces.ECPrivateKey
import java.security.spec.PKCS8EncodedKeySpec

/**
 * WebAuthn assertion material compatible with the browser extension
 * (`generatePasskeyAssertion` in service-worker.ts): ES256 over
 * SHA256(authenticatorData || clientDataHash), DER signature, 37-byte
 * authenticatorData (rpIdHash || flags 0x05 || signCount 0).
 */
object PasskeyAssertionHelper {

    data class AssertionParts(
        val credentialId: ByteArray,
        val authenticatorData: ByteArray,
        val signatureDer: ByteArray,
        val userHandle: ByteArray?,
    )

    fun buildAssertion(
        cred: AutofillCredential,
        relyingPartyId: String,
        clientDataHash: ByteArray,
    ): AssertionParts {
        require(cred.canAssertPasskey) { "Credential cannot assert passkey" }
        val rpId = relyingPartyId.trim().lowercase()
        val storedRp = cred.passkeyRpId!!.trim().lowercase()
        require(rpId == storedRp) { "rpId mismatch" }

        val priv = importEcP256PrivateKeyFromPkcs8Pem(cred.passkeyPrivateKeyPem!!)
        val credId = base64UrlDecode(cred.passkeyCredentialIdB64url!!)

        val md = MessageDigest.getInstance("SHA-256")
        val rpIdHash = md.digest(rpId.toByteArray(Charsets.UTF_8))
        val authenticatorData = ByteArray(37)
        System.arraycopy(rpIdHash, 0, authenticatorData, 0, 32)
        authenticatorData[32] = 0x05.toByte()
        // signCount 0 (bytes 33–36 already zero)

        val sigInput = authenticatorData + clientDataHash
        val signature = Signature.getInstance("SHA256withECDSA")
        signature.initSign(priv)
        signature.update(sigInput)
        val sigDer = signature.sign()

        val userHandle = cred.passkeyUserHandleB64url?.trim()?.takeIf { it.isNotEmpty() }?.let {
            base64UrlDecode(it)
        }

        return AssertionParts(
            credentialId = credId,
            authenticatorData = authenticatorData,
            signatureDer = sigDer,
            userHandle = userHandle,
        )
    }

    private fun importEcP256PrivateKeyFromPkcs8Pem(pem: String): ECPrivateKey {
        val body = pem
            .replace("-----BEGIN PRIVATE KEY-----", "")
            .replace("-----END PRIVATE KEY-----", "")
            .replace("\n", "")
            .replace("\r", "")
            .trim()
        val der = Base64.decode(body, Base64.DEFAULT)
        val spec = PKCS8EncodedKeySpec(der)
        val kf = KeyFactory.getInstance("EC")
        return kf.generatePrivate(spec) as ECPrivateKey
    }

    private fun base64UrlDecode(s: String): ByteArray {
        var t = s.trim().replace('-', '+').replace('_', '/')
        val pad = (4 - t.length % 4) % 4
        if (pad > 0) t += "=".repeat(pad)
        return Base64.decode(t, Base64.DEFAULT)
    }
}

private operator fun ByteArray.plus(other: ByteArray): ByteArray {
    val out = ByteArray(this.size + other.size)
    System.arraycopy(this, 0, out, 0, this.size)
    System.arraycopy(other, 0, out, this.size, other.size)
    return out
}
