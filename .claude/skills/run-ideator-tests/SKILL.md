---
name: run-ideator-tests
description: Run Ideator's unit tests (target CardsTests, scheme Ideator) from a throwaway copy outside ~/Desktop, and get the test count, the failures, any new compiler warning in Cards/ and a PASS or FAIL line. Use whenever you would type `xcodebuild test` for this repo, to run all the tests, one class, one test or a flaky test many times, and before saying a change to Cards/ or CardsTests/ passes.
---

# Run Ideator's unit tests

Call the script inside the checkout you want tested. It tests the checkout it lives in.

```bash
.claude/skills/run-ideator-tests/scripts/run-tests                   # all of CardsTests
.claude/skills/run-ideator-tests/scripts/run-tests DeskTests         # one class
.claude/skills/run-ideator-tests/scripts/run-tests DeskTests/testX   # one test; repeat the argument for more
.claude/skills/run-ideator-tests/scripts/run-tests -n 20 SwipeTests  # 20 runs, to chase a flaky test
```

Run it with the Bash tool's `run_in_background`. A full run took 36 seconds on 2026-10-28, and a
cold package cache makes it minutes. macOS has no `timeout` command.

The script copies the checkout, without `.git` and `build/`, to a new folder under `$TMPDIR`. It
runs the same `xcodebuild test` command as CI there, with the copy's own derived data, and deletes
the copy when it exits. A failing `xcodebuild test` whose derived data is under `~/Desktop` can hang
on the macOS Desktop privacy prompt while it symbolicates, and this repo lives on the Desktop. A
copy per run also keeps parallel agents off each other's derived data.

It writes the full log, minus the `com.apple.linkd` noise, to `build/test-logs/` in the checkout,
and prints the error lines, any compiler warning in `Cards/`, the count of compiler warnings in
`CardsTests/`, the total "Executed N tests" line, the log path, and PASS or FAIL. Exit 0 means
tests ran, none failed, and `Cards/` compiled with no warning. `CardsTests/` had 3 compiler
warnings on main on 2026-10-28, all in `StackArrangerTests.swift`, so its count does not fail the
run. A higher count means you added one. The log's "Conflicting constraints" lines are Auto
Layout messages from the running tests, not compiler warnings.

## Reading a FAIL

- `FAIL (xcodebuild exit N)`: the `error:` lines above it are failed assertions
  (`-[CardsTests.<Class> <test>]`) or compile errors. The log has the rest.
- "The test host crashed": the host is the real app. Read the newest report the script lists from
  `~/Library/Logs/DiagnosticReports`. The screen and pointer are shared with every other app and
  test host on the Mac, so a crash that happens once stays inconclusive until it repeats in a run
  with nothing else driving the Mac.
- `FAIL: no test ran` or `FAIL: no test matched <name>`: a filter matched no test, and
  `xcodebuild` skips such a filter without an error. Class names are the files in `CardsTests/`.
  There is no `IdeatorTests` target.
- `FAIL: compiler warnings in Cards/`: fix them. Main builds `Cards/` with none.

## Writing tests

- The target is `CardsTests`, it imports the app with `@testable import Ideator`, and the app is
  its test host. The tests never touch `~/Documents/Ideator`.
- Make a test method `async` when it creates or releases an object isolated to the main actor,
  such as `Library`. Releasing one from a synchronous test method aborted the test host.
- To wait for an animation or a debounce, poll for its end state with a deadline, as `eventually`
  in `SummarizerTests.swift` does. Never use a fixed sleep for it. A fixed wait passes on an idle
  Mac and fails under load.
