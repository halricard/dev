### Spec-driven method: TLC

- The `tlc-spec-driven` skill leads feature work through its phases: Specify, Design, Tasks, Execute and Verify. Context comes before Specify and Deliver after Verify. Follow its steps and gates, and use this skill for every command those phases need to run, test or inspect.
- In Specify, give each requirement the test that will cover it, in a suite that `dev test` runs (see the notes below).
- In Execute, work one task at a time: write the test first, run the suite with `dev test`, check `dev logs`, and commit only when it passes. Take a `dev snapshot` before destructive steps.
- Stop for the user's approval after the spec, after the design and before opening the pull request.
