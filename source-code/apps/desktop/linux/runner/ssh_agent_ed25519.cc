// Ed25519 signing for the LumenPass Linux SSH agent.
//
// Uses OpenSSL libcrypto (>= 1.1.1) for ed25519 operations and SHA-512.
// Linux ships libcrypto everywhere we care about (Debian/Ubuntu, Fedora,
// Arch), so we link against the system library instead of vendoring a
// reference implementation.

#include "ssh_agent_ed25519.h"

#include <openssl/evp.h>

#include <cstring>

namespace lumenpass {

bool Ed25519DerivePublicKey(const uint8_t seed[32], uint8_t public_key[32]) {
  if (seed == nullptr || public_key == nullptr) return false;
  EVP_PKEY* pkey = EVP_PKEY_new_raw_private_key(
      EVP_PKEY_ED25519, nullptr, seed, 32);
  if (pkey == nullptr) return false;
  size_t out_len = 32;
  int ok = EVP_PKEY_get_raw_public_key(pkey, public_key, &out_len);
  EVP_PKEY_free(pkey);
  return ok == 1 && out_len == 32;
}

bool Ed25519Sign(const uint8_t seed[32],
                 const uint8_t* message,
                 size_t message_len,
                 uint8_t signature[64]) {
  if (seed == nullptr || signature == nullptr) return false;
  if (message == nullptr && message_len != 0) return false;

  EVP_PKEY* pkey = EVP_PKEY_new_raw_private_key(
      EVP_PKEY_ED25519, nullptr, seed, 32);
  if (pkey == nullptr) return false;

  EVP_MD_CTX* ctx = EVP_MD_CTX_new();
  if (ctx == nullptr) {
    EVP_PKEY_free(pkey);
    return false;
  }

  bool ok = false;
  do {
    if (EVP_DigestSignInit(ctx, nullptr, nullptr, nullptr, pkey) != 1) break;
    size_t sig_len = 64;
    if (EVP_DigestSign(ctx, signature, &sig_len,
                       message, message_len) != 1) {
      break;
    }
    if (sig_len != 64) break;
    ok = true;
  } while (false);

  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(pkey);
  return ok;
}

}  // namespace lumenpass
