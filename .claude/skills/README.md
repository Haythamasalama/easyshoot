# Agent skills

Skills that coding agents (Claude Code and others that read `SKILL.md`) load when working on EasyShoot. Both are MIT licensed; each folder keeps its upstream `LICENSE`.

| Skill | Source | Pinned commit |
|:--|:--|:--|
| `swiftui-expert/` | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) (`skills/swiftui-expert-skill`) | `204dba7` |
| `macos-development/` | [e-palmisano/macos-dev](https://github.com/e-palmisano/macos-dev) (`skills/macos-development`) | `31dace7` |

Only `SKILL.md`, `references/` and the license are copied. The Instruments trace scripts from `swiftui-expert-skill` are left out; get them from upstream if you need trace analysis.

To update, copy the same folders again from a newer upstream commit and change the table.
