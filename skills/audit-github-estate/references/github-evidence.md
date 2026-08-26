# GitHub evidence contract

Use API version `2026-03-10`. Capture every `gh api` call as exit code, HTTP status,
and response body. Check the exit code before decoding the body; `gh` can print an
error body to stdout. A failed call or missing applicable field is `UNKNOWN`, never a
disabled control or an empty queue.

## Endpoint and visibility rules

GitHub's repository and configuration APIs use different names for some controls:

| Effective repository field | Configuration counterpart | Public | Private/internal |
|---|---|---|---|
| `code_security` | `code_security` | `enabled` | `disabled` |
| `secret_scanning` | `secret_scanning` | `enabled` | `disabled` |
| `secret_scanning_push_protection` | `secret_scanning_push_protection` | `enabled` | `disabled` |
| `secret_scanning_ai_detection` | `secret_scanning_generic_secrets` | `enabled` | `disabled` |
| `secret_scanning_non_provider_patterns` | `secret_scanning_non_provider_patterns` | `enabled` | `disabled` |
| `secret_scanning_validity_checks` | `secret_scanning_validity_checks` | `enabled` | `disabled` |
| `secret_scanning_delegated_alert_dismissal` | `secret_scanning_delegated_alert_dismissal` | `disabled` | `disabled` |
| `secret_scanning_delegated_bypass` | `secret_scanning_delegated_bypass` | `disabled` | `disabled` |

Configuration-only targets:

| Configuration field | Public configuration | Private/internal |
|---|---|---|
| `secret_protection` | `enabled` | `not attached` |
| `code_scanning_default_setup` | `enabled` | `not attached` |
| `code_scanning_delegated_alert_dismissal` | `disabled` | `not attached` |
| `secret_scanning_extended_metadata` | `enabled` | `not attached` |
| `private_vulnerability_reporting` | `enabled` | `not attached` |

Inventory legacy `advanced_security`, but do not use `advanced_security` as a substitute for the individual `code_security` and `secret_protection` fields. Configuration
`secret_protection` and repository secret-scanning children remain separate evidence.

| Evidence | Public | Private/internal |
|---|---|---|
| `GET /repos/{owner}/{repo}` | Derive visibility, owner type, and the secret-scanning fields actually returned. An omitted legacy `code_security` field is not required. | Require effective `code_security`, `secret_scanning`, push protection, non-provider patterns, and validity checks to be disabled. Delegated and AI-detection fields may be omitted and are not evidence gaps. |
| `GET /repos/{owner}/{repo}/code-security-configuration` | Require `200` with `status: attached`; its `id` or `name` must match the separately loaded required public configuration. | Require the documented no-content `204`; `200` is paid configuration drift. |
| Named code-security configuration | Verify every field returned by the named public configuration. `code_security` and `secret_protection` may be omitted; use product-specific endpoints for those products. | Not applicable when unattached. |
| `GET /repos/{owner}/{repo}/code-scanning/default-setup` | Required `state: configured`. | Not queried under the paid-product policy. |
| Code Scanning analyses | Latest successful default-branch analysis uses `commit_sha`; compare it with the live default-branch SHA. | Not queried under the paid-product policy. |
| Actions workflow runs | Latest required run uses `head_sha`; compare it with the live default-branch SHA. | Same. |
| `GET /repos/{owner}/{repo}/code-quality/setup` | Always safe to inspect read-only. Default is `not-configured` without approved paid use. | Same. |
| Code Quality findings/analysis | Query only when paid use and current charges are explicitly approved. | Same. |

Organization Code Quality repository access, enforcement, and displayed price remain
UI-only. When the operator has not supplied them, record `Code Quality org access:
UNVERIFIED (UI-only, awaiting operator)`. Continue read-only repository setup inspection
and every non-Code-Quality surface. Gate Code Quality mutations and paid
findings/analysis queries, not the whole audit.

## Secret-scanning alert capability probe

For each public repository, call
`GET /repos/{owner}/{repo}/secret-scanning/alerts` first. A successful `200` is the
inventory source, including an empty array. If it is unavailable and the owner is an
organization, call `GET /orgs/{org}/secret-scanning/alerts` and filter the response by
exact `repository.full_name`. Classify the inventory as UI-only/UNKNOWN only after every
route available to that owner has failed. Never infer a zero queue from `404`.

## Executable response check

Store captured responses in the sanitized envelope shape used under `test/fixtures/`
and run `scripts/classify-security-evidence.ps1`. The script intentionally accepts
omitted non-applicable fields and fails closed on CLI failure, malformed JSON, stale
`commit_sha`/`head_sha`, or missing applicable evidence.
