# Security Policy

LumenPass is a password manager and security reports may affect encrypted vaults, credentials, cloud synchronization, AutoFill, passkeys, or platform integrations. Please report vulnerabilities privately and allow time for investigation before public disclosure.

## Reporting a vulnerability

Email **staff@lumenpass.app** with the subject `LumenPass security report`.

Include, when available:

- the affected platform, app version, and commit;
- a clear description of the issue and its security impact;
- reproduction steps or a minimal proof of concept;
- whether exploitation requires local access, an unlocked vault, user interaction, or network control;
- relevant logs or screenshots with all secrets and personal data removed;
- any suggested mitigation.

Do not include real vault files, master passwords, recovery material, access tokens, private keys, or other user secrets. Create synthetic test data instead.

## Disclosure expectations

- Do not open a public issue for an unpatched vulnerability.
- Do not access, modify, or retain data that does not belong to you.
- Do not perform denial-of-service testing against production services or third-party providers.
- Give maintainers a reasonable opportunity to investigate and prepare a fix before disclosure.

We will make a best effort to acknowledge a complete report, assess its impact, and coordinate remediation and disclosure. This document does not create a bug-bounty program or promise compensation.

## Supported versions

Security fixes are targeted at the latest source revision and current release line. Older releases may not receive fixes; users should upgrade to the latest available version.

## Scope notes

Provider authentication failures caused solely by Google, Dropbox, Microsoft, WebDAV, SFTP, S3, Apple, Android, browser, or operating-system services may need to be reported to the relevant upstream vendor. Reports showing an unsafe interaction in LumenPass remain welcome.
