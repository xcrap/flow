---
name: Projects are folder-based
description: Each project maps to a folder on disk. Agents and terminals run in that folder's context.
type: feedback
---

Projects must be folder-based. When creating a project, the user picks a root folder. All agents and terminals within that project run with that folder as their working directory.

**Why:** The user wants each project to represent a real codebase/folder on disk, not an abstract concept.

**How to apply:** Project creation must include a folder picker. Store the root path in the Project model. Pass it to ClaudeCodeProvider and TerminalSession as workingDirectory.
