# Report contract

Write additive reports and manifests beneath `<vault>/Claude/Performance Audit/<repository>/` using:

```text
YYYY-MM-DD-HHmm-<scope>-performance-audit.md
YYYY-MM-DD-HHmm-<scope>-performance-audit.manifest.json
YYYY-MM-DD-HHmm-PERF-001-experiment.md
```

Before publication, test both audit paths for collision. Never overwrite an existing file. If either minute-resolution path exists, add the lowest available deterministic pair suffix (`-02`, `-03`, ...) to both the Markdown and manifest stem, then publish the pair atomically.

## Report order

1. Orientation and executive summary.
2. Repository, scope, and authority boundaries.
3. Workload contracts.
4. Environment and reproducibility ledger.
5. Tool and source ledger.
6. Baseline results.
7. Attributed hotspot map.
8. Costed findings, each with all four costing views.
9. Rejected and inconclusive experiments.
10. Recommended experiment order.
11. Unassessed dimensions and fidelity gaps.
12. Repository-state preservation evidence.
13. Artifact ledger.
14. Remediation manifest.

The artifact ledger records each raw trace, benchmark output, supplied production artifact, and other retained input/output by path, SHA-256 hash, producing command, sensitivity, retention state, and required analysis tool. Do not copy, modify, or delete supplied production artifacts. A missing artifact or hash is a fidelity gap, not implied evidence.

Record the target repository's before and after Git state. A published finding ID has the immutable form `PERF-NNN`; publish every audit finding with immutable `resolutionState: "unresolved"`. A later remediation invocation records user approval separately and must not rewrite the audit manifest.

The manifest minimum shape is:

```json
{
  "schemaVersion": 1,
  "repository": { "path": "...", "head": "...", "branch": "..." },
  "audit": { "startedUtc": "...", "completedUtc": "...", "targetStateUnchanged": true },
  "findings": [
    {
      "id": "PERF-001",
      "title": "...",
      "classification": "Observed bottleneck",
      "confidence": "High",
      "resolutionState": "unresolved",
      "evidence": ["..."],
      "project": "src/Example",
      "files": ["src/Example/HotPath.cs"],
      "symbols": ["HotPath.Execute"],
      "workload": { "id": "request", "baseline": "p95 20 ms" },
      "attributedMechanism": "...",
      "proposedExperiment": "...",
      "correctnessInvariants": ["..."],
      "expectedTradeoffs": ["..."],
      "materialityThreshold": "...",
      "commands": { "baseline": "...", "candidate": "..." },
      "requiredTools": ["..."],
      "requiredArtifacts": ["..."],
      "cost": { "inputs": ["..."], "missingInputs": ["..."] },
      "productBoundary": {
        "allowed": "managed-public-api",
        "exclusions": ["unsafe", "System.Runtime.Intrinsics", "DllImport", "LibraryImport", "PInvoke", "native binaries", "native-dependent packages", "custom native allocators", "undocumented runtime switches", "runtime-private APIs", "reflection/runtime patching"]
      },
      "acceptanceConditions": ["..."],
      "rejectionConditions": ["..."],
      "rollbackExpectation": "..."
    }
  ]
}
```

Every finding is a complete one-experiment handoff. `files`, `symbols`,
`correctnessInvariants`, `expectedTradeoffs`, `productBoundary.exclusions`,
`acceptanceConditions`, and `rejectionConditions` are non-empty text arrays.
`requiredTools`, `requiredArtifacts`, `cost.inputs`, and `cost.missingInputs`
are required text arrays and may be empty only when that is the evidenced
state. All other shown finding values are required scalar text or objects.
`proposedExperiment` is one scalar description, never a list. `commands`
contains the exact comparable baseline and candidate commands. `workload`
records its stable ID and baseline identity. `productBoundary.allowed` is
exactly `managed-public-api`; `productBoundary.exclusions` must contain this
canonical minimum vocabulary: `unsafe`, `System.Runtime.Intrinsics`,
`DllImport`, `LibraryImport`, `PInvoke`, `native binaries`,
`native-dependent packages`, `custom native allocators`, `undocumented runtime
switches`, `runtime-private APIs`, and `reflection/runtime patching`.
Target-specific text exclusions may be added. The validator rejects missing,
wrongly typed, or incomplete handoff fields; it does not mutate the manifest.

Only production artifacts supplied by the user may support production-correlated evidence; never attach to a live production process.
