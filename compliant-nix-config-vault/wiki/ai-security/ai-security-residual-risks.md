# AI Security — Residual Risks

What infrastructure controls **cannot** solve. This section exists to prevent false confidence.

## 1. Prompt Injection Remains Unsolved

Even with all controls, sophisticated prompt injection can cause attacker-desired outputs. Sandboxing, allowlisting, and approval gates reduce **consequences** but cannot prevent **injection** at the model layer.

## 2. ~60% of Controls Require Custom Application Code

The NixOS flake enforces infrastructure controls only. The application layer (port 8000 orchestrator, tool implementations, output filters, approval gates) does not exist yet. Until built and audited, effective security is limited to infrastructure controls.

## 3. Goal Hijacking Within Policy is Invisible

An agent pursuing attacker-specified goals using only its permitted tools, within resource budget, without triggering allowlist violations, will generate **no infrastructure-level alert**. Detecting semantic attacks requires application-layer behavioral analysis — an unsolved research problem.

## 4. cgroups Cannot Enforce GPU VRAM Limits

`MemoryMax` controls system RAM via cgroups. GPU VRAM is outside cgroup control. A model exceeding VRAM will crash or fall back to CPU inference (10-100x slower) without OS intervention.

**Compensating controls:**
- Restrict allowed model sizes in registry
- Limit concurrent inference requests
- Monitor GPU memory via `nvidia-smi` with alerting at 80%/95%
- Document VRAM capacity and per-model consumption

## 5. Model Provenance is Trust-on-First-Download

Ollama has no GPG signatures, SLSA provenance, or cryptographic attestation back to the model author. The model inventory records hashes after first download — a compromised model that was malicious at download time passes all subsequent checks.

## 6. CUDA Breaks MemoryDenyWriteExecute

CUDA's JIT compiler (NVRTC) requires W+X memory for PTX compilation. Enabling `MemoryDenyWriteExecute=true` on any CUDA-facing service crashes GPU inference.

**Where to apply it:** agent-runner, API proxy, monitoring services, all non-GPU helpers
**Where NOT to apply:** Ollama, CUDA inference services, model loading utilities

**Compensating controls:** SystemCallFilter, RestrictAddressFamilies, ProtectSystem=strict, NoNewPrivileges=true

## 7. Live Memory ePHI Exposure

ePHI in RAM/VRAM during inference is unencrypted. LUKS provides no protection for running systems. See [[hipaa/live-memory-ephi-risk]] for full analysis.

## 8. LLM Confidence Scores are Unreliable

Local open-weight models via Ollama lack calibrated confidence scores. "Self-reported confidence" from an LLM is unreliable and must NOT be used as a gating mechanism. Heuristic confidence from argument validation rates is a better (though imperfect) proxy.

## Key Takeaways

- Infrastructure controls are necessary but **not sufficient**
- The honest assessment: infrastructure limits blast radius, not prevents attacks
- Goal hijacking within policy boundaries is the hardest unsolved problem
- GPU VRAM is a persistent blind spot across cgroups, AIDE, and memory encryption
- These risks must be formally documented and accepted, not ignored
