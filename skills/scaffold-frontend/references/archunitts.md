# ArchUnitTS wrapper rationale

Importing `archunit` at its package root eagerly registers a matcher that needs a
global `expect`, so it throws under this scaffold's Vitest `globals: false`. The
wrapper deep-imports `archunit/dist/src/files`, avoiding that side effect and
centralising the unsupported subpath.

The package has no `exports` map, so the deep import is version-sensitive. A 2026-06
cross-vendor review found the proposed
upstream alternatives either behaviourally ineffective or breaking. When upstream
ships a working root import or exports map, update the wrapper and pin together.
