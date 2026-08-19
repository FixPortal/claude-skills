# Async and timing tests

## Canonical deadline policy

Do not ban deadlines. Ban sleeps, races against the scheduler, and elapsed-time assertions. Every operation whose completion can go missing needs one generous hang ceiling so a regression fails loudly instead of wedging the test host.

Prefer a real completion signal: a `TaskCompletionSource`, channel item, callback, observable state transition, or lifecycle hook. When no signal exists, poll the condition with the same ceiling. A poll is diagnostic waiting, not a performance measurement.

Choose the ceiling from the runner contract:

| Runner configuration | Ceiling |
|---|---|
| xUnit conservative scheduling | `[Fact(Timeout = ...)]` is supported |
| Test parallelization is disabled | `[Fact(Timeout = ...)]` is supported |
| Aggressive or unknown scheduling | Use operation-local `WaitAsync(TimeSpan)` or a linked token with `CancelAfter` |

xUnit documents timeout behaviour under aggressive scheduling as undefined. Inspect `xunit.runner.json` before adding framework timeouts; do not assume the current default will remain unchanged. See the official [parallelism documentation](https://xunit.net/docs/running-tests-in-parallel) and [Fact timeout API](https://api.xunit.net/v3/1.0.0/v3.1.0.0-Xunit.FactAttribute.Timeout.html).

For an operation-local ceiling:

```csharp
await completion.Task.WaitAsync(TimeSpan.FromSeconds(30));

using var deadline = CancellationTokenSource.CreateLinkedTokenSource(testToken);
deadline.CancelAfter(TimeSpan.FromSeconds(30));
await completion.Task.WaitAsync(deadline.Token);
```

Use one form, not both. Pick a value far above a healthy instrumented run. Expiry means "completion did not arrive"; it does not establish that the code is too slow.

## What remains forbidden

- `Thread.Sleep` or `Task.Delay` followed by an assertion.
- `Stopwatch`, `BeLessThan`, or a tight timeout used as a performance verdict.
- `Task.WhenAny(work, Task.Delay(...))` when it merely rebuilds a deadline badly.
- Wall-clock polling with `DateTime.UtcNow`; use `WaitAsync`, cancellation, or an injected clock.
- A short expiry used to prove that something did not happen. Wait for the next positive signal that closes the relevant window, then assert absence.

If transport code has its own timeout, distinguish it from the test ceiling. Prefer an infinite transport timeout plus the selected test token when the transport supports that shape. Filter `OperationCanceledException` against the token that actually owns the ceiling so dependency cancellation is not mislabeled.

A `TimeSpan` passed into the system under test can be legitimate production configuration. Keep time itself controllable through `IClock` or `TimeProvider`; advance fake time instead of sleeping.
