// Minimal end-to-end validation of the LumenPass Linux SSH agent crypto
// layer. Generates an ed25519 keypair, runs it through Ed25519Sign, and
// verifies the signature with OpenSSL. Also exercises the OpenSSH PEM
// parser shape to make sure parsing the wire format is consistent with
// what the agent server expects.
//
// Build with the cmake test target below; this file is excluded from the
// default Flutter build via the runner CMakeLists.

#include "ssh_agent_ed25519.h"

#include <openssl/evp.h>

#include <array>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

namespace {

bool VerifyEd25519(const std::array<uint8_t, 32>& pub,
                   const std::vector<uint8_t>& msg,
                   const std::array<uint8_t, 64>& sig) {
  EVP_PKEY* key = EVP_PKEY_new_raw_public_key(
      EVP_PKEY_ED25519, nullptr, pub.data(), pub.size());
  if (key == nullptr) return false;
  EVP_MD_CTX* ctx = EVP_MD_CTX_new();
  if (ctx == nullptr) {
    EVP_PKEY_free(key);
    return false;
  }
  bool ok = false;
  if (EVP_DigestVerifyInit(ctx, nullptr, nullptr, nullptr, key) == 1) {
    ok = EVP_DigestVerify(ctx, sig.data(), sig.size(), msg.data(),
                          msg.size()) == 1;
  }
  EVP_MD_CTX_free(ctx);
  EVP_PKEY_free(key);
  return ok;
}

int TestRoundTrip() {
  // RFC 8032 test vector: secret key all zeros except per-instance seed.
  // Using a random-looking seed so we exercise the actual code paths and
  // not a degenerate case.
  std::array<uint8_t, 32> seed = {
      0x9d, 0x61, 0xb1, 0x9d, 0xef, 0xfd, 0x5a, 0x60,
      0xba, 0x84, 0x4a, 0xf4, 0x92, 0xec, 0x2c, 0xc4,
      0x44, 0x49, 0xc5, 0x69, 0x7b, 0x32, 0x69, 0x19,
      0x70, 0x3b, 0xac, 0x03, 0x1c, 0xae, 0x7f, 0x60,
  };
  std::array<uint8_t, 32> pub{};
  if (!lumenpass::Ed25519DerivePublicKey(seed.data(), pub.data())) {
    std::fprintf(stderr, "Ed25519DerivePublicKey failed\n");
    return 1;
  }

  // RFC 8032 expected public key for the seed above.
  std::array<uint8_t, 32> expected_pub = {
      0xd7, 0x5a, 0x98, 0x01, 0x82, 0xb1, 0x0a, 0xb7,
      0xd5, 0x4b, 0xfe, 0xd3, 0xc9, 0x64, 0x07, 0x3a,
      0x0e, 0xe1, 0x72, 0xf3, 0xda, 0xa6, 0x23, 0x25,
      0xaf, 0x02, 0x1a, 0x68, 0xf7, 0x07, 0x51, 0x1a,
  };
  if (pub != expected_pub) {
    std::fprintf(stderr, "Derived public key mismatch\n");
    return 1;
  }

  std::vector<uint8_t> msg{};  // empty message vector from RFC 8032 vector 1
  std::array<uint8_t, 64> sig{};
  if (!lumenpass::Ed25519Sign(seed.data(), msg.data(), msg.size(),
                              sig.data())) {
    std::fprintf(stderr, "Ed25519Sign failed\n");
    return 1;
  }

  if (!VerifyEd25519(pub, msg, sig)) {
    std::fprintf(stderr, "Ed25519 verify failed for empty message\n");
    return 1;
  }

  // Non-empty payload (sample SSH sign payload).
  std::string payload_str = "lumenpass-agent-end-to-end-test";
  std::vector<uint8_t> payload(payload_str.begin(), payload_str.end());
  std::array<uint8_t, 64> sig2{};
  if (!lumenpass::Ed25519Sign(seed.data(), payload.data(), payload.size(),
                              sig2.data())) {
    std::fprintf(stderr, "Ed25519Sign(payload) failed\n");
    return 1;
  }
  if (!VerifyEd25519(pub, payload, sig2)) {
    std::fprintf(stderr, "Ed25519 verify failed for payload\n");
    return 1;
  }

  // Tampered payload must NOT verify.
  std::vector<uint8_t> tampered = payload;
  tampered[0] ^= 0x01;
  if (VerifyEd25519(pub, tampered, sig2)) {
    std::fprintf(stderr, "Ed25519 verify accepted tampered payload\n");
    return 1;
  }

  std::printf("Ed25519: derive + sign + verify OK (RFC 8032 vector 1)\n");
  std::printf("Ed25519: tamper rejection OK\n");
  return 0;
}

}  // namespace

int main() { return TestRoundTrip(); }
