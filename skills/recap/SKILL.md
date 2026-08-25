---
name: recap
description: Use when the user runs /recap or resumes one Git repository and wants work reconstructed from its recap marker. Not for current cleanliness across repositories (state-of-play), writing a brief before context is lost (handoff), or ending a session (close).
---

# Recap

Reconstruct what changed in one repository since its last recap, then separate
what follows into five buckets: Actionable Now, Deferred, Unverifiable,
Operator Gated, and Information Only. The journal under `~/.agents/recap/` is
internal plumbing, never a user-managed repository artefact.

Read [references/classification.md](references/classification.md) before
classifying forward work and [references/journal.md](references/journal.md)
before reading or updating the marker.

## Procedure

### 0. Re-anchor and recall

Before any repository work, re-read the active runtime's user-level instruction
file in full and any canonical instruction file to which it explicitly
delegates. Never assume an unrelated host's policy.

Before selecting a memory provider, require a Git repository and initialize
the topic variables. Take the root in two steps, checking the exit code before
using the output — `$ErrorActionPreference = 'Stop'` does **not** trip on a
native nonzero exit, so an unchecked lookup outside a repository carries an
empty root into the topic key and recalls the wrong project's memory:

```powershell
$rootRaw = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($rootRaw)) { throw 'recap requires a Git repository' }
$repoRoot = [IO.Path]::GetFullPath($rootRaw.Trim())
```

Resolve the shared recipe with `$recipePath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'close' 'references' 'topic-key.ps1')).Path`, and dot-source it with `. $recipePath`. It provides `Get-RepositoryTopicInfo` and `Get-RemoteRepositoryName`; call each once, in the block below.
Assign `$repoDisplayName = $topicInfo.DisplayName`,
`$repoTopicKey = $topicInfo.TopicKey`,
`$contextTopic = $topicInfo.ContextTopic`, and
`$decisionsTopic = $topicInfo.DecisionsTopic`. The recipe is
[../close/references/topic-key.ps1](../close/references/topic-key.ps1); it
normalizes the resolved root and appends a SHA-256 suffix, so
spaces/metacharacters cannot merge distinct repositories.

Pass the repository's GitHub name too, so historical topics are derivable:

```powershell
$remoteUrl = git remote get-url origin 2>$null
if ($LASTEXITCODE -ne 0) { $remoteUrl = $null }
$topicInfo = Get-RepositoryTopicInfo -RepositoryRoot $repoRoot -RemoteName (Get-RemoteRepositoryName -RemoteUrl $remoteUrl)
```

Check `$LASTEXITCODE` on the line directly after the `git` call — a repository with
no `origin` is normal, and `Get-RemoteRepositoryName` returns `$null` for anything
unusable, which simply yields the four-topic read set.

Then read `$topicInfo.ReadTopics` — the deduplicated set of every topic this
repository's memory has ever been filed under. Do not assemble that list by
hand. The suffix arrived on 2026-08-12 with no migration, so anything stored
before it lives under the unsuffixed name; and `icm remember` files under the
git remote name while close used the directory name, which differ wherever a
checkout's folder is not named after its repository. Measured that day on one
such checkout: 1 memory under the derived topic, 27 under the unsuffixed
directory name, 4 under the remote name — all three the same project. Recap
never writes, so reading a historical channel costs it nothing.

Now use the runtime's native project-memory recall when its active contract
defines one. Otherwise, if `icm.exe` resolves on `PATH`, enumerate all four exact
topics with [references/recall-icm-topics.ps1](references/recall-icm-topics.ps1):

```powershell
$memoryBodies = & "$PSScriptRoot\references\recall-icm-topics.ps1" -Topics $topicInfo.ReadTopics
```

It calls `icm.exe list --topic "$topic" --all --format json`, not the
five-result-default `recall` command. Each list result is a complete stored
memory record. The helper returns one result per topic; a topic whose
enumeration or parse fails arrives with empty `Bodies`, `Failed = $true`, and a
warning, and the recall continues with the remaining topics. Use no ICM
candidate context for that failed topic and record the incomplete recall in
journal detail; never treat a partial result as complete.

Keep the results as candidate context; prior recap digests are never evidence
for forward work.

### 1. Establish scope

The repository check was completed before memory selection. If it was not true,
answer `Not a git repository — recap needs git history. Nothing to recap.` and
stop.
Compute the branch-specific journal key and marker exactly as the journal
reference specifies.

### 2. Safe housekeeping

Best effort only; failure never blocks recap:

1. `git fetch --prune`; if it fails, do not delete branches.
2. `git worktree prune` for already-missing worktrees.
3. Delete a non-current branch only when its upstream is gone and its commits
   are proved on mainline by the standing rebase-merge title fingerprint or
   `git branch --merged`. Report deletions in digest detail.

Never delete an upstream-less, ahead, or unmerged branch; never drop stashes,
clean files, discard changes, run `git gc`, or pull.

### 3. Gather done

Run compact history and state commands:

- `git log <marker>..HEAD --format='%h %s'`
- `git diff --stat <marker>..HEAD`
- `git status --short`, `git diff --cached --stat`, and `git diff --stat`
  (or [references/get-working-state.ps1](references/get-working-state.ps1)).
  Keep staged and unstaged stats separate; the marker-to-HEAD diff covers only
  committed work and must not be recomputed from `HEAD`.

If neither commits nor working-tree changes exist, re-display the last journal
digest and write nothing. If no entry exists, say there is no work to recap.

### 4. Gather and classify forward work

Consult live markers in changed code, nearby planning docs, the current
branch's open PR when authenticated, full relevant memory bodies, and the
task-start recall. Skip missing sources silently and do not run tests.

Re-derive every forward item from a current primary source. A memory index is
only a pointer; open the body. A prior journal or ICM recap is self-authored
history, not corroboration. Apply the classification reference, including its
closure, absence, cross-repo, and optional-pass rules.

### 5. Answer

Return the journal heading, `Done since last recap`, and all five forward
headings. Actionable Now is numbered in recommended order; the other buckets
are bulleted. Use `- none` for an empty bucket. Tag every forward item with
`[code]`, `[doc]`, `[pr]`, or `[memory]`; cap each bucket at seven entries and
put overflow in journal detail.

End with one line:

- `[OK] Re-read active global instructions — standing house rules in force for this session.`
- Or, when absent: `[OK] No runtime-level instruction file for this host — none to re-read.`

### 6. Persist silently

Only when the range contains new commits, prepend the entry described in the
journal reference. Never journal uncommitted-only state. If `icm.exe` resolves
on `PATH`, store only Done bullets plus the commit range in
`$contextTopic`; never store forward buckets or write to the decisions topic.
