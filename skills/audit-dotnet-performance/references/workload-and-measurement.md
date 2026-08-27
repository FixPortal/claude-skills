# Workload and measurement

Choose a workload in this order:

1. Trusted existing benchmark.
2. Representative existing test or executable workload.
3. Supplied trace or artifact.
4. Ephemeral harness, only after explicit approval.
5. A static opportunity classified `Unmeasured` when none is safe.

Measured claims require a Release build; baseline and candidate identities; warmup; multiple measured iterations; environment capture; raw artifact retention; and profile-first attribution before proposing a fix. Include the workload, environment, command, raw artifact location, repetitions, statistic, baseline identity, and limitations.

Consider throughput, latency percentile, allocation, CPU, GC, startup, I/O, lock/contention, and exceptions, but report a dimension only when it is evidenced. Use native choices suited to the evidence: an existing BenchmarkDotNet benchmark, `dotnet-counters`, `dotnet-trace`, or framework logging/metrics. Do not install or prescribe every tool. Process and GC dumps are excluded in v1 even for controlled non-production processes.

Do not treat a single-invocation `Stopwatch`, Debug build, one run, elapsed time without workload count, or mixed-machine results as fully benchmarked evidence.
