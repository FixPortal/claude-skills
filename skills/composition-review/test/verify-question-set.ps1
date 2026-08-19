$ErrorActionPreference = 'Stop'
$text = Get-Content (Join-Path $PSScriptRoot '..' 'SKILL.md') -Raw
$body = $text -replace '(?s)^---.*?---\s*', ''

# Assertions here are STRUCTURAL, not substring-presence. A needle check proves a word
# survives, never that the thing it names still exists: a question table replaced by
# "Restart-replay, Idempotency, Ordering, Fence pairing and Partial failure were dropped"
# passes every needle in it while the instrument is gone.
function Get-Section {
    param([string] $Heading)
    $pattern = '(?ms)^##\s+' + [regex]::Escape($Heading) + '\s*?\r?\n(.*?)(?=^##\s|\z)'
    $match = [regex]::Match($body, $pattern)
    if (-not $match.Success) { throw "SKILL.md has no '## $Heading' section" }
    return $match.Groups[1].Value
}

# The five questions are the whole instrument. A skill that has quietly lost one still
# reads as a composition review and still returns a confident all-clear. Count the ROWS,
# then pin the names - prose that merely mentions the five is not a question set.
$questions = Get-Section -Heading 'The five questions'
$questionRows = [regex]::Matches($questions, '(?m)^\| Q\d \|').Count
if ($questionRows -ne 5) {
    throw "Expected exactly 5 question rows (^| Qn |); found $questionRows."
}
foreach ($needle in 'Restart-replay', 'Idempotency', 'Ordering', 'Fence pairing',
                    'Partial failure') {
    if ($body -notmatch [regex]::Escape($needle)) {
        throw "Question set is missing a question: $needle"
    }
}

# Three output slots and no fourth. Counted, not asserted in prose: the "there is no
# fourth" sentence survives the addition of a fourth slot directly beneath it. Without
# the three-slot discipline the subagent can answer "looks fine", which is the failure
# this instrument exists to prevent - an absence of analysis reading as an all-clear.
$contract = Get-Section -Heading 'Output contract'
$slots = [regex]::Matches($contract, '(?m)^- \*\*`([^`]+)`\*\*')
$slotNames = @($slots | ForEach-Object { $_.Groups[1].Value })
if (($slotNames -join ',') -ne 'finding,clear,N/A') {
    throw "Output contract must offer exactly three slots (finding, clear, N/A); found: $($slotNames -join ', ')"
}
if ($contract -notmatch 'mechanism') {
    throw 'Output contract no longer requires a mechanism from a finding.'
}

# The N/A slot is the one through which five non-answers read as an all-clear, so the
# restriction on it is anchored like the blocking rule rather than matched loosely.
# Both halves are pinned: the demand to name the absent subject, and the consequence of
# not naming it. A presence check on either alone survives the other being deleted.
if ($contract -notmatch '`N/A` on Q1, Q2 or Q5\s+must name the absent subject') {
    throw 'The N/A restriction on Q1/Q2/Q5 no longer demands the absent subject be named.'
}
if ($contract -notmatch 'is a coverage gap') {
    throw 'An unjustified N/A on Q1/Q2/Q5 is no longer a coverage gap.'
}

# One subagent, asserted POSITIVELY. The previous word-ban on "panel"/"cross-vendor"
# bought nothing - deleting the whole Dispatch section, or asking for five subagents,
# both slipped past it - while false-positiving on legitimate prose about class C.
if ($body -notmatch '(?m)^Send \*\*one\*\* subagent') {
    throw 'Dispatch must instruct exactly one subagent (line starting "Send **one** subagent").'
}

# The teeth. A question set whose findings do not block is a domain present on paper.
# Anchored on the sentence, symmetrically with the gate test's step-6 anchor. A loose
# 'blocks .*PASS' match survives "Any finding blocks PASS **only when the user asks for it
# to; by default it is recorded and the merge proceeds**" - the phrase is intact and the
# rule is inverted, which is the same free-floating-needle defect one file over.
$consequence = Get-Section -Heading 'What happens to a finding'
if ($consequence -notmatch '(?m)^Any finding blocks .*PASS until it is fixed') {
    throw 'The blocking rule is no longer stated as "Any finding blocks ... PASS until it is fixed".'
}
if ($body -match '(?i)finding[^.\n]*(advisory|does not block|never blocks|non-blocking)') {
    throw 'Findings are described as non-blocking somewhere in the skill.'
}

# The constraint that keeps this from becoming FPES again.
foreach ($forbidden in 'examination round', 'acceptance ledger', 'Accepted State') {
    if ($body -match [regex]::Escape($forbidden)) {
        throw "Skill has grown FPES machinery: $forbidden"
    }
}

$wordCount = [regex]::Matches($body, '\b[\p{L}\p{N}_/-]+\b').Count
if ($wordCount -ge 550) {
    throw "SKILL.md is $wordCount words; this is a question set, not a framework."
}

'composition-review question set OK'
