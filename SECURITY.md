# Security Policy

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Use [GitHub Private Vulnerability Reporting](https://github.com/caura-ai/caura-cross-fleet-gov/security/advisories/new) — the **"Report a vulnerability"** button on the repo's Security tab. Reports are private to maintainers until a coordinated disclosure.

If you cannot use GitHub Security Advisories, email **security@caura.ai** as a fallback. Mark the subject `[SECURITY]` and expect a slower acknowledgement than the form.

We aim to acknowledge reports within **3 business days**. See the [Caura security policy](https://github.com/caura-ai/caura/blob/main/SECURITY.md) for the full coordinated disclosure process.

Include:
- affected component
- reproduction steps
- potential impact
- suggested mitigation (if known)

## Secrets and Credentials

Never commit live credentials to this repository.
Use environment variables via `.env` and keep `.env` out of version control.

If a credential is exposed:
1. Rotate/revoke it immediately.
2. Replace it with a placeholder.
3. Audit logs for suspicious use.

## Scope

This repository is a reference implementation and is not production hardened by default.
Additional controls are required for production use.
