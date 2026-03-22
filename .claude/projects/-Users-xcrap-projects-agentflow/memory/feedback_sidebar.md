---
name: Keep left sidebar always
description: Never remove the left project sidebar - user explicitly wants it. Only the right inspector was removed.
type: feedback
---

Do NOT remove the left sidebar (project list). The user explicitly corrected this. Only the right inspector sidebar was removed.

**Why:** The left sidebar is the primary navigation for switching between projects. Removing it breaks the core UX.

**How to apply:** When asked to remove "the sidebar" or "the right sidebar", only touch the right/inspector panel. The left NavigationSplitView sidebar with ProjectSidebarView must always remain.
