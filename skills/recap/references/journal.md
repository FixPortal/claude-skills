# Recap Journal Contract

## Key and marker

1. `rootSHA` is the lexically smallest result of
   `git rev-list --max-parents=0 HEAD`; `root12` is its first 12 characters.
2. `branch` is `git rev-parse --abbrev-ref HEAD`, or
   `detached-<short-head>` when detached. Replace characters outside
   letters, digits, `.`, `_`, and `-` with `-`.
3. Path: `~/.agents/recap/<root12>__<sanitised-branch>.md`.

For an existing journal, parse the second SHA in the first heading's
`<from>..<to>` token. If it is not a commit, treat the journal as absent. For a
new journal, detect the default branch from `origin/HEAD`, then `main` or
`master`, and use `git merge-base <default> HEAD`. When that is HEAD, use
`HEAD~20` or the first commit on a shorter branch.

## Entry

```text
## YYYY-MM-DD HH:MM — <branch> — <fromSHA>..<toSHA>

**Done since last recap**
- 3–7 concise bullets

**Actionable Now**
1. recommended order, source-tagged

**Deferred**
- source-tagged

**Unverifiable**
- source-tagged

**Operator Gated**
- source-tagged

**Information Only**
- source-tagged

<details><summary>Detail</summary>

Commit list, committed file-change stats, separate staged and unstaged working
file-change stats, pruning, caveats, and overflow.

</details>
```

New files start with `# Recap Journal — <repo>` and
`<!-- key: rootSHA=<full rootSHA> branch=<raw branch> -->`. Entries are
newest-first and use local system time. Always render all five buckets, using
`- none` when empty. Note uncommitted files in detail and mark them in the
digest, but advance the journal only to a real commit.

When no new work exists, render the previous digest from its heading through
the last forward section, excluding detail, and write nothing.
