<!-- Author-written. Used by the orchestrator as the report contract VERBATIM. Do not reword, trim, or "improve". -->

Perform a read-only, risk-based assessment of test adequacy for this repository.

Do not modify code. Do not optimize for a predetermined line-coverage percentage, and do not assume that executed code is adequately tested.

First construct an evidence-based model of:

* the system's externally observable behaviours;
* important business rules and invariants;
* security and trust boundaries;
* persistence and transaction guarantees;
* asynchronous processing, retries and idempotency;
* external integrations and failure behaviour;
* public API and serialization contracts;
* startup, configuration and deployment-critical behaviour.

Then inspect the existing test projects and map tests to those behaviours.

Evaluate test quality as well as presence. Identify:

* important behaviours with no effective test;
* tests whose assertions are too weak to demonstrate their stated behaviour;
* tests that primarily reproduce implementation details;
* happy-path tests lacking meaningful boundary or failure cases;
* false confidence caused by excessive mocking;
* integration boundaries tested only with substitutes;
* nondeterministic, order-dependent or concurrency-sensitive tests;
* tests that could pass despite a material defect;
* duplicated tests that add maintenance cost without materially increasing confidence;
* production design that unnecessarily obstructs testing.

If a coverage report or mutation report is present, use it as supporting evidence. Do not treat coverage percentage alone as proof of quality.

For every proposed addition or improvement provide:

1. The risk or invariant being addressed.
2. Exact production files and symbols involved.
3. Existing relevant tests and why they are insufficient.
4. The most appropriate test level:

   * unit;
   * component;
   * integration;
   * contract;
   * end-to-end;
   * architecture or configuration test.
5. A concrete test scenario, including setup, action and meaningful assertions.
6. Whether mocking is appropriate and which boundary should remain real.
7. The realistic regression or mutation the test should detect.
8. Priority, implementation cost and confidence.

Avoid recommending tests for:

* trivial getters or constructors;
* framework behaviour already guaranteed by the framework;
* private methods independently of observable behaviour;
* exhaustive combinations without a risk-based justification;
* implementation details likely to change without changing behaviour;
* coverage percentage for its own sake.

Produce:

## 1. Test-suite assessment

Summarize the suite's actual strengths, weaknesses and sources of false confidence.

## 2. Behaviour-to-test map

Map important behaviours and invariants to existing effective tests, partial tests or missing tests.

## 3. Prioritized test backlog

Separate into:

* Critical confidence gaps
* High-value additions
* Useful strengthening
* Low-value or consciously omitted

## 4. Tests to improve or remove

Identify weak, misleading, redundant or excessively coupled tests and recommend the smallest proportionate correction.

## 5. Recommended test distribution

Explain where this project needs unit, integration, contract and end-to-end tests. Base this on its actual architecture rather than a generic testing pyramid.

## 6. Implementation sequence

Propose bounded slices that can be implemented and reviewed independently. For each slice, state the evidence that would demonstrate completion.

## 7. Measurement strategy

Recommend appropriate use of line and branch coverage, mutation testing, test reliability and execution time. Do not propose arbitrary thresholds without explaining what they protect.

The objective is the greatest defensible increase in confidence for the least additional test and maintenance burden.
