# AI-Specific Security — OWASP Top 10 for LLMs + MITRE ATLAS

Source: prd-owasp.md, prd-ai-governance.md

## OWASP Top 10 for LLM Applications (2025)

### LLM01: Prompt Injection
- **Primary risk for agentic systems** — poisoned input can weaponize agents
- Direct (user input) and indirect (RAG documents, tool outputs)
- Infrastructure mitigations: separate UIDs for Ollama and orchestrator, network segmentation, IPAddressAllow/Deny
- **Infrastructure cannot prevent injection** — only limits blast radius

### LLM02: Sensitive Information Disclosure
- Model may leak training data, system prompts, secrets, filesystem paths
- Use InaccessiblePaths for /run/secrets, /etc/secrets, /root
- Ephemeral agent workspaces cleaned on restart
- Output filtering must scan for API keys, tokens, internal paths

### LLM03: Supply Chain Vulnerabilities
- Compromised models, registries, dependencies
- Pinned flake inputs with hash verification in flake.lock
- AIDE monitoring on model storage paths
- **Model provenance is trust-on-first-download** — Ollama has no cryptographic attestation

### LLM04: Data and Model Poisoning
- RAG poisoning is the most relevant vector
- Write-protect RAG data stores — writable only by dedicated ingestion service
- Model files set to read-only after deployment
- Detecting sophisticated poisoning is an **open research problem**

### LLM05: Improper Output Handling
- Model outputs passed to tools without validation → code/command/SQL injection
- Agent tools must NEVER use shell=True
- TemporaryFileSystem to restrict shell binaries from agent view
- LimitFSIZE=100M, LimitNPROC=64 for resource protection

### LLM06: Excessive Agency
- Agents invoking tools beyond what's needed
- Per-agent UID, CapabilityBoundingSet="", IPAddressDeny="any"
- Max action chain depth (default: 10), human approval for destructive actions
- Rate limits: read tools 60/min, write 10/min, destructive 2/min with approval

### LLM07: System Prompt Leakage
- Store prompts in read-only path, InaccessiblePaths for inference engine
- Audit access to prompt directory
- Output filter: block responses containing >30 chars of system prompt

### LLM08: Vector and Embedding Weaknesses
- Separate vector-db service with own UID
- Agent processes get InaccessiblePaths to vector store
- Similarity score clamping: flag scores >0.99

### LLM09: Misinformation / Hallucination
- Agentic amplification: hallucinated tool arguments cause real damage
- systemd sandbox bounds the damage even with hallucinated actions
- Tool implementations must validate arguments against reality
- **LLM self-reported confidence is unreliable** — don't use as gating mechanism

### LLM10: Unbounded Consumption
- MemoryMax, CPUQuota, TasksMax via systemd cgroups
- **GPU VRAM is a blind spot** — cgroups cannot enforce VRAM limits
- RuntimeMaxSec=1800 for session hard limits
- Log rotation with size caps

## Critical Honesty: Residual Risks

1. **Prompt injection remains unsolved** — sandboxing limits blast radius, doesn't prevent
2. **~60% of controls require custom application code that doesn't exist yet**
3. **Goal hijacking within policy is invisible** to infrastructure monitoring
4. **cgroups cannot enforce GPU VRAM limits**
5. **Model provenance is trust-on-first-download**

## OWASP Agentic AI Threats (AGT-01 through AGT-09)

| Threat | Key Control |
|---|---|
| AGT-01: Unexpected Tool Invocation | Per-task allowlists at systemd level |
| AGT-02: Privilege Escalation via Tool Chaining | NoExecPaths on workspaces, taint tracking |
| AGT-03: Excessive Autonomy | RuntimeMaxSec=1800, WatchdogSec, pause-and-confirm |
| AGT-04: Identity Spoofing | UID-based identity, SO_PEERCRED verification |
| AGT-05: Memory Poisoning | Ephemeral session dirs, RuntimeDirectoryPreserve=no |
| AGT-06: Cascading Hallucination | Independent failure domains, read-only handoff |
| AGT-07: Uncontrolled Resource Access | ProtectSystem=strict, PrivateDevices=true |
| AGT-08: Insufficient Guardrails | Workspace snapshots, transaction boundaries |
| AGT-09: Goal/Instruction Hijacking | Immutable goal specs, network isolation |

## MITRE ATLAS Threat Model

| ATLAS ID | Technique | Primary Mitigation |
|---|---|---|
| AML.T0010 | ML Supply Chain Compromise | Hash verification, AIDE |
| AML.T0015 | Evade ML Model | Input validation, adversarial testing |
| AML.T0018 | Backdoor ML Model | Provenance, behavioral testing |
| AML.T0024 | Exfiltration via Inference API | FDE, permissions, LAN-only |
| AML.T0040 | Inference API Abuse | Rate limiting, auth, resource limits |
| AML.T0043 | Craft Adversarial Data | Sandbox, approval gates |
| AML.T0051 | LLM Prompt Injection | Input validation, no egress |
| AML.T0056 | LLM Data Leakage | Output logging, network isolation |

**Note:** ATLAS technique IDs are actively reorganized. Verify quarterly against current knowledge base.
