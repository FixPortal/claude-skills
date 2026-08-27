# Costing

Every measurable candidate reports all four views below. An unavailable field is explicit and reasoned, never omitted.

## 1. Performance delta

Record applicable absolute and percentage changes, the raw distribution and uncertainty, CPU per operation, allocations and GC, throughput or tail latency, working set, startup, and published size. State the practical materiality threshold and whether the result exceeds it. Statistical difference alone is not operational materiality.

Use native units before currency:

```text
cpu-seconds / operation
allocated-bytes / operation
requests / core-second
wall-seconds / batch
GB-hours / workload unit
```

## 2. Measurement cost

Record actual elapsed time, benchmark cases and executions, compute environment, tool/setup time, artifact volume, and any external service or infrastructure used.

## 3. Engineering and operational cost

Estimate an implementation range with its assumptions, behavioural surface, required tests and review, rollout/rollback difficulty, retained-memory or cache effects, concurrency/configuration complexity, portability, and ongoing maintenance. Keep estimates labelled; do not turn guessed line counts into authoritative hours.

## 4. Commercial impact

Report unit economics whenever measurable. Calculate currency and break-even only when the user supplies operation volume, deployment topology and scaling rules, applicable unit rates, and utilisation assumptions:

```text
period_cost = unit_consumption × workload_volume × topology_multiplier × supplied_unit_rate
savings = baseline_period_cost - candidate_period_cost
```

Preserve every input's value, source, date, and formula assumptions. Do not extrapolate across an unmeasured bottleneck. If any required input is absent, emit `currencyCost: unknown` and list the missing inputs. A resource improvement that crosses no real capacity, replica, SKU, or billing boundary has no immediately realisable saving. V1 does not query prices or infer a deployment cost model.
