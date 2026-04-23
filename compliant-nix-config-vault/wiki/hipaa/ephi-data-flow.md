# ePHI Data Flow

Seven stages of ePHI movement through the AI system, each requiring specific controls.

## Stage 1: Prompt Ingestion
User submits prompt containing ePHI to Ollama (11434) or app API (8000).

**Controls:** TLS from client, authentication before acceptance, access logging (who/when/where), input validation for ePHI markers (app-layer).

## Stage 2: RAG Context Retrieval
Application retrieves stored documents that may contain ePHI.

**Controls:** Filesystem ACL on RAG stores (POSIX + systemd sandbox), LUKS encryption at rest, audit trail of document retrieval, minimum necessary filtering (app-layer).

## Stage 3: Model Inference
Prompt + context processed by Ollama. **ePHI exists unencrypted in RAM and VRAM.** See [[live-memory-ephi-risk]].

**Controls:** Memory isolation (dedicated user, ProtectSystem=strict), swap encryption, no telemetry, core dumps disabled. **MemoryDenyWriteExecute incompatible with CUDA** — see [[ai-security/ai-security-residual-risks]].

### Context Window Persistence Risk
Ollama may cache conversation state between requests. ePHI from Patient A may persist when Patient B's request arrives. Requires aggressive session timeouts and per-patient isolation at app layer.

## Stage 4: Agent Actions
Agents take actions based on inference output containing ePHI.

**Controls:** systemd sandboxing, tool allowlisting, write path restrictions (ReadWritePaths), human approval gates, output content scanning (app-layer).

## Stage 5: Output Delivery
Results returned to requesting user.

**Controls:** TLS on response, response logging (metadata not full ePHI), access control verification.

## Stage 6: Log Persistence
Logs may contain ePHI fragments (error messages with prompt text, request metadata).

**Controls:** Encrypted storage, restricted access (audit role only), retention/rotation policy, log integrity (append-only or remote forwarding), redaction strategy (app-layer).

## Stage 7: Inter-Process Communication
IPC channels carry ePHI between processes within the host.

**Channels:** Unix sockets (API↔Ollama), shared memory (CUDA host↔GPU), message queues, D-Bus.

**Controls:** Socket file permissions (0660 with group ACL), shared memory isolation (PrivateTmp, ProtectSystem), D-Bus policy restricting send/receive.

## Key Takeaways

- ePHI protection isn't just about encryption at rest — every stage needs controls
- Stage 3 (inference) has the highest risk due to [[live-memory-ephi-risk]]
- App-layer controls are required at stages 1, 2, 4, 5, 6 — infrastructure alone is insufficient
- IPC (stage 7) is often overlooked because it doesn't traverse the network
- Nix store world-readability is a leakage vector — see [[nixos-platform/nixos-gotchas]]
