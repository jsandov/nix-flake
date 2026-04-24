# Multi-agent parallel execution — session lessons

Captured during the session that spawned three subagents in parallel for ARCH-09, ARCH-12, and AI-14+15+16. All three agents hit sandbox restrictions that blocked git/gh/curl/WebFetch; all three produced good file content; main session had to carry over three bodies of work and untangle a collision on the shared worktree. Lessons below are worth lifting to wiki entries 35+ on a future compile pass.

## What happened

1. Main session dispatched three agents with `Agent({ ..., run_in_background: true })`.
2. All three attempted their tasks in parallel.
3. All three wrote files to the shared `/root/gt/nix_flake/crew/nixoser` worktree.
4. All three tried `git checkout -b <branch>` and were denied by subagent sandbox (`Permission to use Bash has been denied` for write-side git and every `gh` invocation).
5. Each reported back "work done, cannot push" — and left its edits sitting in the main session's worktree.
6. Main session had to: save each agent's diff aside as a patch, untangle the shared worktree, create three branches from `main`, apply each patch cleanly, commit + push + PR one at a time.

## Lesson 1 — Subagents don't get an isolated worktree by default

The `Agent` tool accepts `isolation: "worktree"` as a parameter. I did not set it on any of the three dispatches. As a result, every agent ran in the main session's working directory and shared the same git branch state. Agent C's `git add` even moved my ARCH-09 branch's staged-files set because it ran on top of my branch.

**Rule (for future multi-agent dispatches):** always set `isolation: "worktree"` when dispatching >1 agent that needs to write files AND do git operations. Without it, the three agents race on one directory.

## Lesson 2 — Sandbox blocks git mutation, not git read

Each subagent could do `git status`, `git diff`, `git log`, `git add`, but **not** `git checkout -b`, `git commit`, `git push`, `git branch`, `git reset`, `git restore`, `git stash`. Also blocked: `gh *` commands, `curl`, `WebFetch`, `WebSearch`. This means a subagent cannot independently land a PR today; it can only prepare the changes.

**Consequence:** the "end-to-end" workflow (branch → commit → push → PR → verify) that I routinely ran as the main session is **not available to subagents**. Agents produce patches; main session lands them.

**Rule:** when dispatching an agent for a git-terminal task, accept that it will produce file edits + a summary, not a merged PR. Plan the session around this.

## Lesson 3 — Patches are the right handoff format

When an agent reports "work done but can't push," the main session needs to extract the work. Two approaches tested this session:

- **Agent A (ARCH-09)** reported no uncommitted files because it had not modified the worktree — sandbox blocked even `git add`. Main session reproduced the work from scratch using the agent's design notes. ~15 min of main-session context.
- **Agent B (HITRUST)** staged its changes via a lone successful `git add`. Main session ran `git diff --cached > /tmp/agent-patches/hitrust-prd.patch`, reset, applied the patch on a fresh branch. ~3 min.
- **Agent C (ARCH-12)** similarly left staged changes. Same workflow. ~3 min.

**Rule:** instruct subagents to always `git add` their changes before reporting back, so the main session can extract a clean patch. Even if the agent can't commit, the staging area captures the work.

## Lesson 4 — Shared-worktree collisions are fast-destructive

At one point during this session the worktree contained:
- Main session's ARCH-09 edits to `flake.nix` + `modules/stig-baseline/default.nix` (unstaged)
- Agent B's HITRUST edits to `docs/prd/prd-hitrust.md` (staged)
- Agent C's ARCH-12 edits to `docs/prd/prd.md` (staged) + raw note (staged)
- Main session's ARCH-09 raw note (untracked)
- Main session on branch `feat/arch-09-secure-boot`

Without explicit untangling, a `git commit -a` would have dragged three unrelated PRs onto one branch. I had to:
1. Save each agent's staged diff as a patch (`git diff --cached > /tmp/...patch`).
2. `git reset HEAD <files>` + `git checkout -- <files>` to revert agent work.
3. Commit my own ARCH-09 work.
4. Check out main, branch new, apply patch, commit, push, PR — per agent.

**Rule:** use `isolation: "worktree"` to avoid this entirely. If you can't (older Agent tool, permission issues), serialise the agents: dispatch one, wait for it, merge, dispatch next.

## Lesson 5 — Parallel dispatch only saves wall-clock time if CI is the long pole

The three agents took ~3–10 minutes each, running in parallel. The untangling + sequential landing took ~20 minutes in the main session. Net gain vs sequential: modest — maybe 15 minutes saved.

The savings would be larger if the CI run time were the dominant cost (5+ minutes per PR). At current CI speeds (~1 minute/run) and our parallel-branch pattern, three PRs land at ~5–7 minutes total wall-clock; the orchestration overhead doesn't amortise cleanly across only three.

**Rule:** parallel agent dispatch is valuable for research (three agents doing distinct WebSearch work in parallel) and for code-heavy independent modules. It is marginal for PRD-doc sweeps where CI is fast and patching is quick.

## Lesson 6 — The assertion-failure-on-lockout gotcha

ARCH-09 with `users.mutableUsers = false` (canonical value) failed CI with:

```
Failed assertions:
- Neither the root account nor any wheel user has a password or SSH authorized key.
You must set one to prevent being locked out of your system.
```

This is a NixOS safety assertion that fires when `mutableUsers = false` and no wheel user has any authentication configured. Skeleton doesn't declare an admin user yet (that's a future TODO). Fix: `users.allowNoPasswordLogin = lib.mkDefault true;` as a skeleton-only escape hatch, with a comment explaining that real deployments declare the admin user and override this back to `false` via `lib.mkForce`.

**Rule worth capturing:** when landing a module that sets a lock-down value from canonical, check if NixOS has a corresponding safety assertion that prevents skeleton evaluation. If yes, add a `lib.mkDefault` escape hatch with a comment naming the real-deployment override pattern.

## Suggested wiki compile targets

- `wiki/review-findings/lessons-learned.md` — add entries 35–37 (or however many):
  - 35: subagent sandbox blocks git push / gh — plan for it.
  - 36: multi-agent worktree collisions without `isolation: "worktree"`.
  - 37: `users.mutableUsers = false` lock-out assertion + the allowNoPasswordLogin escape hatch.
- `wiki/nixos-platform/nixos-gotchas.md` — new entry #17 on the mutableUsers assertion + escape hatch.
- `wiki/architecture/multi-agent-orchestration.md` (possibly new) — the isolation-worktree rule, the patch-handoff rule, when parallel pays off vs when serial wins.
