# Portable remediation-prompt contract

Read **only after** the user has resolved findings. If they have not, go back and ask.

## Gate

Include a finding only if the user marked it **Accepted**, **Accepted with constraints**, or **Needs reproduction** (validation work only).

Never include: rejected findings · informational findings · unresolved subjective decisions · anything the user did not explicitly resolve · your own recommendations that were never accepted.

If the user authorises "a defined subset", restate the subset back to them before generating.

## Agent-neutral

The prompt is handed to whichever agent the user chooses — Claude Code, Codex, something else. It must not assume: Superpowers · a planning mode · a subagent system · Claude- or Codex-specific commands · a particular IDE · any access to this conversation.

Self-contained. The receiving agent has none of your context.

## Required contents

- Repositories and projects in scope (absolute paths)
- Objective, and explicit **non**-objectives
- Accepted findings, each with its evidence
- Accepted constraints, verbatim
- Exact rule IDs, owning analyzer, analyzer version
- Relevant file paths and the configuration precedence that produced the effective severity
- Findings authorised for **reproduction only**, marked as such
- Changes explicitly **permitted**
- Changes explicitly **prohibited**
- Intended modern-C# policy
- Test-specific policy
- Required validation commands and expected outcomes
- Completion criteria
- Final-report requirements

## Required instructions to the receiving agent

- **Independently verify the evidence before changing anything.** This handoff is context and authorisation — not permission to follow stale conclusions blindly.
- **Stop and report if repository evidence contradicts the audit.** Do not reconcile silently.
- Do not perform unrelated cleanup or scope expansion.
- Preserve unrelated existing changes; do not revert or stash work you did not create.

## Variants

| Variant | Use |
|---|---|
| **Configuration remediation** | Analyzer versions, `.editorconfig`, MSBuild properties, severities, suppressions, test scoping. **Default** when the audit is about governance. |
| **Code remediation** | Accepted correctness/maintainability findings needing code changes. |
| **Validation only** | Reproduce disputed findings or trial an upgrade, with no durable change. |
| **Combined** | Config + code together. Only on explicit request — mixed changes are harder to review and attribute. |

## Output

Write to `<vault>\Claude\Prompts\`, and show the user the path. The prompt has to survive the death of this session — that is the entire point of it being portable.
