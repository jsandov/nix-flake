# Wiki Graph

Cross-topic connections in the knowledge base. For the full article list, see [[_master-index]].

This graph shows how the four most-referenced articles connect across topic boundaries. These are the nodes where knowledge converges — start here when looking for something.

```mermaid
flowchart TD
  subgraph architecture["architecture/"]
    flake-modules
    data-flows
    threat-model
  end

  subgraph compliance-frameworks["compliance-frameworks/"]
    canonical-config-values
    cross-framework-matrix
  end

  subgraph nixos-platform["nixos-platform/"]
    nixos-gotchas
  end

  subgraph hipaa["hipaa/"]
    live-memory-ephi-risk
    ephi-data-flow
  end

  subgraph ai-security["ai-security/"]
    residual-risks
    owasp-llm-top-10
    owasp-agentic-threats
    mitre-atlas
  end

  subgraph ai-governance["ai-governance/"]
    model-supply-chain
  end

  subgraph shared-controls["shared-controls/"]
    controls-overview
    evidence-generation
    secrets-management
  end

  subgraph review-findings["review-findings/"]
    master-review
    lessons-learned
  end

  %% canonical-config-values — single source of truth for resolved settings
  flake-modules --> canonical-config-values
  controls-overview --> canonical-config-values
  secrets-management --> canonical-config-values
  master-review --> canonical-config-values
  lessons-learned --> canonical-config-values

  %% residual-risks — what infrastructure cannot solve
  threat-model --> residual-risks
  owasp-llm-top-10 --> residual-risks
  model-supply-chain --> residual-risks
  canonical-config-values --> residual-risks
  master-review --> residual-risks

  %% nixos-gotchas — platform pitfalls that cut across topics
  secrets-management --> nixos-gotchas
  ephi-data-flow --> nixos-gotchas
  master-review --> nixos-gotchas
  nixos-gotchas --> residual-risks

  %% live-memory-ephi-risk — the #1 system risk
  threat-model --> live-memory-ephi-risk
  residual-risks --> live-memory-ephi-risk
  ephi-data-flow --> live-memory-ephi-risk

  %% AI security chain
  owasp-llm-top-10 <--> owasp-agentic-threats
  mitre-atlas --> model-supply-chain
  cross-framework-matrix --> owasp-llm-top-10
  flake-modules --> owasp-agentic-threats
  controls-overview --> owasp-agentic-threats

  %% Architecture → operations
  flake-modules --> evidence-generation
  data-flows --> evidence-generation
  flake-modules --> model-supply-chain
```

**Hub articles** are referenced from 5+ topics — they reflect the project's key tensions:

| Hub | Tension |
|---|---|
| canonical-config-values | Where do the resolved settings live? |
| residual-risks | What can infrastructure not solve? |
| nixos-gotchas | Where does NixOS differ from expectations? |
| live-memory-ephi-risk | What is the single biggest security gap? |
