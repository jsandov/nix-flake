# Model Supply Chain

Provenance verification, integrity checking, and the download-to-deploy pipeline.

## Provenance Limitation

Ollama has **no GPG signatures, SLSA provenance, or cryptographic attestation**. Verification is hash-comparison against a locally-maintained manifest. This is trust-on-first-download.

A compromised model that was malicious at download time passes all subsequent integrity checks.

## Model Manifest Required Fields

Every model in the registry must include:

| Field | Example |
|---|---|
| name | `llama3.1-8b` |
| provider | `meta` |
| version | `3.1` |
| hash (sha256) | `abc123...` |
| license | `llama3.1-community` |
| known_limitations | Array of documented limitations |
| risk_tier | `minimal` / `limited` / `high` |
| intended_use | Free text description |
| deployment_date | ISO 8601 |
| review_due | Max 6 months from deployment |

Registry stored as `/etc/ai/model-registry.json` in the flake — version-controlled in Git.

## Deployment Pipeline

```
Request → Fetch + Hash Verify → Validate → Register → Deploy → Monitor
```

1. **Request:** Only ai-admin can initiate. Documented approval for high-risk models.
2. **Fetch + Verify:** `ai-model-fetch` script checks hash against manifest. Failed = model removed + critical log.
3. **Validate:** `ai-model-validate` runs functional + adversarial test suites. Results archived.
4. **Register:** Model added to registry in flake. Git-tracked change.
5. **Deploy:** `nixos-rebuild switch`. Previous generation available for rollback.
6. **Monitor:** AIDE checks model integrity hourly. Health checks every 5 minutes.

## Ollama Storage Format

Models are **content-addressed blobs** in `/var/lib/ollama/models/blobs/sha256-<hex>`. NOT `.bin` files.

Manifests in `/var/lib/ollama/models/manifests/` list layer digests. The largest layer with `mediaType` containing "model" is the weights blob.

Scripts must navigate this format — `find -name "*.bin"` finds nothing.

## Dependency Verification

| Dependency | Verification |
|---|---|
| NVIDIA driver | Pinned via nixpkgs, version in flake.lock |
| CUDA toolkit | Hash-verified by Nix |
| Ollama | Pinned via nixpkgs/overlay |
| Python/ML libs | Hash-verified by Nix |

## Model Retirement

1. Stop services using the model
2. `ollama rm <model-name>`
3. Update registry (mark retired) via flake + rebuild
4. Archive associated logs
5. Verify removal

## Key Takeaways

- Supply chain is the weakest link — no true cryptographic provenance
- Pinned flake inputs + AIDE monitoring are the best available mitigations
- Ollama blob format must be understood for integrity verification scripts
- Review model registry every 6 months — `review_due` field enforces this
- See [[ai-security/ai-security-residual-risks]] for provenance limitations
