# OWASP Agentic AI Threats

Nine threat categories specific to AI agents with real tool access.

## AGT-01: Unexpected Tool Invocation
Agent calls tools not intended for current task context.
- **Control:** Per-task allowlists at systemd level (ReadOnlyPaths, no write access for research agents)
- **Control:** Binary availability restriction — don't bind-mount shells into agent namespace

## AGT-02: Privilege Escalation via Tool Chaining
Individually-permitted tools chained to achieve unauthorized outcomes.
- **Control:** `NoExecPaths` on agent workspaces — written files cannot be executed
- **Control:** Cross-agent isolation via InaccessiblePaths
- **App:** Forbidden tool sequence enforcement, credential opaque references

## AGT-03: Excessive Autonomy
Long sequences of consequential actions without human oversight.
- **Control:** `RuntimeMaxSec=1800` (30-min hard limit), `WatchdogSec=300`
- **App:** Mandatory pause-and-confirm every N tool invocations, auto-termination on no confirmation

## AGT-04: Identity Spoofing Between Agents
One agent impersonates another for unauthorized access.
- **Control:** UID-based identity enforced by kernel, not application claims
- **Control:** Separate Unix sockets per agent, `SO_PEERCRED` verification
- **Control:** No shared secrets between agent UIDs

## AGT-05: Memory Poisoning
Attacker manipulates agent's persistent/session memory to influence future decisions.
- **Control:** Ephemeral session directories (`RuntimeDirectoryPreserve=no`)
- **Control:** AIDE integrity monitoring on memory stores
- **App:** Memory integrity validation, content filtering on memory writes, 30-day expiration

## AGT-06: Cascading Hallucination Failures
Hallucinated output from one step becomes accepted input for next step.
- **Control:** Independent failure domains — separate systemd units per pipeline stage
- **Control:** Read-only handoff between stages
- **App:** Input validation at each stage, ground truth checkpoints, max 2 retries per tool

## AGT-07: Uncontrolled Resource Access
Agent accesses resources beyond current task scope.
- **Control:** `PrivateDevices=true` (no GPU for agents), `DeviceAllow=[]`
- **Control:** Comprehensive systemd hardening: ProtectSystem, ProtectKernel*, ProtectClock, etc.
- **Control:** Deny-by-default for all resource access

## AGT-08: Insufficient Guardrails on Multi-Step Actions
Multi-step workflows lack checkpoints, rollback, or approval gates.
- **Control:** Workspace snapshots before destructive operations
- **Control:** NixOS generation rollback for system-level recovery
- **App:** Transaction boundaries, reversibility classification, progressive approval escalation

## AGT-09: Goal/Instruction Hijacking
Attacker manipulates agent's goals mid-execution via prompt injection or manipulated tool outputs.
- **Control:** Immutable goal specs in read-only path (`/run/agent-goals`)
- **Control:** Network isolation — agents cannot receive external instructions
- **App:** Goal anchoring at each step, drift detection, tool output sanitization

## Key Takeaways

- These threats are the **agentic amplification** of [[owasp-llm-top-10]] risks
- systemd provides the strongest infrastructure controls — UID separation, namespace isolation, capability bounding
- The biggest gap: goal hijacking within policy-allowed boundaries is **invisible to infrastructure monitoring**
- Per-agent UID allocation is the foundation — kernel-enforced, not application-trusting
