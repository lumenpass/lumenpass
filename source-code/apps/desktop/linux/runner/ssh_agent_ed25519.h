#ifndef RUNNER_SSH_AGENT_ED25519_H_
#define RUNNER_SSH_AGENT_ED25519_H_

#include <cstddef>
#include <cstdint>

namespace lumenpass {

bool Ed25519DerivePublicKey(const uint8_t seed[32], uint8_t public_key[32]);

bool Ed25519Sign(const uint8_t seed[32],
                 const uint8_t* message,
                 size_t message_len,
                 uint8_t signature[64]);

}  // namespace lumenpass

#endif  // RUNNER_SSH_AGENT_ED25519_H_
