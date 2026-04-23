# Data Flows

How data moves through the system with security controls at each stage.

## Inference Request Flow

```
Client (LAN) ──[TLS/mTLS]──> Firewall (port allowlist)
  ──> Rate Limiter (per-client throttling)
  ──> Input Logger (prompt metadata, no secrets)
  ──> Inference Engine (Ollama)
  ──> Output Logger (response metadata)
  ──> Client
```

Controls per stage:
- **Network entry:** Firewall validates source, TLS terminates at Nginx
- **Rate limiting:** ≤30 req/min/client prevents abuse
- **Input logging:** Request metadata for audit without sensitive content in logs
- **Inference:** Service account with minimal privileges, GPU access scoped
- **Output logging:** Response metadata, potential data leakage flagging
- **Response:** Encrypted in transit back to client

## Agentic Workflow Flow

```
Agent Request ──> Approval Gate (high-risk check)
  ──> Tool Allowlist (permitted tools only)
  ──> Sandboxed Execution (systemd isolation)
  ──> Action Logger (tool, args, result)
  ──> Result ──> Agent
```

Controls per stage:
- **Approval gate:** Human-in-the-loop for shell exec, file deletion, credential access
- **Tool allowlist:** Only explicitly permitted tools callable
- **Sandbox:** ProtectSystem=strict, namespace isolation, seccomp, resource quotas
- **Action logging:** Every tool invocation logged for audit
- **Result delivery:** Output sanitized before return to agent context

## RAG Pipeline Flow

```
Document Ingestion ──> Access Control (per-collection permissions)
  ──> Embedding Model ──> Vector Store (encrypted at rest)
  ──> Query ──> Similarity Search
  ──> Context Assembly (relevance filtering, access control check)
  ──> Inference (prompt + retrieved context)
  ──> Output (with source citations)
```

Key points:
- Documents classified before embedding; access controls inherited from source
- Vector store AIDE-monitored, access restricted to inference service account
- Retrieved documents filtered by requestor's access level — see [[hipaa/ephi-data-flow]]
- Output citations enable auditability

## Audit and Evidence Flow

```
System Events ──> auditd + journald ──> Local Log Store
  ──> AIDE (integrity baseline comparison)
  ──> Drift Alerting (notify on unauthorized changes)
  ──> Evidence Generator (periodic compliance snapshots)
  ──> Incident Response Hooks (threshold-based triggers)
```

## Key Takeaways

- Every data path has controls at each stage — defense in depth
- Ollama is bound to localhost only; all LAN access goes through authenticated TLS proxy
- Agent actions are logged, sandboxed, and gated by human approval for high-risk operations
- RAG pipeline enforces access control at both ingestion and retrieval
- Audit flow generates automated evidence for compliance — see [[shared-controls/evidence-generation]]
