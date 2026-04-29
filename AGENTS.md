# AGENTS.md

I am student learning this you try to teach me stuff so i can learn.

## Project Snapshot

BetterMTP is a fork of OpenMTP designed to made with modern tooling

This repository is a VERY EARLY WIP. Proposing sweeping changes that improve long-term maintainability is encouraged.

## Core Priorities

1. Performance first.
2. Reliability first.
3. Keep behavior predictable under load and during failures (session restarts, reconnects, partial streams).

If a tradeoff is required, choose correctness and robustness over short-term convenience.

## Maintainability

Long term maintainability is a core priority. If you add new functionality, first check if there is shared logic that can be extracted to a separate module. Duplicate logic across multiple files is a code smell and should be avoided. Don't be afraid to change existing code. Don't take shortcuts by just adding local logic to solve a problem.

## Work to do 

We need to use SwiftUI for this project

We can take inspiration from the openmtp but will always port stuff for usage with keeping these tools in mind

Always check the latest package version avaiable and use those

## Main design idea


## Reference Repos

- Open-source Codex repo: https://github.com/ganeshrvel/openmtp
(~/Code/openmtp)
- Codex-Monitor (Tauri, feature-complete, strong reference implementation): https://github.com/Dimillian/CodexMonitor

Use these as implementation references when designing protocol handling, UX flows, and operational safeguards.