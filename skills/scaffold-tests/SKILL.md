---
name: scaffold-tests
description: Use when creating or normalizing .NET/C# test projects (xUnit) — adding a test project for a src/ project, scaffolding unit tests, or aligning test project structure. Triggers - add tests, create test project, scaffold unit tests, a src/ project missing its test project. .NET/C# only; for JS/TS frontend tests see scaffold-frontend.
---

# Scaffold Tests

## Overview

Create and maintain xUnit test projects that mirror the `src/` structure, using NSubstitute for mocking and AwesomeAssertions for assertions. Prioritize brevity and meaningful coverage — one well-parameterized theory replaces many redundant facts.

## When to Use

- Creating test projects for existing source projects
- Adding tests to a project that has none
- When asked to "add tests", "scaffold tests", or "create unit tests"
- When a `src/` project is missing its corresponding test project under `tests/`

## Test Project Structure

- New test projects use `tests/{ProjectName}.UnitTests`
- When normalizing an existing repository, preserve its established test-project names
- Test projects use `Microsoft.NET.Sdk`
- Test projects must reference their corresponding source project via `ProjectReference`
- Test projects are added to the solution under the `tests` solution folder
- New `xunit.v3` test projects set both `<OutputType>Exe</OutputType>` AND
  `<UseMicrosoftTestingPlatformRunner>true</UseMicrosoftTestingPlatformRunner>` in the
  `.csproj`. `OutputType=Exe` alone only enables Test-Explorer integration — the MTP
  command-line runner/host that `dotnet test`/CI actually invokes needs the
  `UseMicrosoftTestingPlatformRunner` property too. The house `scaffold-ci` default is
  `test-runner: mtp`; without both properties a scaffolded project silently falls back
  off MTP the first time CI wires up Stryker. Keep `Microsoft.NET.Test.Sdk` +
  `xunit.runner.visualstudio` alongside it — `dotnet test` (VSTest) keeps working, the
  two runners coexist. Does not apply to `xunit` v2 projects. Verify the generated
  project actually runs under MTP against the CI + Stryker commands before calling it
  done.

## Naming Conventions

- New test project: `{ProjectName}.UnitTests`; preserve established names in existing repositories
- Test class: `{ClassName}Tests` (e.g., `CompanyEndpointsTests`)
- Test method: `MethodName_Scenario_ExpectedResult` (e.g., `GetDatabase_WithValidName_ReturnsCompany`)

## Test Style

### Prefer Theory over Fact

Use `[Theory]` with `[InlineData]` whenever a test can be parameterized — when multiple test cases differ only by input and expected output. Do not write multiple `[Fact]` methods that test the same logic with different values.

```csharp
// Preferred: one Theory covers multiple cases
[Theory]
[InlineData("Apple", true)]
[InlineData("NonExistent", false)]
public void GetByName_WithVariousNames_ReturnsExpectedResult(string name, bool shouldExist)
{
    var result = FakeDatabase.GetFruitByName(name);
    (result is not null).Should().Be(shouldExist);
}

// Avoid: separate Facts for each input
[Fact]
public void GetByName_WithApple_ReturnsFruit() { /* ... */ }
[Fact]
public void GetByName_WithNonExistent_ReturnsNull() { /* ... */ }
```

### Documentation

Every new test method must have an XML doc comment explaining:
1. What the test validates
2. Why this test is a valid choice (what risk it mitigates or behavior it confirms)

Do not retrofit XML comments across existing tests during repository normalization.

```csharp
/// <summary>
/// Verifies that the cache is consulted before the database, returning cached values
/// when available. This ensures the caching layer is actually wired up and not bypassed.
/// </summary>
[Fact]
public void GetCached_WithCachedValue_ReturnsCachedResult()
```

### Assertions

Use AwesomeAssertions (`.Should()`) instead of xUnit's `Assert.*`. AwesomeAssertions is the free, Apache-2.0 fork of FluentAssertions. Import it with `using AwesomeAssertions;` — the 9.x line renamed the namespace from `FluentAssertions`, though the `.Should()` API is otherwise unchanged. Do not use the `FluentAssertions` package (v8+ is commercially licensed).

```csharp
// Preferred
result.Should().NotBeNull();
result!.Name.Should().Be("Apple");

// Avoid
Assert.NotNull(result);
Assert.Equal("Apple", result.Name);
```

### Mocking

Use NSubstitute for mocking dependencies:

```csharp
var cache = Substitute.For<IFusionCache>();
cache.GetOrSet(Arg.Any<string>(), Arg.Any<Func<CancellationToken, Fruit?>>())
    .Returns(expectedFruit);
```

NSubstitute is for **unit** tests. In integration tests use real instances, not empty
substitutes — substitute only the genuine external boundary. For time-dependent code,
inject NodaTime `IClock` (or .NET `TimeProvider` where NodaTime isn't in play) and supply
a fake/fixed clock in the test rather than reading `DateTime.UtcNow` / `SystemClock.Instance`.

### Async and timing

Tests that exercise async or concurrent behaviour (a fill landing, a race
resolving, a pipeline disposing, a message arriving) must be **event-driven**.

**No wall-clock value inside a test body may decide whether it passes.** Not as
a sleep, not as a ceiling, not as a "generous" bound. This is a prohibition, not
a preference — a duration in the body measures how busy the runner was, so it
turns load into failure. Specifically banned:

| Banned in a test body | Why it fails |
|---|---|
| `Thread.Sleep(n)` / `await Task.Delay(n)` then assert | Races the system under test |
| `elapsed.Should().BeLessThan(...)`, `Stopwatch` ceilings | Measures the scheduler |
| `signal.Wait(TimeSpan)` / `.WaitAsync(TimeSpan)` asserted true | A slow runner is not a defect |
| `Task.WhenAny(work, Task.Delay(n))` as a hang detector | Same bound, moved |
| `while (!cond && DateTime.UtcNow < deadline)` poll loops | The deadline is the flake |

The trap is that the last three *look* event-driven. They await real signals —
and then impose a private deadline on how long the signal may take, which is the
same defect wearing a better coat. A 2-second bound on "has the dispatcher
started yet" is not generous; it is a bet on the scheduler, and under full-suite
parallelism it loses.

**Where the ceiling belongs: on the framework.** A test that awaits an unbounded
signal still must not wedge the suite when the code genuinely regresses. Put
that ceiling on the test, far above any healthy run and with no diagnostic
meaning in between:

```csharp
private const int HangCeilingMs = 30_000;

[Fact(Timeout = HangCeilingMs)]
public async Task Shutdown_returns_while_an_uncancellable_send_is_still_in_flight()
{
    // Await a real signal, bounded ONLY by the test's cancellation token.
    await sender.Entered.WaitAsync(TestContext.Current.CancellationToken);

    var shutdown = RunOnDedicatedThread(() => sink.Dispose());
    await shutdown.WaitAsync(TestContext.Current.CancellationToken);

    // The assertion is a state fact, not a duration.
    sender.CompletedSends.Should().Be(0, "shutdown did not wait for the blocked send");
}

// Polling is fine when nothing signals — but with NO deadline of its own.
private static async Task WaitUntilAsync(Func<bool> condition)
{
    while (!condition())
    {
        await Task.Delay(10, TestContext.Current.CancellationToken);
    }
}
```

Verify the ceiling actually fires before relying on it: a throwaway
`[Fact(Timeout = 1_000)]` that awaits forever must report *"Test execution timed
out"*, not hang the run.

**Assert a state fact, never a duration.** "Did teardown return?" is answered by
awaiting the task, not by timing it. "Did the fill land?" is answered by the
collection's contents. If the only way to express an invariant seems to be a
duration, the invariant is usually "X happened while Y was still in flight" —
express that as a counter or flag the system already exposes.

**The one exception: a bound that can only degrade the test, never fail it.** A
best-effort barrier — "wait for all eight workers to start, and proceed anyway if
the scheduler is starved" — is allowed, because nothing is asserted on how it
resolves: missing it makes the test less thorough, not red. Say so in a comment,
or the next reader will copy the shape into a place where it *does* decide the
verdict.

**A `TimeSpan` passed *into* the system under test is not a test timer** —
`new Registry(disposalWaitTimeout: TimeSpan.FromMilliseconds(50))` is production
configuration, and choosing a small value to make behaviour observable is right.
The prohibition is on the test measuring time, not on the code being configured
with it.

**Negative assertions** ("must NOT recreate", "must NOT emit") cannot be made
event-driven by waiting for an absence. Gate them on the nearest real signal that
provably comes after the moment in question, assert the negative there, and state
the residual in a comment. Never substitute a sleep for the missing signal — it
is not more rigorous, only slower and flakier.

Expose a completion hook the test can await (e.g. a `TaskCompletionSource` the
sink signals) rather than guessing a delay. Combine with the injected clock
above so the *passage* of time is controlled, not slept through.

### Brevity

- Do not write ten tests where one will do
- One well-parameterized `[Theory]` replaces many `[Fact]` methods
- Only test meaningful behavior — skip trivial getters/setters unless they contain logic
- Prefer fewer, comprehensive tests over many narrow ones, provided coverage is maintained

## Package Requirements

All packages must be at the latest versions compatible with .NET 10:

- `xunit.v3` — xUnit v3 for new solutions. When adding a test project to an existing solution, match the xUnit major version already in use (`xunit` for a v2 solution); do not mix v2 and v3.
- `xunit.runner.visualstudio`
- `Microsoft.NET.Test.Sdk`
- `NSubstitute`
- `AwesomeAssertions` — free Apache-2.0 fork of FluentAssertions; imported via `using AwesomeAssertions;` (9.x renamed the namespace). Do not use the `FluentAssertions` package (v8+ is commercially licensed).

If the solution uses central package management (`Directory.Packages.props`), add `PackageVersion` entries there and use versionless `PackageReference` entries in the test project files.

## Checklist

When scaffolding test projects, verify:

- [ ] New test projects use `tests/{Name}.UnitTests`; established names are preserved when normalizing existing repositories
- [ ] Test projects added to solution under `tests` solution folder
- [ ] Test projects reference their source project via `ProjectReference`
- [ ] All required packages added (`xunit.v3`, `xunit.runner.visualstudio`, `Microsoft.NET.Test.Sdk`, `NSubstitute`, `AwesomeAssertions`); xUnit major version matches the solution
- [ ] Packages use central package management if `Directory.Packages.props` exists
- [ ] `[Theory]`/`[InlineData]` used instead of `[Fact]` where inputs vary
- [ ] Each new test method has an XML doc comment explaining what and why; existing tests are not retrofitted
- [ ] No redundant tests — brevity maintained with meaningful coverage
- [ ] AwesomeAssertions used for all assertions (no `Assert.*`)
- [ ] NSubstitute used for all mocking
- [ ] Async/timing tests are event-driven: every wait is on a real signal or a poll bounded ONLY by `TestContext.Current.CancellationToken`
- [ ] No wall-clock value in any test body decides pass/fail — no sleep-then-assert, no `Stopwatch`/`BeLessThan(TimeSpan)` ceiling, no `Wait(TimeSpan)` asserted true, no `WhenAny(work, Task.Delay(n))`, no `DateTime.UtcNow` poll deadline
- [ ] Tests that await an unbounded signal carry a framework hang ceiling (`[Fact(Timeout = …)]`), set far above a healthy run and verified to fire
- [ ] `xunit.v3` test projects have `<OutputType>Exe</OutputType>` set (required for the house `scaffold-ci` `test-runner: mtp` default)
- [ ] Tests build and pass

## Related skills

- `audit-tests` — reads this skill's output. This skill creates/normalizes the test
  project; `audit-tests` is a separate, read-only pass that judges whether an *existing*
  suite actually defends the codebase's behaviour (risk-based adequacy, not coverage
  percentage) and produces a prioritized backlog. Use `audit-tests` when the question is
  "are these tests any good", not "scaffold me a test project".
