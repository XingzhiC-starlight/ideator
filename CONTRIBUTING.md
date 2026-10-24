# Contributing to Ideator

Bug reports, ideas and pull requests are welcome. Open an issue first for anything larger than a
small fix, so we can agree on the approach before you spend time on it.

## Before your first pull request

Ideator is source-available under the [PolyForm Shield License](LICENSE.md), not an open source
license: anyone may use, change and share it, but not to offer a product that competes with it.
To keep the project free to change its license later, every contributor signs the
[Contributor License Agreement](CLA.md) once. You keep the copyright in your work.

When you open your first pull request, a bot comments with the sentence to post. Post it as a
comment on the pull request and the check turns green. You only sign once.

## Making a change

- How to build, run and test the app is in the [README](README.md). What the app should do is in
  [CARDS-SPEC.md](CARDS-SPEC.md), and how the code is put together is in [DESIGN.md](DESIGN.md).
- A change to behaviour updates the spec in the same pull request.
- CI must pass: the unit tests, the desk invariant check and the packaging script.
- Keep each pull request to one change, with a title in the form `fix(cards): …`, `feat(cards): …`
  or `docs(cards): …`.

Forks that you distribute need their own name and icon; see [TRADEMARKS.md](TRADEMARKS.md).
