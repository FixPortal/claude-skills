# Evidence contract

Classify every finding as exactly one of: `Observed bottleneck`, `Benchmarked improvement`, `Production-correlated`, `Static opportunity`, `Unmeasured`, or `Rejected experiment`. Confidence is exactly `High`, `Moderate`, `Low`, or `Indeterminate`.

| Field | Required content |
| --- | --- |
| Classification | One exact evidence class |
| Confidence | One exact confidence value |
| Claim | Narrow, falsifiable statement |
| Workload | Named operation and representative input |
| Provenance | Commit, runtime, OS, architecture, tool/version, and command |
| Result | Statistic plus unit; distributions or variance when available |
| Attribution | Trace/profile evidence, or its explicit absence |
| Correctness | Test or check that guards behavior |
| Limits | Threats to validity and missing evidence |

Static observations are hypotheses. Benchmark deltas alone do not establish bottleneck attribution. A failed or neutral experiment remains evidence and must not be discarded.
