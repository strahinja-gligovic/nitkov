# 0006: Specs and tickets are local markdown, committed with the code

## Context

The work is done mostly by coding agents working in project copies, which read and update tickets with file tools. A ticket's scope, acceptance criteria and measured outcomes need to stay next to the code they describe and to version with it.

## Decision

- Each feature has a folder `.scratch/<feature>/` with a `spec.md` and one markdown file per ticket under `issues/`. The file conventions (numbering, the `Status:` and `Blocked by:` lines, `## Comments`) are in `docs/agents/issue-tracker.md`, and the triage strings are in `docs/agents/triage-labels.md`.
- The files are tracked in git and change in the same commits as the work.

## Consequences

- Despite the folder name, `.scratch/` is tracked, not gitignored. Commit ticket edits along with the change.
- Finished tickets read `Status: done`, which is not one of the five triage labels. Open work uses the labels (ticket 16 is `needs-triage`).
- Tickets hold the history (why a number changed, what was measured), so docs state only the current truth. When the code and a ticket disagree, trust the code; old tickets name things that no longer exist (`GauntletData`, Shard Volley).
- The current milestone is `.scratch/nitkov-combat-prototype/`. Its `spec.md` is the design reference, and later tickets amend it (ticket 15 adds Lightning and Wind, ticket 16 owns the time-to-kill target).
