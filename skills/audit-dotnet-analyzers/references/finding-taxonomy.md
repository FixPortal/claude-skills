# Finding taxonomy, dispositions and report shape

Read when assembling the audit report.

## Fact vs inference vs recommendation

Keep the three visibly separate in every finding. The failure this skill exists to prevent is an inference ("Sonar wants X") presented as a fact.

- **Fact** — observed. A build line, a config entry, a package version, a method signature.
- **Inference** — reasoned from facts. Label it. Give confidence.
- **Recommendation** — what you would do. **Carries no authority.**

If a finding cannot be reproduced, say so plainly. You may name the most likely rule — labelled as inference, not fact.

## Categories

- Incorrect or false-positive rule behaviour
- Stale or incompatible analyzer
- Modern-idiom conflict
- Duplicate or contradictory enforcement
- Inconsistent enforcement (project / test / CI)
- Missing intentional policy
- No action required

## Severity

Critical · High · Medium · Low · Informational

## Every actionable finding carries

Rule ID · rule title · owning analyzer · analyzer version · effective severity · configuration provenance (which layer set it) · affected repos/projects · observed evidence · inference (if any) · technical consequence · recommended disposition · confidence

## Disposition vocabulary

Keep · Keep but clarify · Change severity · Scope away from tests · Disable · Upgrade analyzer · Investigate further

Never recommend disabling a correctness or security rule merely to reduce noise. State the technical basis for any "stale" or "incorrect" label — inconvenience is not a basis.

## Resolution statuses (the user assigns these, not you)

| Status | Eligible for remediation prompt? |
|---|---|
| Accepted | Yes |
| Accepted with constraints | Yes, with the constraints |
| Needs reproduction | Validation work only |
| Subjective decision required | No, unless the user later decides |
| Rejected | No |
| Informational | No |

## Report shape

**Executive conclusion first.** Answer the question that was actually asked, in the first paragraph.

Then:

- **A. Inventory** — table: repo · TFM · LangVersion · SDK · analyzer packages · analysis level · code-style enforcement · warnings-as-errors policy
- **B. Configuration precedence** — which files apply, in what order; flag contradictory, redundant or shadowed settings
- **C. Findings** — taxonomy, severity, disposition, confidence
- **D. Rule-disposition table** — every questioned rule and its recommendation
- **E. Proposed modern-C# policy** — division of responsibility between compiler/nullable, Roslyn correctness analyzers, Sonar, `.editorconfig` style, IDE guidance, test-specific exceptions. Snippets may be *proposed*, never applied.
- **F. Prioritised next actions** — split: safe after approval · needs code inspection · analyzer upgrade needing dedicated validation · subjective, reserved for the owner
- **G. Resolution request** — findings in a form the user can accept / reject / constrain one by one

Then **stop**. Do not generate the remediation prompt.
