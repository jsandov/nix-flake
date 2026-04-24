# PRD Module: OWASP Top 10 for LLM Applications (2025) and OWASP Agentic AI Threats

## Scope

This document is a compliance-specific module for the Control-Mapped NixOS AI Agentic Server PRD. It provides detailed risk analysis, mitigation requirements, and implementation guidance for two OWASP frameworks:

1. **OWASP Top 10 for LLM Applications (2025 edition)**
2. **OWASP Agentic AI Threats**

All requirements assume the system described in the parent PRD: a LAN-only, flake-based NixOS server running Ollama (port 11434) and application APIs (port 8000) with SSH access (port 22), GPU-backed local inference, and sandboxed agentic workflows. No public Internet ingress is permitted. Agents run as isolated systemd services with tool allowlisting and human approval gates.

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the OWASP-specific rationale; the implementation flake uses only the canonical values.

---

## Part 1: OWASP Top 10 for LLM Applications (2025)

---

### LLM01: Prompt Injection

#### Risk description

An attacker crafts input that causes the LLM to override its system prompt, bypass safety instructions, or execute unintended actions. In this environment, prompt injection is the primary vector for weaponizing agents: a poisoned user query or retrieved document could instruct the model to invoke privileged tools, exfiltrate data via tool calls, or bypass approval gates. Because this server runs agentic workflows with real tool access, prompt injection has direct operational consequences beyond information disclosure.

Direct injection occurs when a user submits adversarial instructions in their query. Indirect injection occurs when malicious instructions are embedded in retrieved context (RAG documents, tool outputs, prior conversation history).

#### OS/infrastructure-level mitigations

- **Separate process boundaries**: The inference engine (Ollama) and the agent orchestrator must run as distinct systemd services under separate UIDs. A successful prompt injection against the model cannot directly invoke OS primitives without traversing the orchestrator's tool validation layer.

```nix
{
  systemd.services.ollama = {
    serviceConfig = {
      User = "ollama";
      Group = "ollama";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/ollama" ];
      RestrictAddressFamilies = [ "AF_INET" "AF_UNIX" ];
      SystemCallFilter = [ "@system-service" "~@privileged" "~@mount" ];
      # MemoryDenyWriteExecute: DO NOT ENABLE for CUDA/GPU services.
      # CUDA requires W+X memory for JIT compilation of PTX kernels.
      # Enabling this directive crashes GPU inference at runtime.
      # See prd.md Appendix A.3 and HIPAA module Section 2.3.3.
      # Compensating controls: SystemCallFilter, RestrictAddressFamilies,
      # ProtectSystem=strict, NoNewPrivileges=true.
    };
  };
}
```

- **Network segmentation between inference and tool execution**: The agent sandbox must not share a network namespace with the inference service. Tool-executing agents must reach Ollama only through the loopback interface on port 11434 and must not be able to forge requests to other local services.

```nix
{
  systemd.services.agent-runner = {
    serviceConfig = {
      # Canonical systemd hardening values per prd.md Appendix A.3
      PrivateNetwork = false;  # needs loopback access
      IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
      IPAddressDeny = "any";
    };
  };
}
```

#### Application-level mitigations

- The orchestrator must implement a strict separation between system instructions, user input, and retrieved context. These must be passed as structurally distinct message types in the API call, never concatenated into a single text field.
- All user-supplied text and RAG-retrieved content must be treated as untrusted data. The orchestrator must not parse natural-language instructions from these fields as control-plane directives.
- The application must implement an output classifier that detects when model responses contain tool invocation patterns that were not explicitly requested by the system prompt.
- Tool calls returned by the model must be validated against the current session's allowlist before execution. The model's output alone must never be sufficient to invoke a tool.
- A canary-token mechanism should be embedded in system prompts. If the model's output contains the canary, the system must flag the interaction as a potential injection and halt tool execution.

#### Monitoring and detection

- Log all prompts and completions (with PII redaction) to the audit trail under `/var/log/ai-audit/`.
- Alert when: (a) a model response attempts to invoke a tool not in the session allowlist, (b) a model response contains fragments of the system prompt, (c) tool invocation rate for a session exceeds baseline by more than 2x within a sliding 60-second window.
- Retain prompt/completion logs for a minimum of 90 days for incident investigation.

#### Implementation requirements

- `ai-services` module: Enforce separate systemd units for Ollama and the orchestrator.
- `agent-sandbox` module: Validate every tool call against the allowlist before execution. Reject and log any tool call not on the list.
- Application config: Implement structured prompt formatting with delimiters that are validated server-side.

---

### LLM02: Sensitive Information Disclosure

#### Risk description

The LLM reveals confidential data in its responses: training data memorization, system prompt contents, secrets from retrieved context, PII from conversation history, or internal infrastructure details. In this environment, the model may process internal documents via RAG, see filesystem paths from tool outputs, or encounter secrets in environment variables or config files passed as context. Any of these could leak through model responses to unauthorized requesters.

#### OS/infrastructure-level mitigations

- **Secrets isolation**: Secrets must never be present in the Nix store, environment variables visible to the inference process, or any path readable by the Ollama or agent-runner UIDs.

```nix
{
  # Use sops-nix for secrets; never pass secrets as environment variables
  # to AI service processes
  systemd.services.ollama.serviceConfig = {
    ProtectHome = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ "/var/lib/ollama" ];
    # Ollama cannot read /etc/secrets, /run/secrets, or home directories
    InaccessiblePaths = [ "/run/secrets" "/etc/secrets" "/root" ];
  };

  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    # Agent runner gets only its own secrets via bind-mount
    BindReadOnlyPaths = [ "/run/secrets/agent-api-key:/run/agent-secrets/api-key" ];
    InaccessiblePaths = [ "/run/secrets" "/etc/secrets" ];
  };
}
```

- **Filesystem read restrictions**: The inference service and agent processes must have the minimum filesystem visibility required. Use `ReadOnlyPaths`, `InaccessiblePaths`, and `TemporaryFileSystem` to prevent access to system configs, other service data, and user home directories.

- **tmpfiles.d for ephemeral workspaces**: Agent working directories must be created as ephemeral tmpfiles that are cleaned on service restart.

```nix
{
  systemd.tmpfiles.rules = [
    "d /var/lib/agent-runner/workspace 0750 agent agent - -"
    "D /var/lib/agent-runner/workspace 0750 agent agent 1d -"
  ];
}
```

#### Application-level mitigations

- The orchestrator must implement an output filter that scans model responses for patterns matching: API keys, tokens, file paths outside approved directories, IP addresses on internal ranges, and configurable regex patterns for organization-specific sensitive data.
- RAG retrieval must enforce access control: the documents returned to the model must be filtered based on the requesting user's authorization level, not served from a flat index.
- System prompts must not contain secrets, credentials, or internal infrastructure details. Any dynamic configuration needed by the prompt must be injected through a structured metadata channel that is excluded from the model's visible context.
- Conversation history sent to the model must be truncated and sanitized. Outputs from previous tool calls that contained sensitive data must be replaced with summaries before being included in subsequent context windows.

#### Monitoring and detection

- Scan all model outputs for sensitive data patterns before returning to the user. Log and redact matches.
- Alert on: detection of secret-like patterns in model output, model responses containing filesystem paths outside `/var/lib/agent-runner/workspace`, responses containing internal IP addresses or hostnames.
- Track unique sensitive-data detection events per user session. Escalate if a single session triggers more than 3 detections in 10 minutes.

#### Implementation requirements

- `agent-sandbox` module: Enforce `InaccessiblePaths` for all secret storage locations.
- `ai-services` module: Output filtering middleware is required before any response reaches the client.
- Application config: Implement configurable regex-based output scanning with a default ruleset for keys, tokens, and paths.

---

### LLM03: Supply Chain Vulnerabilities

#### Risk description

Compromise of models, model registries, training data, inference frameworks, or dependencies introduces backdoors, poisoned behaviors, or vulnerable code into the stack. In this environment, the supply chain includes: Ollama itself (binary and container), model weights pulled from registries (Ollama library, Hugging Face), Python/Node dependencies for the orchestrator, Nix packages, and flake inputs. A compromised model could contain embedded instructions that activate on specific inputs. A compromised dependency could exfiltrate data or provide a persistent backdoor.

#### OS/infrastructure-level mitigations

- **Pinned flake inputs with hash verification**: All Nix flake inputs must be pinned to specific revisions with integrity hashes recorded in `flake.lock`. Updates to flake inputs must be a reviewed, deliberate action.

```nix
{
  # flake.nix — all inputs pinned
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # Explicit pin; flake.lock records the hash
  };
}
```

- **Model storage integrity**: Downloaded model files must be stored in a dedicated path with filesystem-level integrity checking. AIDE must include model storage paths in its baseline.

```nix
{
  # Add model storage to AIDE monitoring
  environment.etc."aide.conf".text = ''
    /var/lib/ollama/models R+sha256
  '';
}
```

- **Restrict model download sources**: The Ollama service must be configured to pull models only from approved registries. Egress filtering must block the Ollama process from reaching unapproved endpoints.

- **Package pinning**: All application dependencies must be built in the Nix derivation with fixed-output hashes or managed through a lock file checked into the repository.

#### Application-level mitigations

- Maintain an inventory of all models in use, including their source, version/hash, and last verification date.
- Before deploying a new model, validate its checksum against a known-good manifest.
- The orchestrator's dependency tree must be auditable. Use `nix flake metadata` and `nix flake check` as part of CI/CD to verify no unexpected input changes.
- Third-party plugins, tools, or extensions loaded by the orchestrator must be explicitly declared and reviewed. No dynamic plugin loading from user-supplied paths.

#### Monitoring and detection

- AIDE integrity checks must cover `/var/lib/ollama/models/` and alert on any unexpected file change.
- Log all model pull operations with source URL, timestamp, and resulting file hash.
- Alert on: model file changes outside of a documented deployment window, flake.lock changes in uncommitted or unreviewed code, Ollama process making network connections to non-allowlisted hosts.

#### Implementation requirements

- `ai-services` module: Pin Ollama version in the Nix derivation. Include model paths in AIDE config.
- `audit-and-aide` module: Extend AIDE rules to cover model storage directories.
- `lan-only-network` module: Egress filtering for the Ollama UID to restrict download sources (see LLM10 for resource controls; this is about endpoint restriction).
- Application config: Model inventory file checked into the repository with expected hashes.

---

### LLM04: Data and Model Poisoning

#### Risk description

Attackers manipulate training data, fine-tuning data, or RAG knowledge bases to embed biases, backdoors, or targeted misinformation into model behavior. In this local inference environment, poisoning vectors include: tampered model weights from untrusted sources, poisoned documents injected into RAG corpora, manipulated embeddings in the vector store, and adversarial fine-tuning data if local fine-tuning is performed.

RAG poisoning is particularly relevant: if an attacker can write to the document store that feeds retrieval, they can inject content that causes the model to produce specific outputs or execute specific tool calls when certain queries are made.

#### OS/infrastructure-level mitigations

- **Write-protect RAG data stores**: The vector database and document storage paths must be writable only by a dedicated ingestion service, not by the inference or agent processes.

```nix
{
  systemd.services.rag-ingestion = {
    serviceConfig = {
      User = "rag-ingest";
      Group = "rag-ingest";
      ReadWritePaths = [ "/var/lib/rag-data" ];
    };
  };

  systemd.services.ollama.serviceConfig = {
    ReadOnlyPaths = [ "/var/lib/rag-data" ];
  };

  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    ReadOnlyPaths = [ "/var/lib/rag-data" ];
    # Agent cannot modify the knowledge base
  };
}
```

- **Model file immutability**: After a model is deployed, its files should be set to read-only for all processes except a dedicated model-management service.

- **Filesystem integrity monitoring**: AIDE must monitor both model files and RAG data directories for unauthorized changes.

```nix
{
  environment.etc."aide.conf".text = ''
    /var/lib/ollama/models R+sha256
    /var/lib/rag-data R+sha256
  '';
}
```

#### Application-level mitigations

- Document ingestion into the RAG pipeline must require authentication and authorization. Anonymous or unauthenticated document submission must be rejected.
- All documents ingested into the RAG store must be logged with: source, submitter identity, timestamp, and content hash.
- The application should implement provenance tracking for RAG-retrieved content so that model responses can be traced back to specific source documents.
- If local fine-tuning is performed, training data must be validated and stored in a version-controlled, integrity-checked repository.
- RAG retrieval should implement relevance scoring with an anomaly threshold: documents with unusually high relevance scores to common queries should be flagged for review.

#### Model provenance

Ollama's model distribution does not currently support cryptographic provenance verification beyond transport-layer TLS. The model inventory with expected hashes described below is trust-on-first-download: the hash is recorded after the first pull and verified against that baseline on subsequent checks, but there is no independent chain of trust back to the model trainer.

#### Monitoring and detection

- Alert on any write to RAG data paths outside of the authenticated ingestion pipeline.
- Alert on AIDE integrity failures for model or RAG data files.
- Log all document ingestion events. Monitor ingestion volume and flag anomalies (sudden spikes in document count or size).
- Document expected behavior for each deployed model (expected output characteristics for a set of reference queries) and monitor for deviation. Note that defining "expected behavior" precisely enough to detect poisoning requires domain-specific effort and is an imperfect signal.
- Acknowledge: detecting sophisticated model poisoning through output analysis is an open research problem. Behavioral monitoring may catch gross deviations but will not reliably detect targeted, subtle poisoning.

#### Implementation requirements

- `agent-sandbox` module: Ensure agent processes have read-only access to RAG data.
- `audit-and-aide` module: Add RAG data paths to AIDE monitoring rules.
- `ai-services` module: Separate ingestion and retrieval into distinct services with distinct UIDs.
- Application config: Implement authenticated document ingestion with audit logging.
- Application config: Model integrity verification via checksums before deployment. Verify model file hashes against the inventory manifest before any model is loaded for inference.
- Application config: Restrict model sources to known registries. The Ollama service must only pull from an explicitly configured allowlist of model sources.
- Application config: Model inventory file checked into the repository with expected hashes, source registry, download date, and reference behavior descriptions.

---

### LLM05: Improper Output Handling

#### Risk description

Model outputs are used in downstream operations without adequate validation, sanitization, or escaping. This can lead to code injection, command injection, SQL injection, XSS, or SSRF when model-generated content is passed to interpreters, databases, web frontends, APIs, or the operating system. In this agentic environment, the risk is severe: model outputs may be passed directly to tool implementations that execute shell commands, write files, make API calls, or modify system state.

#### OS/infrastructure-level mitigations

- **No direct shell access for agents**: Agent tool implementations must never use `os.system()`, `subprocess.Popen(shell=True)`, or equivalent patterns that pass model output to a shell interpreter.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    # Restrict available system calls to prevent shell spawning abuse
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@mount"
      "~@raw-io"
    ];
    # Remove shell binaries from the agent's view
    TemporaryFileSystem = "/bin:ro";
    BindReadOnlyPaths = [
      "${pkgs.coreutils}/bin/env:/bin/env"
      # Only bind specific required binaries
    ];
  };
}
```

- **Filesystem write restrictions**: Agent processes must be restricted to writing only within their designated workspace. Any attempt to write outside this path must be denied by systemd sandboxing.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    ReadWritePaths = [ "/var/lib/agent-runner/workspace" ];
    ProtectSystem = "strict";
    ProtectHome = true;
  };
}
```

- **Resource limits**: Prevent model output from causing resource exhaustion via oversized writes or runaway processes.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    LimitFSIZE = "100M";    # Max file size any child can create
    LimitNPROC = 64;         # Max child processes
    LimitAS = "2G";          # Max address space
  };
}
```

#### Application-level mitigations

- All model outputs must be treated as untrusted user input. Every tool implementation must validate and sanitize model-provided arguments against a strict schema before execution.
- Tool implementations that write to databases must use parameterized queries exclusively.
- Tool implementations that generate HTTP requests must validate URLs against an allowlist of permitted hosts and paths.
- Tool implementations that write files must validate the target path is within the allowed workspace using canonical path resolution (resolving symlinks before comparison).
- Model outputs rendered in any web interface must be escaped for the target context (HTML, JavaScript, URL) using established escaping libraries.
- Tool argument schemas must be enforced with strict typing: if a tool expects an integer, the orchestrator must reject non-integer values before the tool is invoked.

#### Monitoring and detection

- Log all tool invocations with full arguments (redacting secrets) and results.
- Alert on: tool argument validation failures (potential injection attempts), file write attempts outside the workspace (caught by systemd), process spawn attempts exceeding `LimitNPROC`.
- Track tool error rates per session. A session with more than 5 tool failures in 5 minutes should be flagged for review.

#### Implementation requirements

- `agent-sandbox` module: Enforce `ProtectSystem=strict`, `ReadWritePaths` limited to workspace, resource limits.
- Application config: Mandatory argument validation schemas for all tool implementations. No raw shell execution.
- `ai-services` module: Output escaping middleware for any web-facing API responses.

---

### LLM06: Excessive Agency

#### Risk description

The LLM-based system is granted capabilities beyond what is required for its task, or it takes actions autonomously that should require human oversight. In this agentic environment, excessive agency is the risk that agents can invoke tools, chain actions, or escalate their own capabilities in ways that exceed the operator's intent. This includes: tools with overly broad permissions, missing approval gates for destructive actions, unbounded action chains, and the ability to self-modify tool access.

#### OS/infrastructure-level mitigations

- **Minimal tool surface**: Each agent profile must declare an explicit, minimal set of allowed tools. The systemd unit and application configuration must enforce this list independently.

```nix
{
  # Define agent profiles with specific tool access
  # This is enforced both in application config and OS-level restrictions

  systemd.services.coding-agent = {
    serviceConfig = {
      User = "agent-coding";
      Group = "agents";
      ReadWritePaths = [ "/var/lib/agents/coding/workspace" ];
      # No network access beyond loopback for inference
      IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
      IPAddressDeny = "any";
      # Cannot access other agents' workspaces
      InaccessiblePaths = [
        "/var/lib/agents/ops"
        "/var/lib/agents/research"
      ];
    };
  };

  systemd.services.ops-agent = {
    serviceConfig = {
      User = "agent-ops";
      Group = "agents";
      ReadWritePaths = [ "/var/lib/agents/ops/workspace" ];
      IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
      IPAddressDeny = "any";
      InaccessiblePaths = [
        "/var/lib/agents/coding"
        "/var/lib/agents/research"
      ];
    };
  };
}
```

- **UID separation per agent type**: Different agent roles must run under different UIDs to enforce kernel-level access control boundaries.

- **Capability bounding**: Agent processes must drop all Linux capabilities and run with `NoNewPrivileges=true`.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    NoNewPrivileges = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    SecureBits = "noroot-locked";
  };
}
```

#### Application-level mitigations

- The orchestrator must enforce a maximum action chain depth per invocation (default: 10 steps). Beyond this limit, the agent must pause and request human approval to continue.
- High-risk actions must be classified and require explicit human approval before execution. The classification must include at minimum: file deletion, file writes outside workspace, any network request, any database modification, any credential access, and any action that modifies agent configuration.
- The orchestrator must not allow an agent to modify its own tool allowlist, system prompt, or approval gate configuration.
- Each tool invocation must include a justification field in the audit log explaining why the model chose to invoke it.
- Rate limits per tool type: read-only tools may execute up to 60 times per minute; write tools up to 10 times per minute; destructive tools (delete, overwrite) up to 2 times per minute with mandatory approval.

#### Monitoring and detection

- Log every tool invocation with: tool name, arguments, result summary, session ID, agent ID, and chain depth.
- Alert on: action chain depth exceeding 80% of the configured maximum, approval gate bypass attempts, tool invocations not in the agent's allowlist, rapid sequential invocations of write or destructive tools.
- Dashboard: real-time view of active agent sessions, current chain depth, tools invoked in the current chain, and pending approval requests.

#### Implementation requirements

- `agent-sandbox` module: Per-agent UID allocation, capability bounding, workspace isolation.
- Application config: Tool allowlists per agent profile, chain depth limits, approval gate classification, rate limits per tool category.
- `ai-services` module: Approval gate API endpoint for human-in-the-loop confirmation.

---

### LLM07: System Prompt Leakage

#### Risk description

The system prompt, which contains the LLM's behavioral instructions, security constraints, tool descriptions, and possibly organizational context, is extracted by a user through direct questioning, prompt injection, or observation of model behavior. In this environment, system prompt leakage could reveal: the list of available tools (enabling targeted prompt injection), security constraints (enabling evasion), internal API endpoints, and organizational policies embedded in the prompt.

#### OS/infrastructure-level mitigations

- **System prompts stored outside the inference process's general filesystem view**: System prompt templates should be stored in a read-only path accessible only to the orchestrator, not to the inference engine or agent processes.

```nix
{
  systemd.tmpfiles.rules = [
    "d /etc/ai-prompts 0550 orchestrator orchestrator - -"
  ];

  systemd.services.orchestrator.serviceConfig = {
    BindReadOnlyPaths = [ "/etc/ai-prompts" ];
  };

  # Inference engine cannot see prompt files
  systemd.services.ollama.serviceConfig = {
    InaccessiblePaths = [ "/etc/ai-prompts" ];
  };
}
```

- **Audit access to prompt storage**: File access auditing should cover the prompt template directory.

```nix
{
  security.auditd.enable = true;
  # Audit rules for prompt file access
  security.audit.rules = [
    "-w /etc/ai-prompts -p r -k prompt-access"
  ];
}
```

#### Application-level mitigations

- The orchestrator must implement system prompt isolation: the system prompt must be injected into the API call at the orchestrator layer and never echoed back to the user, even in debug or error responses.
- Model responses must be scanned for fragments of the system prompt before being returned. If more than a configurable threshold (default: 30 contiguous characters) of the system prompt appears in a response, the response must be blocked and the event logged.
- Error messages returned to users must not contain raw inference API errors, which may include the full prompt context.
- The application must not expose a "debug mode" or "verbose mode" that includes the system prompt in API responses.

#### Monitoring and detection

- Log all instances where system prompt fragment detection triggers.
- Alert on repeated system prompt leakage attempts from a single session or user (more than 2 in 10 minutes).
- Periodically test with adversarial prompts designed to extract the system prompt (red-team testing).

#### Implementation requirements

- `ai-services` module: Prompt file storage with restricted permissions, audit rules on prompt directory.
- Application config: System prompt fragment detection in output filtering. Structured error handling that strips internal context.

---

### LLM08: Vector and Embedding Weaknesses

#### Risk description

The vector database and embedding pipeline used for RAG can be exploited through: adversarial documents crafted to have high similarity to common queries (embedding collision attacks), unauthorized access to embeddings that can be reversed to reconstruct original content, manipulation of the embedding model to produce biased or controllable similarity scores, and injection of adversarial embeddings directly into the vector store.

In this environment, the vector store supports the RAG pipeline and may contain embeddings of internal documents, code, and operational knowledge. Compromising the embedding space undermines the trustworthiness of all RAG-augmented responses.

#### OS/infrastructure-level mitigations

- **Vector store access control**: The vector database must run as its own service with its own UID. Read and write access must be separated.

```nix
{
  systemd.services.vector-db = {
    serviceConfig = {
      User = "vectordb";
      Group = "vectordb";
      StateDirectory = "vector-db";
      ReadWritePaths = [ "/var/lib/vector-db" ];
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
      # Only allow connections from the orchestrator
      IPAddressAllow = [ "127.0.0.1/32" ];
      IPAddressDeny = "any";
    };
  };

  # Agent processes cannot access vector DB files directly
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    InaccessiblePaths = [ "/var/lib/vector-db" ];
  };
}
```

- **Encryption at rest for vector store**: The vector database directory must reside on the encrypted filesystem (covered by the full-disk encryption requirement in the parent PRD).

- **Backup integrity**: Vector store backups must include integrity checksums and be stored in a separate path from the live data.

#### Application-level mitigations

- The embedding pipeline must log all documents processed with source attribution and content hashes.
- Access to raw embeddings via the vector database API must be restricted. The orchestrator should query for similarity results only, not raw vectors, to limit reconstruction attacks.
- Implement retrieval diversity thresholds: if the top-K retrieved documents are all from the same source or all ingested within the same time window, flag the retrieval for review.
- The embedding model itself must be treated as a supply-chain artifact with version pinning and integrity verification (see LLM03).
- Implement cosine similarity clamping: results with suspiciously perfect similarity scores (above 0.99) should be flagged and logged.

#### Monitoring and detection

- Log all vector store write operations with: source document ID, ingesting user/service, timestamp, and embedding dimensions.
- Alert on: bulk embedding insertions (more than 100 vectors in 5 minutes outside scheduled ingestion), vector store access from unauthorized UIDs, retrieval queries returning anomalously high similarity scores.
- Monitor vector store size growth and alert on deviations from baseline.

#### Implementation requirements

- `ai-services` module: Dedicated vector-db systemd service with UID isolation.
- `agent-sandbox` module: Block agent access to vector store files.
- Application config: Retrieval diversity checks, similarity score anomaly detection, authenticated ingestion API.

---

### LLM09: Misinformation

#### Risk description

The LLM generates factually incorrect, fabricated, or misleading content (hallucination) that is then acted upon by users or downstream systems. In an agentic context, misinformation risk is amplified: a hallucinated tool argument (a nonexistent file path, an incorrect API endpoint, a fabricated command) can cause real operational damage when the agent executes it. Cascading hallucinations across multi-step agent chains compound the risk.

#### OS/infrastructure-level mitigations

- **Blast radius containment**: Even if an agent acts on hallucinated information, the damage is bounded by systemd sandboxing. The agent cannot write outside its workspace, access other services' data, or reach the network beyond loopback.

```nix
{
  # This is the same sandbox from LLM05/LLM06 — it serves as the
  # infrastructure backstop for hallucination-driven actions
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    ProtectSystem = "strict";
    ReadWritePaths = [ "/var/lib/agent-runner/workspace" ];
    IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
    IPAddressDeny = "any";
    LimitFSIZE = "100M";
  };
}
```

- **Rollback capability**: The NixOS generation system provides host-level rollback. Agent workspaces should be snapshotted before destructive multi-step operations.

#### Application-level mitigations

- The primary mitigation for misinformation is factual grounding via RAG with cited sources. For factual claims that drive tool invocations, the model must be required to cite specific source documents from the RAG context. Tool invocations based on unsourced claims should be flagged and optionally blocked.
- Tool implementations must validate arguments against reality: a file-read tool must verify the file exists before acting; an API-call tool must verify the endpoint is in the allowlist; a code-execution tool must syntax-check generated code before running it.
- Multi-step agent chains must include intermediate validation checkpoints. After every N steps (configurable, default: 3), the orchestrator must verify that the agent's intermediate state is consistent with the original goal.
- Structured output validation: tool arguments and model outputs that drive actions must conform to strict schemas. Schema validation is deterministic and reliable, unlike LLM self-assessment.
- Note on confidence scoring: local open-weight models served via Ollama generally lack calibrated confidence scores. Ollama does not expose calibrated token-level log probabilities suitable for confidence gating. "Self-reported confidence" from an LLM (e.g., "I am 90% sure") is unreliable and must not be used as a gating mechanism. Heuristic confidence based on argument validation pass rates and source citation coverage is a better, though imperfect, proxy.

#### Monitoring and detection

- Log tool argument validation failures (hallucinated paths, invalid endpoints, malformed arguments).
- Track hallucination rate as a metric: percentage of tool invocations that fail argument validation.
- Alert if the hallucination rate exceeds 20% in a 10-minute window for any agent session.
- Log intermediate chain state at each checkpoint for post-incident analysis.

#### Implementation requirements

- `agent-sandbox` module: Filesystem and network restrictions that bound hallucination impact.
- Application config: Argument validation in all tool implementations, intermediate chain validation, RAG citation requirements, structured output schema enforcement.

---

### LLM10: Unbounded Consumption

#### Risk description

The LLM system consumes excessive resources (GPU compute, memory, disk, network bandwidth, API calls) due to adversarial inputs, runaway agent loops, oversized context windows, or denial-of-service attacks. In this local-inference environment, GPU memory exhaustion crashes the inference service for all users. Disk exhaustion from uncontrolled logging or agent file writes can destabilize the host. CPU/memory exhaustion from spawning too many inference requests can render the server unresponsive.

#### OS/infrastructure-level mitigations

- **cgroups resource limits for all AI services**:

```nix
{
  systemd.services.ollama = {
    serviceConfig = {
      MemoryMax = "24G";         # Bound total memory (adjust for GPU VRAM + system RAM)
      MemoryHigh = "20G";        # Soft limit triggers kernel reclaim
      CPUQuota = "400%";         # 4 cores equivalent
      TasksMax = 128;            # Max threads/processes
      LimitNOFILE = 65536;
      IOWeight = 50;             # Lower IO priority than system services
    };
  };

  systemd.services.agent-runner = {
    serviceConfig = {
      # Canonical systemd hardening values per prd.md Appendix A.3
      MemoryMax = "4G";
      CPUQuota = "200%";
      TasksMax = 64;
      LimitFSIZE = "100M";      # Per-file size limit
      LimitNPROC = 64;
      IOWeight = 30;
    };
  };

  systemd.services.vector-db = {
    serviceConfig = {
      MemoryMax = "8G";
      CPUQuota = "100%";
      TasksMax = 32;
    };
  };
}
```

- **Disk quota enforcement**: Agent workspace directories must have filesystem quotas or be on a separate partition/volume with a size cap.

```nix
{
  # Create a separate mount or use systemd quota controls
  fileSystems."/var/lib/agents" = {
    device = "/dev/disk/by-label/agent-data";
    fsType = "ext4";
    options = [ "usrquota" "grpquota" ];
  };

  # Alternative: systemd-managed state directory with size limit
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    StateDirectory = "agent-runner";
    StateDirectoryMode = "0750";
  };

  # Disk usage monitoring
  systemd.services.disk-monitor = {
    description = "Monitor AI service disk usage";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "check-disk" ''
        usage=$(df /var/lib/agents --output=pcent | tail -1 | tr -d '% ')
        if [ "$usage" -gt 80 ]; then
          echo "ALERT: Agent data partition at ''${usage}% capacity" | systemd-cat -p warning
        fi
      '';
    };
  };

  systemd.timers.disk-monitor = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:0/5";  # Every 5 minutes
  };
}
```

#### GPU memory blind spot

systemd `MemoryMax` controls system RAM allocation via cgroups. It does NOT control GPU VRAM. cgroups have no mechanism to enforce GPU VRAM limits. Ollama can exhaust GPU VRAM independently of system RAM limits, which will either crash the Ollama process or cause it to fall back to CPU inference (resulting in severe performance degradation, potentially 10-100x slower). A model that exceeds available VRAM will degrade without OS-level intervention.

Compensating controls:
- Restrict allowed model sizes in the model registry. Do not deploy models whose VRAM requirements exceed available GPU memory minus a safety margin (recommended: 20% headroom).
- Limit concurrent inference requests via application-layer queue depth controls to prevent multiple simultaneous requests from compounding VRAM usage.
- Monitor GPU memory via `nvidia-smi` (or equivalent for the installed GPU) with alerting thresholds at 80% and 95% VRAM utilization.
- Document the VRAM capacity of the deployed GPU and the expected VRAM consumption of each approved model in the model inventory.

- **Inference request queue limits**: The Ollama service should be fronted by a reverse proxy or rate-limiting layer that enforces concurrent request limits.

- **Log rotation**: All AI service logs must be subject to rotation with maximum size caps.

```nix
{
  services.logrotate = {
    enable = true;
    settings = {
      "/var/log/ai-audit/*.log" = {
        frequency = "daily";
        rotate = 90;
        maxsize = "500M";
        compress = true;
        missingok = true;
        notifempty = true;
      };
    };
  };
}
```

#### Application-level mitigations

- The orchestrator must enforce per-user and per-session rate limits: maximum 30 inference requests per minute per user, maximum 100 tool invocations per session, maximum context window size of 128K tokens per request.
- Agent loop detection: if an agent repeats the same tool call with the same arguments more than 3 times in a session, the loop must be broken and the session flagged for review.
- Maximum session duration: agent sessions must have a configurable timeout (default: 30 minutes). Sessions exceeding this must be terminated with state saved for review.
- Request queue depth: the API layer must reject requests with HTTP 429 when the inference queue exceeds a configurable depth (default: 20 pending requests).

#### Monitoring and detection

- Monitor and alert on: GPU memory utilization above 90%, system memory utilization above 85%, CPU utilization sustained above 90% for more than 5 minutes, disk utilization above 80%, inference request queue depth above 80% of maximum.
- Log all rate-limit rejections with client identity.
- Track requests per minute, tokens per minute, and tool invocations per minute as time-series metrics.
- Alert on agent loop detection events.

#### Implementation requirements

- `ai-services` module: cgroups limits for all services, log rotation, disk monitoring timer.
- `lan-only-network` module: Rate limiting at the network layer for inference API ports.
- Application config: Per-user rate limits, session timeouts, queue depth limits, loop detection.

---

## Part 2: OWASP Agentic AI Threats

---

### AGT-01: Unexpected Tool Invocation

#### Threat description

An agent invokes a tool that was not intended for the current task context, either through prompt injection, hallucination, or flawed reasoning. The agent might call a file-deletion tool when asked to summarize a document, or invoke a network tool when operating in a context that should be read-only. The tool invocation is syntactically valid but semantically inappropriate.

#### Infrastructure-level controls

- **Per-task tool allowlists enforced at the systemd level**: Different agent profiles should have different sets of tools available. A research agent's systemd unit should not have write access to production paths, regardless of what the orchestrator permits.

```nix
{
  # Research agent: read-only tools only at the OS level
  systemd.services.agent-research = {
    serviceConfig = {
      User = "agent-research";
      ReadOnlyPaths = [ "/var/lib/agents/research" "/var/lib/rag-data" ];
      ReadWritePaths = [ ];  # No write access at all
      ProtectSystem = "strict";
      IPAddressAllow = [ "127.0.0.1/32" ];
      IPAddressDeny = "any";
    };
  };
}
```

- **Binary availability restriction**: Remove unnecessary binaries from the agent's filesystem namespace. If an agent should not execute shell commands, do not bind-mount a shell into its namespace.

#### Runtime controls

- The orchestrator must validate every tool call against the session's declared tool allowlist before execution.
- Tool calls must include a mandatory `reason` field populated by the model. The reason is logged and can be used for post-hoc review.
- Implement a "tool surprise" detector: if the model invokes a tool that has not been mentioned in the conversation context and was not part of the original task specification, flag and optionally block the invocation.

#### Detection and alerting

- Alert on any tool invocation that is rejected by the allowlist.
- Log tool invocation sequences per session. Flag sessions where the tool sequence deviates significantly from established patterns for that agent profile.
- Weekly report on tool invocation distributions per agent type to detect drift.

---

### AGT-02: Privilege Escalation via Tool Chaining

#### Threat description

An agent chains multiple individually-permitted tool calls to achieve an outcome that no single call would permit. Examples: reading a credentials file, then using those credentials in an API call; writing a script to a permitted path, then executing it; using a search tool to find sensitive files, then a read tool to access them. Each individual action may be within policy, but the sequence constitutes an escalation.

#### Infrastructure-level controls

- **Taint tracking at the filesystem level**: Files written by agents must be tagged (via extended attributes or a metadata sidecar) so that subsequent tool calls can detect when they are operating on agent-generated content.

```nix
{
  # Ensure agent workspaces support extended attributes
  fileSystems."/var/lib/agents" = {
    options = [ "user_xattr" ];
  };

  # Agent-written files cannot be executed
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    NoExecPaths = [ "/var/lib/agents" ];
    ExecPaths = [ "/nix/store" ];
  };
}
```

- **No execute permission on agent workspace**: Files written by agents must never be executable. The `NoExecPaths` systemd directive must cover all agent workspace directories.

- **Cross-agent isolation**: Agents must not be able to read each other's workspaces or outputs without going through a supervised handoff mechanism.

#### Runtime controls

- Implement chain-aware authorization: the orchestrator must track the full sequence of tool calls in a session and evaluate privilege implications of the chain, not just individual calls.
- Define forbidden tool sequences (e.g., read-credentials then make-api-call, write-file then execute-file) and block them regardless of individual tool permissions.
- Credential access must never return raw credential values to the model context. Credentials must be injected into tool implementations as opaque references that the tool resolves internally.

#### Detection and alerting

- Log complete tool chains per session with timestamps.
- Alert on: any tool chain that matches a forbidden sequence pattern, any attempt to execute agent-written files, cross-agent data access attempts.
- Implement a chain-length alert: chains exceeding the configured maximum depth are logged and blocked.

---

### AGT-03: Excessive Autonomy

#### Threat description

An agent takes a long sequence of consequential actions without human oversight, accumulating risk with each step. A coding agent might refactor an entire codebase, an ops agent might modify multiple system configurations, or a research agent might make dozens of API calls to external services. The operator intended a single discrete action but the agent interpreted broad autonomy.

#### Infrastructure-level controls

- **Session resource budgets**: Each agent session gets a finite resource budget enforced at the cgroup level. When the budget is exhausted, the agent is paused.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    RuntimeMaxSec = 1800;      # 30-minute hard session limit
    WatchdogSec = 300;         # Must send heartbeat every 5 minutes
    TimeoutStopSec = 30;       # Force-kill after 30s if stop fails
  };
}
```

- **Write operation counting via auditd**: Track the number of write syscalls from agent processes and alert at thresholds.

#### Runtime controls

- Mandatory pause-and-confirm after every N tool invocations (configurable per agent profile, default: 5 for write-capable agents, 15 for read-only agents).
- The orchestrator must present a session summary at each pause point showing: actions taken, files modified, data accessed, and remaining approved actions.
- Auto-termination if no human confirmation is received within a configurable timeout (default: 10 minutes).
- Agents must not self-approve their own continuation. The approval signal must come from an authenticated human operator through a separate API path.

#### Detection and alerting

- Alert on: sessions reaching 80% of their resource budget, watchdog timeout failures, sessions that are auto-terminated for lack of human confirmation.
- Log all pause-and-confirm interactions with: timestamp, session state summary, operator identity, and decision (approve/deny/terminate).
- Track mean and p95 session durations per agent type. Alert on statistical anomalies.

---

### AGT-04: Identity Spoofing Between Agents

#### Threat description

In a multi-agent system, one agent impersonates another to gain access to tools, data, or privileges that it is not authorized to use. This can occur through: forged agent identity tokens, shared communication channels without authentication, or prompt injection causing one agent to claim it is another.

#### Infrastructure-level controls

- **UID-based identity**: Each agent type runs under a distinct UID. The kernel enforces access control based on UID, not on any application-level identity claim.

```nix
{
  users.users = {
    agent-coding = { isSystemUser = true; group = "agents"; uid = 990; };
    agent-ops = { isSystemUser = true; group = "agents"; uid = 991; };
    agent-research = { isSystemUser = true; group = "agents"; uid = 992; };
  };

  users.groups.agents = { gid = 990; };
}
```

- **Separate Unix sockets per agent for IPC**: If agents communicate with a shared service (e.g., the orchestrator), each must use a dedicated socket with file permissions restricting access to its UID.

```nix
{
  systemd.services.orchestrator = {
    serviceConfig = {
      # Create per-agent communication sockets
      ExecStartPre = [
        "${pkgs.coreutils}/bin/install -d -m 0750 -o orchestrator -g agents /run/orchestrator"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /run/orchestrator/sockets 0750 orchestrator agents - -"
  ];
}
```

- **No shared secrets between agents**: Each agent UID must have its own service account credentials. Shared group membership must not grant access to other agents' secrets.

#### Runtime controls

- All inter-agent messages must include a cryptographic identity token that is validated by the orchestrator. The token must be bound to the agent's UID and session ID.
- The orchestrator must verify the source UID of incoming connections (via `SO_PEERCRED` on Unix sockets) and reject messages where the claimed identity does not match the socket-level identity.
- Agents must not be able to invoke tools assigned to other agent profiles, even if they know the tool's name.

#### Detection and alerting

- Alert on: identity token validation failures, socket-level UID mismatches, tool invocation attempts for tools outside the agent's profile.
- Log all inter-agent communication with source and destination agent identities.

---

### AGT-05: Memory Poisoning

#### Threat description

An attacker manipulates the agent's persistent or session memory (conversation history, scratchpad, accumulated context) to influence future decisions. This could occur through: injecting adversarial content into conversation history, poisoning a shared memory store that multiple sessions read from, or exploiting context carryover between sessions to plant instructions that activate later.

#### Infrastructure-level controls

- **Session isolation at the filesystem level**: Each agent session must have its own workspace directory. Session state must not persist across sessions unless explicitly promoted through a reviewed process.

```nix
{
  # Per-session ephemeral directories
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    PrivateTmp = true;
    # Session workspace is created per-invocation and cleaned up
    RuntimeDirectory = "agent-session";
    RuntimeDirectoryPreserve = "no";
  };
}
```

- **Persistent memory store isolation**: If agents maintain persistent memory across sessions (e.g., a knowledge base or preference store), this store must be writable only through an authenticated API, not directly by the agent process.

- **Integrity monitoring on memory stores**: AIDE must cover agent memory/state directories.

#### Runtime controls

- Implement memory integrity validation: before loading session context or persistent memory into the model's context window, validate that the content has not been tampered with (checksums, signatures).
- Persistent memory writes must be logged and subject to content filtering (same output filters as LLM02 and LLM05).
- Implement memory expiration: persistent memories older than a configurable period (default: 30 days) must be reviewed before being included in context.
- Cross-session memory sharing must require explicit human approval.

#### Detection and alerting

- Alert on: integrity check failures for memory stores, memory writes that trigger content filter rules, anomalous memory growth (more than 2x baseline in 24 hours).
- Log all memory read/write operations with session ID, content hash, and size.

---

### AGT-06: Cascading Hallucination Failures

#### Threat description

In multi-step or multi-agent workflows, a hallucinated output from one step becomes accepted input for subsequent steps, causing errors to compound. Agent A hallucinates a file path, Agent B tries to read it and fails, Agent B hallucinates a workaround, and the cascade continues. Each step increases the divergence from reality and the potential for harmful actions.

#### Infrastructure-level controls

- **Independent failure domains**: Each agent step must have its own systemd unit or at minimum its own workspace, so that failures in one step do not corrupt the state of another.

```nix
{
  # Pipeline stages run as separate services
  systemd.services.pipeline-stage-1 = {
    serviceConfig = {
      User = "agent-stage1";
      ReadWritePaths = [ "/var/lib/pipeline/stage1" ];
      InaccessiblePaths = [ "/var/lib/pipeline/stage2" "/var/lib/pipeline/stage3" ];
    };
  };

  systemd.services.pipeline-stage-2 = {
    serviceConfig = {
      User = "agent-stage2";
      ReadOnlyPaths = [ "/var/lib/pipeline/stage1/output" ];
      ReadWritePaths = [ "/var/lib/pipeline/stage2" ];
      InaccessiblePaths = [ "/var/lib/pipeline/stage3" ];
    };
  };
}
```

- **Read-only handoff**: Output from one pipeline stage must be passed to the next as read-only. The receiving stage cannot modify the previous stage's output.

#### Runtime controls

- Each pipeline stage must validate its inputs before proceeding. If inputs fail validation, the stage must halt and report the failure rather than attempting to recover autonomously.
- Implement "ground truth checkpoints": at configurable intervals in multi-step chains, the orchestrator must verify key facts against authoritative sources (filesystem state, database contents, API responses) rather than relying on the model's context.
- Error propagation policy: when a tool invocation fails, the orchestrator must not allow the model to retry more than 2 times with different arguments. After 2 failures, the step must escalate to human review.
- Multi-agent pipelines must include a "validator agent" or validation step that independently verifies the output of each stage before passing it to the next. However: defense-in-depth through validator agents reduces but does not eliminate hallucination risk. The validator is itself an LLM and can itself hallucinate. Hard verification (checksums, schema validation, deterministic checks against filesystem or database state) should be preferred over LLM-based validation wherever possible. LLM-based validation is a fallback for cases where deterministic verification is not feasible.

#### Detection and alerting

- Track error rates per pipeline stage. Alert when any stage exceeds a 30% error rate over 10 invocations.
- Log the full data flow across pipeline stages with content hashes at each handoff point.
- Alert on retry cascades: more than 3 consecutive retries across a pipeline.

---

### AGT-07: Uncontrolled Resource Access

#### Threat description

An agent accesses resources (files, databases, APIs, hardware) that are beyond the scope of its current task, either through overly broad permissions, permission inheritance, or exploitation of shared infrastructure. This differs from excessive agency (AGT-03) in that it focuses on access to resources rather than autonomy of action.

#### Infrastructure-level controls

- **Principle of least privilege via systemd**:

```nix
{
  systemd.services.agent-runner = {
    serviceConfig = {
      # Canonical systemd hardening values per prd.md Appendix A.3
      # Filesystem
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;

      # Restrict device access (no GPU direct access for agents)
      PrivateDevices = true;
      DeviceAllow = [ ];

      # Network
      IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
      IPAddressDeny = "any";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];

      # System calls
      SystemCallFilter = [ "@system-service" "~@privileged" "~@mount" "~@raw-io" "~@reboot" "~@swap" "~@clock" ];
      SystemCallArchitectures = "native";

      # Capabilities
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      NoNewPrivileges = true;

      # Paths
      ReadWritePaths = [ "/var/lib/agent-runner/workspace" ];
      ReadOnlyPaths = [ "/var/lib/rag-data" ];
      InaccessiblePaths = [
        "/var/lib/ollama"
        "/var/lib/vector-db"
        "/run/secrets"
        "/etc/secrets"
      ];
    };
  };
}
```

- **GPU access restriction**: Only the inference service (Ollama) should have access to GPU devices. Agent processes must use `PrivateDevices=true` with no `DeviceAllow` entries for GPU.

- **Separate filesystem views**: Use `TemporaryFileSystem` and `BindPaths` to present each agent with a minimal filesystem view containing only what it needs.

#### Runtime controls

- Resource access logging: every file read, API call, and database query made by a tool must be logged with the resource identifier and the tool that accessed it.
- Resource access policies per agent profile: configurable lists of allowed file path prefixes, API endpoint prefixes, and database tables.
- Deny-by-default: any resource access not explicitly permitted must be denied and logged.

#### Detection and alerting

- Alert on: resource access denials (both OS-level and application-level), access to resources outside the agent's declared scope, new resource access patterns not seen in the agent profile's baseline.
- Monitor file descriptor counts per agent process. Alert if an agent opens more than 100 file descriptors.

---

### AGT-08: Insufficient Guardrails on Multi-Step Actions

#### Threat description

A multi-step workflow lacks adequate checkpoints, rollback capabilities, or approval gates, allowing an agent to make a series of changes that are difficult or impossible to reverse. This is distinct from excessive autonomy (AGT-03) in that the focus is on the reversibility and safety of the actions, not their quantity.

#### Infrastructure-level controls

- **Filesystem snapshots before destructive operations**:

```nix
{
  # Create workspace snapshots using btrfs or a simple copy
  # before multi-step operations
  systemd.services.workspace-snapshot = {
    description = "Snapshot agent workspace before operation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "snapshot-workspace" ''
        timestamp=$(date +%Y%m%d%H%M%S)
        src="/var/lib/agent-runner/workspace"
        dst="/var/lib/agent-runner/snapshots/$timestamp"
        mkdir -p "$dst"
        cp -a "$src/." "$dst/"
        # Keep only last 10 snapshots
        ls -dt /var/lib/agent-runner/snapshots/*/ | tail -n +11 | xargs rm -rf
      '';
      User = "agent";
    };
  };
}
```

- **NixOS generation rollback**: For any agent that modifies system configuration (which should be extremely restricted), NixOS generation rollback provides a recovery path.

- **Journaling and write-ahead logging**: Agent workspaces should log all file mutations to a journal before applying them, enabling replay and rollback.

#### Runtime controls

- Define "transaction boundaries" for multi-step operations. The orchestrator must create a checkpoint at the start of each transaction and provide a rollback mechanism.
- Classify actions by reversibility: fully reversible (file writes with backup), partially reversible (API calls with undo endpoints), irreversible (external notifications, data deletion). Irreversible actions must always require human approval.
- Progressive approval escalation: the first N steps of a multi-step operation may proceed with blanket approval; subsequent steps require re-approval with a summary of actions taken so far.
- Implement dry-run capability: for destructive multi-step operations, the orchestrator should first run the full sequence in dry-run mode, present the plan to the operator, and execute only after approval.

#### Detection and alerting

- Alert on: multi-step operations that exceed the pre-approved step count, rollback events (indicating something went wrong), checkpoint creation failures.
- Log all checkpoint and rollback operations with full state hashes.

---

### AGT-09: Goal/Instruction Hijacking

#### Threat description

An attacker manipulates the agent's goals or instructions mid-execution, causing it to pursue objectives different from those intended by the operator. Vectors include: prompt injection that overrides the agent's current goal, manipulated tool outputs that cause the agent to change course, adversarial content in retrieved documents that redirects the agent's plan, and exploitation of the agent's planning capabilities to insert attacker-controlled sub-goals.

This is the agentic-specific amplification of LLM01 (Prompt Injection). While LLM01 addresses the injection vector, this threat addresses the goal-level consequences unique to agents.

#### Infrastructure-level controls

- **Immutable goal specification**: The agent's goal/task specification must be stored in a read-only location and re-validated at each step. The agent process must not be able to modify its own goal.

```nix
{
  systemd.tmpfiles.rules = [
    # Goal specs are written by the orchestrator, read-only to agents
    "d /run/agent-goals 0550 orchestrator agents - -"
  ];

  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    BindReadOnlyPaths = [ "/run/agent-goals" ];
  };
}
```

- **Audit trail for goal changes**: Any modification to an agent's task specification must be logged with the identity of the modifier and the before/after state.

- **Network isolation preventing external goal injection**: Agents cannot receive instructions from external sources because they have no network access beyond loopback.

```nix
{
  systemd.services.agent-runner.serviceConfig = {
    # Canonical systemd hardening values per prd.md Appendix A.3
    IPAddressAllow = [ "127.0.0.1/32" "::1/128" ];
    IPAddressDeny = "any";
    # Agent can only talk to the local inference service
    # Cannot receive instructions from external sources
  };
}
```

#### Runtime controls

- Goal anchoring: at each step, the orchestrator must re-inject the original goal specification into the model's context. The model's proposed next action must be evaluated for alignment with the original goal.
- Implement a goal-drift detector: compare the semantic similarity of the agent's current plan/action with the original goal. If similarity drops below a configurable threshold (default: 0.6), pause and escalate.
- Tool outputs must be treated as untrusted data (same principle as indirect prompt injection). The orchestrator must sanitize tool outputs before including them in the model's context.
- External content (web pages, documents, API responses) must be clearly delineated in the context window with explicit markers indicating it is external and untrusted.

#### Detection and alerting

- Alert on: goal-drift detection triggers, plan changes that were not initiated by the operator, agent actions that cannot be traced to the original goal specification.
- Log the agent's plan state at each step with a goal-alignment score.
- Alert on rapid plan changes (more than 3 goal reformulations in a single session).

---

## Part 3: Combined Control Matrix

### Infrastructure Controls Mapping

| Control | NixOS Module | Assurance Level | LLM Risks Addressed | Agentic Threats Addressed |
|---|---|---|---|---|
| **UID-per-service isolation** | `agent-sandbox` | Enforced | LLM01, LLM02, LLM05, LLM06 | AGT-01, AGT-04, AGT-07 |
| **systemd ProtectSystem=strict** | `agent-sandbox` | Enforced | LLM02, LLM05, LLM09 | AGT-07, AGT-08 |
| **ReadWritePaths workspace restriction** | `agent-sandbox` | Enforced | LLM02, LLM05, LLM06 | AGT-01, AGT-02, AGT-07 |
| **NoNewPrivileges + CapabilityBoundingSet=""** | `agent-sandbox` | Enforced | LLM06 | AGT-02, AGT-03, AGT-07 |
| **IPAddressDeny=any + loopback allowlist** | `agent-sandbox`, `lan-only-network` | Enforced | LLM01, LLM10 | AGT-07, AGT-09 |
| **SystemCallFilter** | `agent-sandbox` | Enforced | LLM05, LLM06 | AGT-01, AGT-02 |
| **NoExecPaths on agent workspaces** | `agent-sandbox` | Enforced | LLM05 | AGT-02 |
| **PrivateDevices=true for agents** | `agent-sandbox` | Enforced | LLM10 | AGT-07 |
| **MemoryMax / CPUQuota / TasksMax cgroups** | `ai-services` | Enforced | LLM10 | AGT-03 |
| **RuntimeMaxSec session timeout** | `ai-services` | Enforced | LLM10 | AGT-03 |
| **LimitFSIZE / LimitNPROC resource limits** | `agent-sandbox` | Enforced | LLM05, LLM10 | AGT-03, AGT-07 |
| **AIDE integrity monitoring on models** | `audit-and-aide` | Enforced | LLM03, LLM04 | AGT-05 |
| **AIDE integrity monitoring on RAG data** | `audit-and-aide` | Enforced | LLM04, LLM08 | AGT-05, AGT-06 |
| **auditd rules for prompt/secret file access** | `audit-and-aide` | Enforced | LLM02, LLM07 | AGT-04 |
| **Separate UIDs per agent type** | `stig-baseline`, `agent-sandbox` | Enforced | LLM06 | AGT-04 |
| **InaccessiblePaths for cross-agent isolation** | `agent-sandbox` | Enforced | LLM02 | AGT-02, AGT-04 |
| **LAN-only firewall** (see qualifications below) | `lan-only-network` | Enforced | LLM03, LLM10 | AGT-09 |
| **Full-disk encryption** (see qualifications below) | `stig-baseline` | Enforced | LLM02 | AGT-05 |
| **Log rotation with size caps** | `audit-and-aide` | Enforced | LLM10 | AGT-03 |
| **Ephemeral session directories (RuntimeDirectory)** | `agent-sandbox` | Enforced | LLM02 | AGT-05 |
| **TemporaryFileSystem for minimal FS view** | `agent-sandbox` | Enforced | LLM02, LLM05 | AGT-07 |
| **Separate vector-db service/UID** | `ai-services` | Enforced | LLM08 | AGT-05 |
| **Disk monitoring timer** | `audit-and-aide` | Enforced | LLM10 | AGT-03, AGT-07 |
| **Workspace snapshot service** | `agent-sandbox` | Enforced | LLM09 | AGT-08 |

**Mapping qualifications:**
- LAN-only firewall and LLM01: The firewall reduces the attacker population to authorized LAN users but does not mitigate prompt injection from those users. LLM01 is addressed by application-layer controls, not network segmentation.
- Full-disk encryption and LLM08: FDE protects data at rest on disk but does not prevent embedding manipulation or vector store attacks while the system is running. LLM08 is addressed by vector-db access control and application-layer retrieval checks.

### Application-Level Controls Mapping

Controls are listed in dependency order where applicable. Controls marked with (dep: X) require control X to be implemented first.

| Control | Assurance Level | LLM Risks Addressed | Agentic Threats Addressed | Priority |
|---|---|---|---|---|
| **Tool allowlist per agent profile** | Requires Application Code | LLM01, LLM06 | AGT-01, AGT-02 | Critical |
| **Human approval gates for high-risk actions** | Requires Application Code | LLM06 | AGT-01, AGT-03, AGT-08 | Critical |
| **Action chain depth limits** | Requires Application Code | LLM06, LLM09 | AGT-03, AGT-06, AGT-08 | Critical |
| **Output content filtering (secrets, PII)** | Requires Application Code | LLM02, LLM07 | AGT-05 | Critical |
| **Tool argument validation schemas** | Requires Application Code | LLM05, LLM09 | AGT-01, AGT-06 | Critical |
| **Structured prompt formatting** | Requires Application Code | LLM01, LLM07 | AGT-09 | High |
| **Per-user/session rate limiting** | Requires Application Code | LLM10 | AGT-03 | High |
| **System prompt fragment detection** | Requires Application Code | LLM07 | AGT-09 | High |
| **Forbidden tool sequence enforcement** (dep: Tool allowlist) | Requires Application Code | LLM05 | AGT-02 | High |
| **Goal anchoring and drift detection** | Aspirational/Research-Grade | LLM01 | AGT-09 | High |
| **Agent loop detection** | Requires Application Code | LLM10 | AGT-03, AGT-06 | High |
| **Intermediate chain validation checkpoints** (dep: Action chain depth limits) | Requires Application Code | LLM09 | AGT-06, AGT-08 | High |
| **RAG access control** | Requires Application Code | LLM02, LLM04 | AGT-07 | High |
| **Authenticated document ingestion** | Requires Application Code | LLM04, LLM08 | AGT-05 | High |
| **Credential opaque references** | Requires Application Code | LLM02 | AGT-02 | High |
| **Transaction boundaries with rollback** | Requires Application Code | LLM09 | AGT-08 | High |
| **Tool invocation reason logging** (dep: Tool allowlist) | Requires Application Code | LLM06 | AGT-01, AGT-03 | Medium |
| **Retrieval diversity checks** | Requires Application Code | LLM08 | AGT-05 | Medium |
| **Similarity score anomaly detection** | Requires Application Code | LLM08 | AGT-05 | Medium |
| **Memory integrity validation** | Requires Application Code | LLM04 | AGT-05 | Medium |
| **Factual grounding via RAG with cited sources** | Requires Application Code | LLM09 | AGT-06 | Medium |
| **Dry-run mode for destructive operations** | Requires Application Code | LLM05, LLM09 | AGT-08 | Medium |
| **Session duration limits** | Requires Application Code | LLM10 | AGT-03 | Medium |
| **Error propagation policy (max 2 retries)** | Requires Application Code | LLM09 | AGT-06 | Medium |

### Rate Limiting and Resource Quota Requirements

| Resource | Limit | Enforcement Layer | Risks Addressed |
|---|---|---|---|
| Inference requests per user per minute | 30 | Application (API middleware) | LLM10 |
| Tool invocations per session | 100 | Application (orchestrator) | LLM06, LLM10, AGT-03 |
| Write-tool invocations per minute | 10 | Application (orchestrator) | LLM05, LLM06, AGT-01 |
| Destructive-tool invocations per minute | 2 (with approval) | Application (orchestrator) | LLM06, AGT-08 |
| Inference queue depth | 20 pending requests | Application (API middleware) | LLM10 |
| Max context window per request | 128K tokens | Application (orchestrator) | LLM10 |
| Ollama process memory | 24 GB (MemoryMax) | systemd cgroup | LLM10 |
| Agent process memory | 4 GB (MemoryMax) | systemd cgroup | LLM10, AGT-03 |
| Agent CPU | 200% (CPUQuota) | systemd cgroup | LLM10, AGT-03 |
| Agent max file size | 100 MB (LimitFSIZE) | systemd resource limit | LLM05, LLM10 |
| Agent max processes | 64 (LimitNPROC/TasksMax) | systemd resource limit | LLM05, LLM10 |
| Agent session duration | 30 minutes (RuntimeMaxSec) | systemd | LLM10, AGT-03 |
| Agent disk quota | Partition-level cap | Filesystem quota | LLM10, AGT-07 |
| Vector DB memory | 8 GB (MemoryMax) | systemd cgroup | LLM08, LLM10 |
| Bulk embedding insertions | 100 vectors per 5 min | Application (ingestion API) | LLM08, AGT-05 |
| Agent action chain depth | 10 steps (default) | Application (orchestrator) | LLM06, AGT-03, AGT-06 |
| Tool retry limit | 2 per tool per step | Application (orchestrator) | LLM09, AGT-06 |

### Egress Filtering Requirements

| Source UID | Permitted Destinations | Denied | Module |
|---|---|---|---|
| `ollama` | Model registry hosts (configured allowlist), loopback | All other | `lan-only-network` |
| `agent-*` | 127.0.0.1:11434 (Ollama), 127.0.0.1:8000 (API) | All other including LAN | `agent-sandbox` |
| `vectordb` | Loopback only | All | `ai-services` |
| `rag-ingest` | Loopback, configured internal document sources | All other | `ai-services` |
| `orchestrator` | Loopback, LAN interface for client connections | All other | `lan-only-network` |

### Monitoring and Audit Requirements Summary

| Event Category | Log Destination | Retention | Alert Threshold |
|---|---|---|---|
| Tool invocations | `/var/log/ai-audit/tools.log` | 90 days | Allowlist violations: immediate |
| Prompt/completion pairs (redacted) | `/var/log/ai-audit/inference.log` | 90 days | System prompt leakage: immediate |
| Approval gate decisions | `/var/log/ai-audit/approvals.log` | 90 days | Bypass attempts: immediate |
| Resource consumption metrics | `/var/log/ai-audit/resources.log` | 30 days | >90% GPU/memory/disk: warning |
| AIDE integrity checks | `/var/log/aide/aide.log` | 90 days | Any integrity failure: immediate |
| Agent session lifecycle | `/var/log/ai-audit/sessions.log` | 90 days | Auto-terminated sessions: warning |
| RAG ingestion events | `/var/log/ai-audit/ingestion.log` | 90 days | Bulk ingestion anomalies: warning |
| Authentication events | `/var/log/ai-audit/auth.log` | 90 days | Identity mismatches: immediate |
| Chain depth and goal drift | `/var/log/ai-audit/chains.log` | 90 days | Drift threshold exceeded: warning |
| Rate limit rejections | `/var/log/ai-audit/ratelimit.log` | 30 days | >10 rejections/min/user: warning |

### Detection Gap Analysis

Infrastructure monitoring detects policy violations. It does NOT detect semantic attacks.

**Detectable by infrastructure monitoring:**
- Tool allowlist violations (blocked and logged by the orchestrator and systemd)
- Resource exhaustion (cgroups limits, disk quotas, rate limit rejections)
- Access control failures (UID-based filesystem denials, network policy breaches)
- Network policy breaches (IPAddressDeny violations, egress filtering blocks)
- File integrity changes (AIDE alerts on model or RAG data modification)

**NOT detectable by infrastructure monitoring:**
- Goal hijacking within policy-allowed tool boundaries (an agent pursuing attacker goals using only its permitted tools)
- Subtle data exfiltration through legitimate tool arguments (embedding sensitive data in allowed API call parameters or file contents)
- Hallucination-driven errors that stay within resource bounds (a hallucinated but syntactically valid tool argument that causes incorrect but not policy-violating behavior)
- Prompt injection that stays within allowed tools (the model follows injected instructions but only invokes tools on its allowlist)
- Semantic attacks on output quality (degrading the usefulness or accuracy of responses without triggering any policy violation)

Infrastructure controls limit the blast radius of attacks. Detecting semantic attacks within policy boundaries requires application-layer behavioral analysis, which remains an active research area without proven general-purpose solutions.

### Log Volume Sizing Estimate

Full prompt/completion logging with 90-day retention requires storage planning. Estimate for a single GPU inference server:

- If average prompt + completion size is 2 KB and the server handles 1,000 requests/day, request logs alone consume approximately 180 MB over 90 days.
- With larger context windows (e.g., 32K-128K tokens), individual request logs can be 50-200 KB each. At 1,000 requests/day with an average of 50 KB per logged request, 90-day retention requires approximately 4.5 GB for inference logs alone.
- Tool invocation logs, session lifecycle logs, and AIDE reports add overhead proportional to agent activity.
- Actual volume depends heavily on context window sizes, request rates, and the verbosity of tool output logging.

Recommendation: set a log storage budget based on the partition or volume hosting `/var/log/ai-audit/`. Configure alerting at 80% capacity (the disk monitoring timer already provides this for agent data partitions; extend it to cover log storage). The logrotate configuration (500 MB maxsize per log file, 90-day retention, compression enabled) provides a baseline cap, but total volume across all log categories should be monitored as a single budget.

---

## Acceptance Criteria for This Module

- Every OWASP Top 10 for LLM Applications (2025) risk has at least one infrastructure-level and one application-level mitigation defined.
- Every OWASP Agentic AI threat has at least one infrastructure control, one runtime control, and one detection requirement defined.
- The combined control matrix maps every risk to specific NixOS modules.
- All NixOS configuration examples are syntactically valid and reference real systemd and NixOS options.
- Rate limits, resource quotas, and egress filtering rules are specified with concrete numeric values.
- Monitoring requirements specify log destinations, retention periods, and alert thresholds.
- All controls are compatible with the parent PRD's LAN-only, flake-based, GPU-inference architecture.

## Residual Risk and Known Limitations

This section exists to prevent false confidence. The controls documented above are necessary but not sufficient. Readers must understand what this document does and does not guarantee.

1. **Prompt injection remains an unsolved problem.** Even with all listed controls, a sufficiently sophisticated prompt injection can cause the model to produce attacker-desired outputs. Infrastructure controls limit blast radius, not prevent injection. The sandboxing, allowlisting, and approval gates in this document reduce the consequences of a successful injection but cannot prevent the injection itself from occurring at the model layer.

2. **Most controls require custom application code that does not yet exist.** Approximately 60% of the controls listed in this document require custom application code that does not yet exist. The NixOS flake enforces infrastructure-level controls only. The Assurance Level column in the control matrices distinguishes what is enforced by NixOS/systemd configuration (high assurance, verifiable by inspecting the flake) from what depends on application implementation quality (medium assurance) or is aspirational with no proven implementation (low assurance). Until the application layer is built and audited, the effective security posture is limited to infrastructure controls.

3. **Goal hijacking within policy is invisible to infrastructure.** Goal hijacking within policy-allowed tool boundaries is invisible to infrastructure monitoring. Detecting semantic attacks requires application-layer behavioral analysis, which is an unsolved research problem. An agent that pursues attacker-specified goals using only its permitted tools, within its resource budget, and without triggering any allowlist violation will not generate any infrastructure-level alert.

4. **cgroups cannot enforce GPU VRAM limits.** A model that exceeds VRAM will crash or degrade without OS-level intervention. The `MemoryMax` systemd directive controls system RAM via cgroups only. GPU VRAM exhaustion must be addressed through model size restrictions and application-layer concurrency controls, with `nvidia-smi` monitoring as a detection mechanism, not a prevention mechanism.

5. **Model provenance is trust-on-first-download.** Model provenance for Ollama library models is trust-on-first-download. Ollama does not support cryptographic provenance attestation. The model inventory with expected hashes described in this document verifies that a model has not changed since it was first downloaded, but does not verify the integrity of the original download against a chain of trust back to the model trainer. A compromised model that was malicious at download time will pass all subsequent integrity checks.

## Open Questions

- Should RAG ingestion be permitted from network sources beyond the LAN, and if so, what additional egress controls are needed for the `rag-ingest` UID?
- What is the target GPU VRAM size? The Ollama `MemoryMax` of 24 GB assumes a system with at least 24 GB available for inference after OS overhead; this must be tuned to hardware.
- Should model fine-tuning be an in-scope capability? If so, additional controls are needed for training data validation and model versioning.
- What is the multi-agent communication topology? The current design assumes agents communicate only through the orchestrator. Direct agent-to-agent communication would require additional controls.
- What approval gate UI/API will operators use? The requirements assume an approval API exists but do not specify the frontend.
