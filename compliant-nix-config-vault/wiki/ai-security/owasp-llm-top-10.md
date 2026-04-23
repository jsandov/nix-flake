# OWASP Top 10 for LLM Applications (2025)

Infrastructure-level mitigations for each LLM risk. ~60% of full mitigations require application code — see [[ai-security-residual-risks]].

## LLM01: Prompt Injection
- **Risk:** Adversarial input causes model to override instructions or weaponize agents
- **Infra:** Separate UIDs for Ollama and orchestrator, IPAddressAllow/Deny on agents
- **App:** Structured prompt formatting, tool call validation against allowlist, canary tokens
- **Truth:** Infrastructure limits blast radius — cannot prevent injection itself

## LLM02: Sensitive Information Disclosure
- **Risk:** Model leaks training data, system prompts, secrets, file paths
- **Infra:** InaccessiblePaths for `/run/secrets`, ephemeral workspaces, ProtectHome=true
- **App:** Output filter scanning for keys, tokens, internal paths, PII patterns

## LLM03: Supply Chain Vulnerabilities
- **Risk:** Compromised models, registries, dependencies
- **Infra:** Pinned flake inputs, AIDE on model paths, egress filtering for Ollama UID
- **Reality:** Model provenance is trust-on-first-download — see [[ai-security-residual-risks]]

## LLM04: Data and Model Poisoning
- **Risk:** Tampered RAG documents or model weights
- **Infra:** Write-protect RAG stores (writable only by ingestion service), AIDE monitoring
- **App:** Authenticated document ingestion, provenance tracking
- **Truth:** Detecting sophisticated poisoning is an **open research problem**

## LLM05: Improper Output Handling
- **Risk:** Model outputs passed to tools without validation → injection attacks
- **Infra:** No shell binaries in agent namespace, LimitFSIZE=100M, SystemCallFilter
- **App:** Mandatory argument validation schemas, no `shell=True`, parameterized queries

## LLM06: Excessive Agency
- **Risk:** Agents invoke tools beyond what's needed
- **Infra:** CapabilityBoundingSet="", per-agent UID, workspace isolation
- **App:** Chain depth limits (default: 10), rate limits (write: 10/min, destructive: 2/min + approval)

## LLM07: System Prompt Leakage
- **Risk:** Attackers extract behavioral instructions
- **Infra:** Prompts in read-only path, InaccessiblePaths for inference engine, audit on prompt dir
- **App:** Fragment detection in outputs (block >30 chars of system prompt)

## LLM08: Vector and Embedding Weaknesses
- **Risk:** Exploited RAG pipeline — collision attacks, embedding reversal
- **Infra:** Separate vector-db service/UID, InaccessiblePaths for agents
- **App:** Retrieval diversity checks, similarity score anomaly detection (flag >0.99)

## LLM09: Misinformation / Hallucination
- **Risk:** Hallucinated tool arguments cause real damage in agentic workflows
- **Infra:** Sandbox bounds damage, NixOS rollback for recovery
- **App:** Tool argument validation against reality, intermediate chain checkpoints
- **Truth:** LLM self-reported confidence is unreliable — don't gate on it

## LLM10: Unbounded Consumption
- **Risk:** GPU/memory/disk exhaustion from abuse or runaway agents
- **Infra:** MemoryMax, CPUQuota, TasksMax, RuntimeMaxSec=1800, log rotation with caps
- **Gap:** cgroups cannot enforce GPU VRAM limits — see [[ai-security-residual-risks]]

## Key Takeaways

- Every risk has both infrastructure and application-layer controls
- Infrastructure controls are **enforced** by NixOS/systemd — high assurance
- Application controls **require custom code** that doesn't exist yet — medium assurance
- The [[owasp-agentic-threats]] are the agentic amplification of these base risks
