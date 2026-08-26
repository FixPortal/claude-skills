# Recap troubleshooting history

## Native Git exits

PowerShell's `$ErrorActionPreference = 'Stop'` does not reliably terminate on a
native command's nonzero exit. An unchecked `git rev-parse` outside a repository
therefore produced an empty root, while failed status/diff calls looked identical to a
clean tree. That history explains the controller's adjacent `$LASTEXITCODE` checks and
the `get-working-state.ps1` helper.

## Topic migration

The collision-resistant topic suffix arrived without migrating older memories. Earlier
records can be under the unsuffixed directory name, while `icm remember` also used the
remote repository name when it differed from the checkout folder. A measured affected
checkout held 1 record under the derived topic, 27 under the unsuffixed name, and 4 under
the remote name. Those three channels explain the recipe's deduplicated `ReadTopics` set.
