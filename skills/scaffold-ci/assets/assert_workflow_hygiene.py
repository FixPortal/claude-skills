#!/usr/bin/env python3
"""Assert workflow hygiene structurally: no target-context trigger, no blanket
write token, third-party actions pinned to an immutable ref.

This replaces three line-anchored `grep` assertions. They were bypassable by
ORDINARY block-style YAML, not by any evasion technique: a value may sit on the
line after its key, so

    permissions:
      write-all

resolves to exactly what `permissions: write-all` resolves to, while matching
neither the key-anchored `permissions:.*write-all` pattern nor anything else the
guard looked for. The same held for a `uses:` split across two lines, which never
reached the pin check at all. Demonstrated 2026-08-22: both greps returned no
match on a file PyYAML resolves to `permissions: 'write-all'` and
`uses: 'third/party@v1'`.

Parsing also removes the self-match hazard the greps carried. They needed a
`^[^#]*` prefix so the guard's own comments describing the rules did not trip it
(that bit on a one-repo pilot). A parser reads values, so prose about a
rule cannot be mistaken for the rule.

Exit codes: 0 clean, 1 a hard violation, 2 the checker could not run.
"""

import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    # Same policy as assert_gate_coverage.py: fail legibly rather than installing
    # PyYAML at CI time. This gates merges, so an arbitrary-at-install-time
    # dependency must not enter the gating path.
    #
    # sys.exit(2), not sys.exit(<str>): the string form prints to stderr and exits 1,
    # which is the code this module documents for a real violation. Both fail the step,
    # but a consumer branching on 2 ("infra problem, retry") versus 1 ("violation, do
    # not retry") would misclassify a missing interpreter dependency as a bad workflow.
    print(
        "PyYAML is not available to this runner. Install it in the image rather "
        "than at gate time, or restore '.github/workflows/**' to the review "
        "policy's high tier so a reviewer sees these diffs.",
        file=sys.stderr,
    )
    sys.exit(2)

WORKFLOWS = Path(".github/workflows")
SHA_LEN = 40
DIGEST_LEN = 64


def load(path):
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def triggers(document):
    """The event names in `on:`, whatever spelling was used.

    YAML 1.1 reads a bare `on` as the boolean True, which is why the key is
    looked up both ways -- `document["on"]` alone silently finds nothing in every
    workflow that writes the key unquoted, i.e. all of them.
    """
    section = document.get("on", document.get(True))
    if isinstance(section, str):
        return [section]
    if isinstance(section, list):
        return [event for event in section if isinstance(event, str)]
    if isinstance(section, dict):
        return [event for event in section if isinstance(event, str)]
    return []


def permission_blocks(document):
    """Every `permissions:` value in the file: workflow level, then each job.

    KNOWN GAP, stated so this is not mistaken for full coverage: only the literal
    `write-all` scalar is flagged (see main()). A mapping that grants every scope
    `write` individually carries the same privilege and passes. Not closed here because
    the test cannot be written soundly -- "every scope is write" needs the complete set
    of scopes GitHub defines, which changes as GitHub adds them, and an omitted scope is
    a *narrower* grant, not a broader one. A heuristic on scope count would fail
    workflows that legitimately need three or four write scopes.

    This is the same scope as the grep it replaces, so it is not a regression; the
    bypass this file closes is the block-style spelling of `write-all`, not the
    enumerated equivalent.
    """
    blocks = []
    if "permissions" in document:
        blocks.append(("workflow", document["permissions"]))
    jobs = document.get("jobs")
    if isinstance(jobs, dict):
        for name, job in jobs.items():
            if isinstance(job, dict) and "permissions" in job:
                blocks.append((f"job '{name}'", job["permissions"]))
    return blocks


def action_refs(document):
    """Every `uses:` value in the file, with the job it came from."""
    refs = []
    jobs = document.get("jobs")
    if not isinstance(jobs, dict):
        return refs
    for name, job in jobs.items():
        if not isinstance(job, dict):
            continue
        # A reusable-workflow call carries `uses:` on the job itself.
        if isinstance(job.get("uses"), str):
            refs.append((name, job["uses"]))
        steps = job.get("steps")
        if isinstance(steps, list):
            for step in steps:
                if isinstance(step, dict) and isinstance(step.get("uses"), str):
                    refs.append((name, step["uses"]))
    return refs


# Workflows permitted the target-context trigger under the written-rationale
# exemption in main(): each never checks out or executes PR code (API reads
# against the base ref only; writes are label operations). The gate fails any
# exempted workflow that uses actions/checkout.
TARGET_TRIGGER_NO_CHECKOUT = ("review-tier.yml",)


def is_pinned(ref):
    """True when the ref names an immutable revision.

    Both forms the estate actually uses are accepted. The previous `sed`-based
    scanner kept surrounding quotes in the extracted value, so a correctly pinned
    `uses: "actions/checkout@<40-hex>"` failed the hex test and was reported as an
    unpinned third-party action; and a digest-pinned `docker://` ref could never
    pass it at all. Parsed values carry no quotes, and the digest form is now
    recognised explicitly.
    """
    if ref.startswith("./"):
        return True  # A local action is this repository's own reviewed code.
    if "@" not in ref:
        return False
    revision = ref.rsplit("@", 1)[1]
    if ref.startswith("docker://"):
        algorithm, _, digest = revision.partition(":")
        return algorithm == "sha256" and len(digest) == DIGEST_LEN and all(
            char in "0123456789abcdef" for char in digest
        )
    return len(revision) == SHA_LEN and all(char in "0123456789abcdef" for char in revision)


def main():
    if not WORKFLOWS.is_dir():
        print(f"::error::{WORKFLOWS} does not exist; the guard cannot assert anything.")
        return 2

    failed = False
    first_party_tag = 0

    for path in sorted(list(WORKFLOWS.glob("*.yml")) + list(WORKFLOWS.glob("*.yaml"))):
        try:
            document = load(path)
        except yaml.YAMLError as error:
            print(f"::error file={path}::Not parseable as YAML: {error}")
            failed = True
            continue
        if not isinstance(document, dict):
            print(f"::error file={path}::Workflow does not parse to a mapping.")
            failed = True
            continue

        for event in triggers(document):
            # This trigger runs with a write token and repository secrets in the
            # base repo's context, while able to check out attacker-controlled head
            # code. It has legitimate uses; none should land without being argued
            # for, so it is refused here rather than reviewed by glob.
            #
            # Written-rationale exemption: the workflows named in
            # TARGET_TRIGGER_NO_CHECKOUT are permitted the trigger ONLY because they
            # never check out or execute PR code — every read is an API call against
            # the base ref, and the only writes are label operations. The exemption
            # is enforced below: any actions/checkout use in an exempted workflow
            # fails the gate. Add a workflow to the tuple only with the same
            # no-checkout property argued in its own header comment.
            if event == "pull_request_target":
                if path.name in TARGET_TRIGGER_NO_CHECKOUT:
                    # Enforced on the PARSED document, not raw text — a comment or a
                    # string literal mentioning the action must not trip it, and a
                    # `uses:` under any job must.
                    if any(ref.split("@", 1)[0] == "actions/checkout" for _, ref in action_refs(document)):
                        print(
                            f"::error file={path}::Exempted from the target-context trigger ban on "
                            "the written rationale that it never checks out PR code, but it uses "
                            "actions/checkout. Remove the checkout or the exemption."
                        )
                        failed = True
                    continue
                print(
                    f"::error file={path}::This workflow uses the target-context trigger, which grants "
                    "a write token and repository secrets to a workflow that can check out untrusted "
                    "head code. Use the plain pull_request trigger, or remove this assertion "
                    "deliberately with a written rationale."
                )
                failed = True

        for scope, value in permission_blocks(document):
            if isinstance(value, str) and value.strip() == "write-all":
                print(
                    f"::error file={path}::A write-all token at {scope} scope discards least "
                    "privilege. Declare the specific permissions each job needs."
                )
                failed = True

        for job, ref in action_refs(document):
            if is_pinned(ref):
                continue
            # actions/* is GitHub's own namespace, and the house standard is the
            # INVERSE of the third-party rule: first-party actions take the major
            # tag, and audit-ci grades a SHA-pinned first-party action as drift.
            # "Take the major tag" is enforced here, not assumed: a branch ref
            # (actions/checkout@main) or a bare action name is just as mutable as
            # an unpinned third-party tag and can move after review.
            if ref.startswith("actions/"):
                revision = ref.rsplit("@", 1)[1] if "@" in ref else ""
                if re.fullmatch(r"v\d+(\.\d+)*", revision):
                    # Conformant -- a vN release tag (major or dotted minor/patch).
                    # Counted only so the summary shows the split.
                    first_party_tag += 1
                else:
                    print(
                        f"::error file={path}::First-party action '{ref}' (job '{job}') is not on "
                        "the vN major tag. A branch ref or a bare action name is mutable and can "
                        "change after review."
                    )
                    failed = True
            else:
                print(
                    f"::error file={path}::Third-party action '{ref}' (job '{job}') is not pinned to "
                    "an immutable revision. A mutable tag can change after review."
                )
                failed = True

    if failed:
        return 1

    print(
        "Workflow hygiene: no unexempted target-context trigger, no write-all token, "
        "every third-party action pinned "
        f"({first_party_tag} first-party ref(s) on a vN release tag, conformant)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
