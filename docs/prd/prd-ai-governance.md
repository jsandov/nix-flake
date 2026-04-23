# PRD Module: AI Governance and Security Frameworks

## Overview

This document extends the base PRD for the Control-Mapped NixOS AI Agentic Server with AI-specific governance, risk management, and security frameworks. It maps the system's technical controls — flake modules, systemd hardening, network restrictions, audit infrastructure — to the requirements of NIST AI RMF, the EU AI Act, ISO/IEC 42001, MITRE ATLAS, and model supply chain security practices.

This system runs local GPU inference (Ollama on port 11434), application APIs (port 8000), and sandboxed agentic workflows on a LAN-only NixOS host. The flake structure includes modules for `stig-baseline`, `gpu-node`, `lan-only-network`, `audit-and-aide`, `agent-sandbox`, and `ai-services`. All controls described below build on that foundation.

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the AI governance-specific rationale; the implementation flake uses only the canonical values.

The distinction between what the infrastructure can enforce technically and what requires organizational process is called out explicitly for each requirement.

---

## 1. NIST AI Risk Management Framework (AI 100-1)

### 1.1 GOVERN Function

The GOVERN function establishes the organizational context for AI risk management: policies, roles, accountability, and culture.

#### 1.1.1 AI Risk Management Policy

**Organizational process requirement.** A written AI risk management policy must define:

- Acceptable use cases for local inference and agentic workflows.
- Risk tolerance thresholds for agent autonomy levels.
- Escalation paths when agents encounter uncertainty or failure.
- Data handling rules for prompts, model outputs, and retrieved context.

**Technical enforcement in flake/runtime:**

```nix
# ai-services/governance.nix — enforce policy metadata at build time
{
  # Every AI service must declare its risk tier and approved use case
  # in its systemd unit description. Services without this metadata
  # fail the pre-deployment review checklist.
  systemd.services.ollama = {
    description = "Ollama inference server | risk-tier=moderate | use-case=internal-lan-inference | owner=ai-platform-team";
    # ...
  };

  systemd.services.agent-runner = {
    description = "Sandboxed agent executor | risk-tier=high | use-case=agentic-tool-execution | owner=ai-platform-team | requires-human-approval=true";
    # ...
  };
}
```

```nix
# audit-and-aide/governance-logging.nix — log governance-relevant events
{
  # NOTE: This journald config is illustrative. The canonical retention
  # value is in prd.md Appendix A.5 (365day for operational logs).
  # The implementation flake sets journald.extraConfig exactly once.
  # This block and the EU AI Act logging block (Section 2.3) must NOT
  # both appear in the implementation — they would cause an eval error.

  # Structured logging for all AI service lifecycle events
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=1year
    MaxFileSec=1month
    RateLimitBurst=10000
    RateLimitIntervalSec=30s
  '';
}
```

#### 1.1.2 Roles and Accountability

**Organizational process requirement.** Define at minimum:

| Role | Responsibility |
|---|---|
| AI System Owner | Accountable for risk decisions, model selection, use-case approval |
| AI Operator | Day-to-day operation, monitoring, incident response |
| Security Engineer | Control implementation, audit review, vulnerability response |
| Data Steward | Data classification for training data, prompts, outputs |

**Technical enforcement:** The NixOS configuration enforces role separation through distinct system accounts:

```nix
{
  users.users = {
    ai-admin = {
      isNormalUser = true;
      description = "AI system administrator — deploy and configure";
      extraGroups = [ "wheel" "ai-services" ];
    };
    ai-operator = {
      isNormalUser = true;
      description = "AI operator — monitor and respond";
      extraGroups = [ "ai-services" "systemd-journal" ];
      # No wheel group — cannot sudo to root
    };
    agent = {
      isSystemUser = true;
      description = "Sandboxed agent execution account — no interactive login";
      group = "agent";
      shell = "/run/current-system/sw/bin/nologin";
    };
    ollama = {
      isSystemUser = true;
      description = "Ollama inference service account";
      group = "ollama";
      shell = "/run/current-system/sw/bin/nologin";
    };
  };

  users.groups = {
    ai-services = {};
    agent = {};
    ollama = {};
  };
}
```

#### 1.1.3 Governance Culture and Training

**Organizational process requirement only.** The infrastructure cannot enforce this. Required:

- Annual AI risk awareness training for all personnel interacting with the system.
- Documented review of AI incident post-mortems.
- Periodic re-evaluation of risk tolerance as models and use cases change.

### 1.2 MAP Function

The MAP function identifies context, intended use, and risks specific to this AI system.

#### 1.2.1 Context Mapping

**Intended deployment context:**

| Attribute | Value |
|---|---|
| Deployment type | On-premises, single host, LAN-only |
| Inference mode | Local GPU inference via Ollama |
| Model types | Open-weight LLMs (Llama, Mistral, Qwen, etc.) |
| Agent capabilities | Tool use, file read/write within sandbox, API calls within LAN |
| Data sensitivity | Potentially sensitive (internal documents, code, configurations) |
| User population | Internal technical staff only |
| Network exposure | LAN-only; no public internet ingress |

#### 1.2.2 Intended Use Documentation

**Organizational process requirement.** Each deployed model and agent workflow must have a documented intended-use statement covering:

- Purpose and expected behavior.
- Known limitations of the model for this use case.
- Data types the model will process.
- Decision types the model will influence (advisory only, semi-autonomous, autonomous).
- Populations affected by model outputs.

**Technical enforcement:** The `ai-services` module should maintain a model registry file:

```nix
# ai-services/model-registry.nix
{
  environment.etc."ai/model-registry.json" = {
    mode = "0644";
    text = builtins.toJSON {
      models = [
        {
          name = "llama3.1-8b";
          provider = "meta";
          version = "3.1";
          hash = "sha256:abc123...";
          license = "llama3.1-community";
          intended_use = "Internal code assistance and document summarization";
          risk_tier = "moderate";
          known_limitations = [
            "May hallucinate code that compiles but contains logic errors"
            "Not validated for medical, legal, or financial advice"
            "Performance degrades on inputs exceeding 8192 tokens"
          ];
          data_classification = "internal-only";
          deployment_date = "2026-01-15";
          review_due = "2026-07-15";
        }
      ];
    };
  };
}
```

#### 1.2.3 Risk Identification

Risks specific to this system's MAP context:

| Risk | Likelihood | Impact | Current mitigation |
|---|---|---|---|
| Model hallucination leading to incorrect action | High | Moderate | Human approval gates for high-risk agent actions |
| Prompt injection via untrusted input data | Moderate | High | Input validation, sandboxed execution, no internet egress |
| Model weights containing backdoors | Low | Critical | Model provenance verification, hash checking (see Section 5) |
| Agent escaping sandbox boundaries | Low | Critical | systemd hardening, ProtectSystem=strict, seccomp filters |
| Sensitive data leaking through model outputs | Moderate | High | LAN-only network, output logging and review |
| Unauthorized model replacement | Low | Critical | Immutable Nix store, AIDE integrity monitoring |

### 1.3 MEASURE Function

The MEASURE function defines testing, evaluation, metrics, and ongoing monitoring.

#### 1.3.1 Pre-Deployment Testing

**Organizational process requirement with technical tooling support.**

Before any model is added to the model registry and deployed via Ollama:

1. **Functional testing**: Validate model outputs against a curated test suite for the intended use case.
2. **Safety testing**: Run adversarial prompt test cases (prompt injection, jailbreak attempts, data extraction attempts).
3. **Bias assessment**: For any use case involving people-related decisions, run bias evaluation benchmarks. Document results and accepted limitations.
4. **Performance baseline**: Record inference latency, throughput, and resource consumption for capacity planning.

**Technical enforcement:**

```nix
# ai-services/model-validation.nix
{
  # Pre-deployment validation script available on the system
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "ai-model-validate" ''
      set -euo pipefail
      MODEL="$1"
      RESULTS_DIR="/var/lib/ai-validation/$(date +%Y%m%d-%H%M%S)-$MODEL"
      mkdir -p "$RESULTS_DIR"

      echo "=== Running functional test suite ==="
      ${pkgs.curl}/bin/curl -s http://localhost:11434/api/generate \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$(cat /etc/ai/test-suites/functional.txt)\", \"stream\": false}" \
        > "$RESULTS_DIR/functional-results.json"

      echo "=== Running adversarial prompt tests ==="
      ${pkgs.curl}/bin/curl -s http://localhost:11434/api/generate \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$(cat /etc/ai/test-suites/adversarial.txt)\", \"stream\": false}" \
        > "$RESULTS_DIR/adversarial-results.json"

      echo "=== Recording performance baseline ==="
      for i in $(seq 1 10); do
        ${pkgs.curl}/bin/curl -s -w "%{time_total}\n" -o /dev/null \
          http://localhost:11434/api/generate \
          -d "{\"model\": \"$MODEL\", \"prompt\": \"Summarize: The quick brown fox.\", \"stream\": false}" \
          >> "$RESULTS_DIR/latency.txt"
      done

      echo "Results stored in $RESULTS_DIR"
      echo "MANUAL REVIEW REQUIRED: Check results before adding model to production registry."
    '')
  ];
}
```

#### 1.3.2 Ongoing Monitoring Metrics

**Technical enforcement in flake/runtime:**

| Metric | Collection method | Alert threshold |
|---|---|---|
| Inference latency (p50, p95, p99) | Prometheus scraping Ollama metrics | p95 > 30s |
| Error rate (HTTP 5xx from inference API) | journald log parsing | > 5% over 5-minute window |
| Agent task completion rate | Custom structured log events | < 80% over 1-hour window |
| Agent approval gate bypasses | Audit log analysis | Any occurrence |
| Model file integrity | AIDE hourly check | Any hash mismatch |
| GPU memory utilization | nvidia-smi metrics export | > 95% sustained for 10 minutes |
| Unexpected network connections from agent | systemd journal + firewall logs | Any connection outside allowlist |

```nix
# audit-and-aide/ai-monitoring.nix
{
  # AIDE monitoring for model artifacts
  environment.etc."aide/ai-models.conf" = {
    text = ''
      /var/lib/ollama/models p+i+n+u+g+s+md5+sha256
      /etc/ai/model-registry.json p+i+n+u+g+s+md5+sha256
    '';
  };

  # Systemd timer for AI-specific health checks
  systemd.services.ai-health-check = {
    description = "AI services health and anomaly check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ai-health-check" ''
        set -euo pipefail

        # Check Ollama is responding
        HTTP_CODE=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" http://localhost:11434/api/tags)
        if [ "$HTTP_CODE" != "200" ]; then
          echo "ALERT: Ollama not responding (HTTP $HTTP_CODE)" | systemd-cat -p err -t ai-health
        fi

        # Check agent sandbox integrity
        if systemctl is-active agent-runner > /dev/null 2>&1; then
          AGENT_PID=$(systemctl show agent-runner -p MainPID --value)
          if [ "$AGENT_PID" != "0" ]; then
            # Verify agent is still in its namespace
            MOUNT_NS=$(readlink /proc/$AGENT_PID/ns/mnt 2>/dev/null || echo "MISSING")
            echo "Agent PID=$AGENT_PID mount_ns=$MOUNT_NS" | systemd-cat -p info -t ai-health
          fi
        fi
      '';
    };
  };

  systemd.timers.ai-health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";  # Every 5 minutes
      Persistent = true;
    };
  };
}
```

#### 1.3.3 Bias Assessment

**Organizational process requirement.** For each model in the registry:

- Document known biases disclosed by the model provider.
- For use cases involving people-related decisions, run domain-specific bias benchmarks before deployment.
- Record bias assessment results in the model registry alongside the model metadata.
- Re-assess on model version changes or use-case scope expansion.

This system's primary use cases (code assistance, document summarization, internal tooling) have lower direct bias risk than people-facing decision systems, but the assessment must still be documented even if the conclusion is "low risk for current use cases."

### 1.4 MANAGE Function

The MANAGE function covers risk treatment, incident response, and continuous improvement.

#### 1.4.1 Risk Treatment

For each risk identified in the MAP function (Section 1.2.3), a treatment decision must be documented:

| Risk | Treatment | Implementation |
|---|---|---|
| Model hallucination | Mitigate | Human approval gates; advisory-only output framing |
| Prompt injection | Mitigate | Input sanitization; sandboxed execution; no egress |
| Backdoored weights | Mitigate + Accept residual | Hash verification; trusted sources only; accept residual risk for open weights |
| Sandbox escape | Mitigate | systemd hardening; seccomp; ProtectSystem=strict |
| Sensitive data leakage | Mitigate | LAN-only; output logging; data classification policy |
| Unauthorized model swap | Mitigate | AIDE monitoring; Nix store immutability |

#### 1.4.2 AI-Specific Incident Response

**Organizational process requirement with technical tooling.**

The following AI-specific incident types require defined response procedures:

**Incident Type 1: Model producing harmful or incorrect outputs**
- Severity: Based on downstream impact (advisory vs. actioned output).
- Immediate action: Operator stops the affected agent workflow via `systemctl stop agent-runner`.
- Investigation: Review journald logs for the session, examine prompts and outputs.
- Remediation: Update prompt templates, add test case to adversarial suite, consider model replacement.

**Incident Type 2: Agent exceeding authorized actions**
- Severity: Critical.
- Immediate action: `systemctl stop agent-runner && systemctl disable agent-runner`.
- Investigation: Review audit logs, check for sandbox escape indicators, examine tool invocation records.
- Remediation: Tighten sandbox policy, update tool allowlist, add monitoring rule.

**Incident Type 3: Model integrity compromise**
- Severity: Critical.
- Immediate action: Take Ollama offline: `systemctl stop ollama`.
- Investigation: Compare AIDE hashes, verify model provenance, check for unauthorized file modifications.
- Remediation: Re-download from verified source, update hash in model registry, rebuild from flake.

**Incident Type 4: Prompt injection / data exfiltration attempt**
- Severity: High.
- Immediate action: Isolate the affected agent session.
- Investigation: Review input data source, analyze the injection vector, check for successful exfiltration (outbound connection logs).
- Remediation: Update input validation, add the pattern to adversarial test suite, review network controls.

**Technical enforcement — emergency kill switch:**

```nix
# agent-sandbox/killswitch.nix
{
  # Emergency halt for all AI services
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "ai-emergency-stop" ''
      set -euo pipefail
      echo "$(date -Iseconds) EMERGENCY STOP initiated by $(whoami)" | systemd-cat -p crit -t ai-emergency

      systemctl stop agent-runner.service 2>/dev/null || true
      systemctl stop ollama.service 2>/dev/null || true
      systemctl stop ai-api.service 2>/dev/null || true

      systemctl disable agent-runner.service 2>/dev/null || true

      echo "All AI services stopped. agent-runner disabled."
      echo "To re-enable: systemctl enable --now agent-runner.service"
    '')
  ];

  # Only ai-admin and root can execute the kill switch
  security.sudo.extraRules = [
    {
      groups = [ "ai-services" ];
      commands = [
        { command = "/run/current-system/sw/bin/ai-emergency-stop"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.systemd}/bin/systemctl stop ollama.service"; options = [ "NOPASSWD" ]; }
        { command = "${pkgs.systemd}/bin/systemctl stop agent-runner.service"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];
}
```

#### 1.4.3 Continuous Improvement

**Organizational process requirement.**

- Quarterly review of model registry: are models still appropriate for their documented use cases?
- Quarterly review of agent sandbox escapes, approval gate overrides, and anomaly alerts.
- Annual review of the AI risk management policy against updated framework guidance.
- Post-incident review within 5 business days of any AI-specific incident.
- Track metrics trends: are error rates increasing? Are more approval gates being triggered?

---

## 2. EU AI Act

### 2.1 Risk Classification

Under the EU AI Act (Regulation 2024/1689), AI systems are classified into four risk tiers: unacceptable, high, limited, and minimal.

**Classification of this system:**

This system's classification depends on its use case, not its technical architecture:

| Use case | Likely classification | Rationale |
|---|---|---|
| Internal code assistance | Minimal risk | General-purpose tool, advisory only |
| Document summarization for internal use | Minimal risk | No consequential decisions |
| RAG over internal knowledge base | Limited risk (transparency) | Users should know they interact with AI |
| Agent workflows making operational decisions | Potentially high risk | If decisions affect safety, employment, or essential services |
| Processing health data or ePHI | High risk | Health domain triggers high-risk classification under Annex III |

**Requirement:** The system owner must classify each deployed use case and document the classification rationale in the model registry. If any use case is high-risk, all requirements in Sections 2.2 through 2.6 become mandatory.

### 2.2 Technical Documentation (Article 11)

For high-risk use cases, the following technical documentation must be maintained:

1. **General description**: System purpose, intended users, geographic scope (LAN-only, internal).
2. **Design specifications**: Architecture (NixOS flake, Ollama, agent sandbox), model selection rationale, hardware (GPU specifications).
3. **Development process**: How models are selected, validated, and deployed.
4. **Monitoring and testing**: Pre-deployment validation results, ongoing monitoring metrics (reference Section 1.3).
5. **Risk management**: Reference to the NIST AI RMF MAP and MANAGE outputs (Sections 1.2 and 1.4).
6. **Changes log**: Git history of the flake repository serves as the authoritative change record.

**Technical enforcement:**

```nix
# ai-services/documentation.nix
{
  # System description metadata baked into the build
  environment.etc."ai/system-description.json" = {
    mode = "0644";
    text = builtins.toJSON {
      system_name = "NixOS AI Agentic Server";
      version = "1.0";
      purpose = "Local GPU inference and sandboxed agentic workflows for internal use";
      deployment_type = "on-premises-lan-only";
      operator = "AI Platform Team";
      hardware = {
        gpu = "NVIDIA — see /etc/ai/hardware-manifest.json at deploy time";
        network = "LAN-only, no public internet ingress";
      };
      ai_act_classification = "determined-per-use-case — see model-registry.json";
      flake_commit = "populated-at-build-time";
    };
  };
}
```

### 2.3 Record-Keeping and Logging (Article 12)

The EU AI Act requires automatic logging that enables traceability of AI system operation.

**Important limitation:** Ollama's native logging produces unstructured service-level log lines (startup, model load, errors) but does not produce structured per-request records suitable for EU AI Act Article 12 traceability. The application layer on port 8000 MUST produce structured per-request inference records. Ollama journal logs alone are insufficient for compliance.

**Requirement: Request/response logging middleware.** The application API (port 8000) must implement middleware that captures and logs every inference request and response with the fields specified in the table below. This middleware sits between the user-facing API and Ollama's inference endpoint, ensuring that every request is logged regardless of Ollama's own logging behavior.

```nix
# ai-services/inference-logging-middleware.nix
{
  # The application API on port 8000 MUST include logging middleware.
  # This is an application-layer responsibility — Ollama does not produce
  # structured per-request logs suitable for Article 12 compliance.
  #
  # The middleware must log to a structured JSONL file or journald with
  # at minimum: timestamp, request_id, model, user/source, prompt_hash,
  # response_hash, latency_ms, token_count_input, token_count_output,
  # http_status. See "Required log fields" table below.
  #
  # Example middleware pattern (application must implement):
  #   1. Receive request on port 8000
  #   2. Log request metadata (timestamp, source, model, prompt hash)
  #   3. Forward to Ollama on port 11434
  #   4. Log response metadata (response hash, latency, token counts)
  #   5. Return response to caller
}
```

**Technical enforcement — infrastructure-level logging (necessary but not sufficient):**

```nix
# audit-and-aide/ai-act-logging.nix
{
  # Structured AI event logging
  # All AI service events go to persistent journal with full metadata
  systemd.services.ollama = {
    serviceConfig = {
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "ollama";
    };
  };

  systemd.services.agent-runner = {
    serviceConfig = {
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "agent-runner";
    };
  };

  # NOTE: This journald config is illustrative. 18-month retention applies
  # to AI decision logs specifically (prd.md Appendix A.5), not to the
  # systemd journal as a whole. In the implementation, AI decision logs
  # should be a separate structured log stream, not journal config.
  # This block conflicts with Section 1.1.1's journald config and must
  # NOT be duplicated in the implementation flake.

  # Log retention: EU AI Act requires logs for duration appropriate to
  # the intended purpose — minimum 6 months recommended for high-risk
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=18month
    Compress=yes
    SystemMaxUse=50G
  '';

  # Export AI logs to structured files for long-term archival
  systemd.services.ai-log-export = {
    description = "Export AI service logs to structured archive";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ai-log-export" ''
        EXPORT_DIR="/var/lib/ai-audit-logs/$(date +%Y-%m-%d)"
        mkdir -p "$EXPORT_DIR"

        # Export Ollama inference logs
        journalctl -u ollama --since "24 hours ago" --output=json \
          > "$EXPORT_DIR/ollama.json"

        # Export agent execution logs
        journalctl -u agent-runner --since "24 hours ago" --output=json \
          > "$EXPORT_DIR/agent-runner.json"

        # Export approval gate decisions
        journalctl -t agent-approval --since "24 hours ago" --output=json \
          > "$EXPORT_DIR/approval-decisions.json"

        # Export emergency stop events
        journalctl -t ai-emergency --since "24 hours ago" --output=json \
          > "$EXPORT_DIR/emergency-events.json"

        # Export application-layer inference logs (Article 12 structured records)
        if [ -f /var/lib/ai-api/inference-audit.jsonl ]; then
          cp /var/lib/ai-api/inference-audit.jsonl "$EXPORT_DIR/inference-audit.jsonl"
        fi

        chmod -R 0640 "$EXPORT_DIR"
        chown -R root:ai-services "$EXPORT_DIR"
      '';
    };
  };

  systemd.timers.ai-log-export = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
```

**Required log fields for traceability:**

| Event type | Required fields |
|---|---|
| Inference request | Timestamp, request_id, model, user/source, prompt hash (not content if sensitive), response hash, latency, token count input, token count output, http_status |
| Agent action | Timestamp, agent ID, action type, tool invoked, target resource, approval status, outcome |
| Approval gate | Timestamp, agent ID, action requested, approver identity, decision (approve/deny), rationale |
| Model lifecycle | Timestamp, model name, action (load/unload/update), actor, previous hash, new hash |
| System event | Timestamp, service, event type (start/stop/crash/restart), actor if manual |

**Note:** Inference request logging MUST be implemented at the application layer (port 8000 middleware), not at the Ollama layer. Ollama does not emit structured per-request records. The other event types (agent action, approval gate, model lifecycle, system event) are captured by journald.

### 2.4 Human Oversight Mechanisms (Article 14)

The EU AI Act requires that high-risk AI systems be designed to allow effective human oversight, including the ability to interrupt, override, and halt.

**Technical enforcement:**

```nix
# agent-sandbox/human-oversight.nix
let
  # Package the approval gate as a Nix derivation — all executables
  # must live in the Nix store for reproducibility, not in /opt.
  approval-gate-pkg = pkgs.python3Packages.buildPythonApplication {
    pname = "approval-gate-server";
    version = "1.0.0";
    src = ./approval-gate;  # Source in the flake's source tree
    propagatedBuildInputs = with pkgs.python3Packages; [
      flask
      gunicorn
    ];
    meta.description = "Human approval gate for agent high-risk actions";
  };

  # Alternative for simpler cases: inline the script via writeScriptBin
  # approval-gate-pkg = pkgs.writers.writePython3Bin "approval-gate-server"
  #   { libraries = with pkgs.python3Packages; [ flask gunicorn ]; }
  #   (builtins.readFile ./approval-gate/server.py);
in
{
  # Human approval gate for high-risk agent actions
  # The agent-runner must call the approval endpoint before executing
  # any action classified as requiring human oversight
  systemd.services.approval-gate = {
    description = "Human approval gate for agent high-risk actions";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "ai-operator";
      Group = "ai-services";
      # Reference via Nix store path — NOT a mutable path like /opt
      ExecStart = "${approval-gate-pkg}/bin/approval-gate-server";
      Restart = "on-failure";
      RestartSec = 5;

      # The approval gate itself is sandboxed but needs network access
      # to receive requests from the agent-runner
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/approval-gate" ];
    };
  };

  # Agent-runner depends on approval-gate being available
  systemd.services.agent-runner = {
    requires = [ "approval-gate.service" ];
    after = [ "approval-gate.service" ];
    # If approval-gate goes down, agent-runner stops (fail-closed)
    bindsTo = [ "approval-gate.service" ];
  };

  # Override mechanism: operator can inject directives
  environment.etc."ai/agent-policy.json" = {
    mode = "0644";
    text = builtins.toJSON {
      actions_requiring_approval = [
        "file_write"
        "file_delete"
        "shell_execute"
        "network_request"
        "credential_access"
        "configuration_change"
      ];
      auto_approved_actions = [
        "file_read_within_sandbox"
        "inference_request"
        "log_write"
      ];
      max_autonomous_actions_per_session = 50;
      session_timeout_minutes = 60;
      fail_closed = true;  # If approval gate is unreachable, deny all
    };
  };
}
```

**Human oversight capabilities that must be available:**

| Capability | Implementation |
|---|---|
| Interrupt a running agent | `systemctl stop agent-runner` (available to ai-services group via sudo) |
| Override an agent decision | Approval gate deny + manual correction |
| Halt all AI services | `ai-emergency-stop` script (Section 1.4.2) |
| Review agent actions in progress | Live journald tail: `journalctl -u agent-runner -f` |
| Modify agent autonomy level | Edit `/etc/ai/agent-policy.json` and reload |
| Disable a specific model | `ollama rm <model>` or remove from model registry and rebuild |
| Roll back entire system | `nixos-rebuild switch --rollback` |

### 2.5 Accuracy, Robustness, and Cybersecurity (Article 15)

**Accuracy:**
- Pre-deployment validation test suites (Section 1.3.1).
- Document expected accuracy ranges for each use case in the model registry.
- Monitor output quality metrics over time; alert on degradation.

**Robustness:**
- Agent sandbox prevents cascading failures from model errors.
- systemd `Restart=on-failure` with `RestartSec` for inference services.
- NixOS generation rollback for system-level recovery.
- Rate limiting on inference API prevents resource exhaustion.

```nix
# ai-services/robustness.nix
{
  # Ollama service — use simple type, NOT notify.
  # Ollama does not support systemd watchdog notifications (sd_notify).
  # Using WatchdogSec with Ollama would cause systemd to kill the
  # process after the watchdog timeout expires with no ping received.
  # A separate health monitor timer handles liveness checking instead.
  systemd.services.ollama = {
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 5;
      # Resource limits prevent runaway inference from starving the host
      MemoryMax = "80%";
      CPUQuota = "400%";  # 4 cores max
      TimeoutStartSec = 120;
      # NOTE: No WatchdogSec — Ollama does not implement sd_notify.
      # See ollama-health timer below for liveness monitoring.
    };
  };

  # Separate health monitor for Ollama — replaces WatchdogSec
  # Checks Ollama's HTTP health endpoint and restarts on failure.
  systemd.services.ollama-health = {
    description = "Ollama health check — restart on failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ollama-health" ''
        if ! ${pkgs.curl}/bin/curl -sf http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then
          echo "Ollama health check failed" >&2
          systemctl restart ollama.service
          logger -p daemon.err "Ollama health check failed, restarting"
        fi
      '';
    };
  };

  systemd.timers.ollama-health = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*:0/5"; };  # every 5 minutes
  };

  systemd.services.agent-runner = {
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
      StartLimitBurst = 3;
      StartLimitIntervalSec = 300;
      # After 3 crashes in 5 minutes, stop restarting — requires manual intervention
      MemoryMax = "4G";
      CPUQuota = "200%";
    };
  };
}
```

**Cybersecurity:**
- All controls from the base PRD (STIG baseline, LAN-only network, SSH hardening, FDE, AIDE).
- AI-specific threats addressed in Section 4 (MITRE ATLAS).
- Model supply chain controls in Section 5.

### 2.6 Transparency Obligations (Article 13)

For systems classified as limited or high risk:

- Users interacting with the AI system must be informed they are interacting with an AI system (not a human).
- System outputs that could be mistaken for human-generated content must be labeled.
- The system description (Section 2.2) must be available to operators and affected persons.

**Organizational process requirement:** Application-layer APIs (port 8000) must include AI disclosure headers or response metadata:

```
X-AI-Generated: true
X-AI-Model: llama3.1-8b
X-AI-System: nixos-ai-server-v1
```

**Technical enforcement (partial):** The API application is responsible for including these headers. The infrastructure can enforce that the system description is available:

```nix
{
  # Make system description accessible to API services
  systemd.services.ai-api = {
    serviceConfig = {
      BindReadOnlyPaths = [
        "/etc/ai/system-description.json"
        "/etc/ai/model-registry.json"
      ];
    };
  };
}
```

### 2.7 Risk Management System (Article 9)

The EU AI Act Article 9 requires that high-risk AI systems have a risk management system established, implemented, documented, and maintained as a continuous iterative process throughout the system's lifecycle.

**Requirements mapped to this system:**

| Article 9 Requirement | Implementation |
|---|---|
| Identification and analysis of known and reasonably foreseeable risks | NIST AI RMF MAP function (Section 1.2.3); MITRE ATLAS threat model (Section 4) |
| Estimation and evaluation of risks from intended use and reasonably foreseeable misuse | Risk classification per use case (Section 2.1); intended-use documentation (Section 1.2.2) |
| Evaluation of risks from data used by the system | Data governance (Section 3.2); RAG data lineage (Section 3.2.1) |
| Adoption of risk management measures to address identified risks | Risk treatment table (Section 1.4.1); infrastructure controls matrix (Section 7) |
| Testing to identify the most appropriate risk management measures | Pre-deployment testing (Section 1.3.1); adversarial testing in validation script |
| Risk management measures appropriate to the effects of the AI system on children, vulnerable groups | Not currently applicable — internal-only system with technical staff users. Must be re-evaluated if use cases expand to external-facing or vulnerable populations |

**Organizational process requirement:** The risk management system must be reviewed and updated:
- When a new model is deployed or an existing model's use case changes.
- When a new agent workflow is introduced or an existing workflow gains new tool access.
- After any AI-specific incident (Section 1.4.2).
- At minimum annually, even absent triggering events.

**Technical enforcement:** The model registry (Section 1.2.2) and agent policy (Section 2.4) encode risk decisions in the flake and are version-controlled in Git. Changes to risk posture require a flake rebuild, ensuring traceability.

### 2.8 Data Governance (Article 10)

The EU AI Act Article 10 requires that high-risk AI systems using data for training, validation, or testing be developed on the basis of appropriate data governance and management practices.

**Requirements mapped to this system:**

| Article 10 Requirement | Implementation |
|---|---|
| Relevant design choices for data collection and preparation | Documented in model registry (provider, preprocessing); RAG pipeline design in flake source |
| Data quality criteria and metrics | Data quality metrics for RAG retrieval accuracy (Section 3.2.1) |
| Examination for possible biases | Bias assessment process (Section 1.3.3); data provenance tracking |
| Identification of data gaps or shortcomings | Organizational process — documented per use case in model registry |
| Appropriate statistical properties of training data | Not directly applicable to pre-trained model inference; applicable if fine-tuning (Section 3.2) |

**For RAG (retrieval-augmented generation) pipelines**, Article 10 is directly relevant because the retrieval corpus functions as runtime training data that shapes model outputs. Requirements:

- Document the sources and curation process for the RAG corpus.
- Monitor retrieval quality — are the correct documents being retrieved for given queries?
- Track data freshness — when were corpus documents last updated?
- Ensure the corpus does not contain biased, outdated, or incorrect information that would skew model outputs.
- See Section 3.2.1 for detailed RAG data governance requirements.

**For pre-trained open-weight models**, Article 10 compliance is limited because the operator does not control the training data. The operator must:

- Document what is publicly known about the model's training data (from the provider's model card or technical report).
- Record this information in the model registry alongside known limitations and biases.
- Accept and document the residual risk that the training data may contain biases or quality issues outside the operator's control.

---

## 3. ISO/IEC 42001 (AI Management System)

### 3.1 Annex A Control Mapping

ISO/IEC 42001:2023 defines AI-specific management system controls in Annex A. The following maps each control area to this system's implementation.

#### A.2 — AI Policies

| Control | Requirement | Implementation type |
|---|---|---|
| A.2.1 AI policy | Establish an AI policy aligned with organizational objectives | Organizational process |
| A.2.2 AI acceptable use | Define acceptable and prohibited uses of AI | Organizational process, enforced partially by agent-policy.json |
| A.2.3 AI risk management integration | Integrate AI risk into enterprise risk management | Organizational process (references NIST AI RMF Section 1) |

#### A.3 — Internal Organization

| Control | Requirement | Implementation type |
|---|---|---|
| A.3.1 Roles and responsibilities | Assign AI-specific roles | Technical (user accounts, Section 1.1.2) + Organizational |
| A.3.2 Segregation of duties | Separate development, deployment, and monitoring | Technical (distinct accounts, no shared credentials) |
| A.3.3 Contact with authorities | Maintain contact list for regulatory bodies | Organizational process |

#### A.4 — Resources for AI Systems

| Control | Requirement | Implementation type |
|---|---|---|
| A.4.1 Compute resources | Ensure adequate compute for safe operation | Technical: GPU resource limits, memory limits in systemd |
| A.4.2 Data resources | Manage data used by AI systems | Organizational + Technical (data classification, storage paths) |
| A.4.3 Human resources | Ensure competent personnel | Organizational process |
| A.4.4 Tool and infrastructure resources | Maintain AI development/deployment tooling | Technical: NixOS flake pins all dependencies reproducibly |

#### A.5 — Impact Assessment

| Control | Requirement | Implementation type |
|---|---|---|
| A.5.1 AI impact assessment | Assess potential impacts before deployment | Organizational process (NIST AI RMF MAP output, Section 1.2) |
| A.5.2 AI impact monitoring | Monitor impacts during operation | Technical: monitoring metrics (Section 1.3.2) + Organizational review |

#### A.6 — AI System Lifecycle

| Control | Requirement | Implementation type |
|---|---|---|
| A.6.1 Design and development | Document design decisions | Technical: flake repository + model registry |
| A.6.2 Data management | Govern data throughout lifecycle | See Section 3.2 below |
| A.6.3 Verification and validation | Test before and during deployment | Technical: validation scripts (Section 1.3.1) |
| A.6.4 Deployment | Controlled deployment process | Technical: NixOS rebuild with rollback |
| A.6.5 Operation and monitoring | Ongoing monitoring | Technical: health checks, AIDE, journald |
| A.6.6 Retirement | Controlled decommission | See Section 3.3 below |

#### A.7 — Data for AI Systems

| Control | Requirement | Implementation type |
|---|---|---|
| A.7.1 Data quality | Ensure data quality for AI | Organizational process |
| A.7.2 Data provenance | Track data origin and lineage | Technical: model registry includes source metadata |
| A.7.3 Data preparation | Document data preparation steps | Organizational process (relevant if fine-tuning) |
| A.7.4 Data labeling | Ensure labeling quality | Organizational process (relevant if fine-tuning) |

#### A.8 — Information for Interested Parties

| Control | Requirement | Implementation type |
|---|---|---|
| A.8.1 Transparency to users | Inform users about AI interaction | Application-layer (Section 2.6) |
| A.8.2 Reporting AI incidents | Report incidents to relevant parties | Organizational process (Section 1.4.2) |

#### A.9 — Use of AI Systems

| Control | Requirement | Implementation type |
|---|---|---|
| A.9.1 Intended use policies | Enforce intended use | Technical: agent-policy.json + sandbox restrictions |
| A.9.2 Human oversight | Enable human intervention | Technical: approval gates, kill switch (Section 2.4) |
| A.9.3 Monitoring by users | Enable users to monitor AI | Technical: journald access for ai-operator role |

#### A.10 — Third-Party and Supplier Relationships

| Control | Requirement | Implementation type |
|---|---|---|
| A.10.1 Supplier AI risk assessment | Assess model provider risks | Organizational process (see Section 3.4) |
| A.10.2 Third-party AI agreements | Document terms for model use | Organizational process (license tracking in model registry) |
| A.10.3 Monitoring third-party AI | Monitor for updates, vulnerabilities | Organizational process + Technical (version pinning, hash checks) |

### 3.2 Data Governance for Training and Fine-Tuning

If the system is used for fine-tuning or retrieval-augmented generation with local data:

**Technical enforcement:**

```nix
# ai-services/data-governance.nix
{
  # Training/fine-tuning data directory with restricted access
  systemd.tmpfiles.rules = [
    "d /var/lib/ai-training-data 0750 ai-admin ai-services -"
    "d /var/lib/ai-rag-data 0750 ai-admin ai-services -"
    "d /var/lib/ai-validation 0750 ai-admin ai-services -"
    "d /var/lib/ai-embeddings 0750 ai-admin ai-services -"
  ];

  # AIDE monitors training data integrity
  environment.etc."aide/ai-data.conf" = {
    text = ''
      /var/lib/ai-training-data p+i+n+u+g+s+sha256
      /var/lib/ai-rag-data p+i+n+u+g+s+sha256
      /var/lib/ai-embeddings p+i+n+u+g+s+sha256
    '';
  };
}
```

**Organizational process requirements:**

- All training data must be classified before use (public, internal, confidential, restricted).
- Data provenance must be documented: source, acquisition date, license, preprocessing steps.
- Data containing PII or sensitive information must be inventoried and protected according to its classification.
- Data retention and deletion policies must be defined and enforced.

#### 3.2.1 RAG Pipeline Data Governance (ISO 42001 A.6.2 / EU AI Act Article 10)

RAG pipelines introduce runtime data dependencies that directly influence model outputs, making data governance critical. The following requirements apply to any RAG deployment on this system.

**Data lineage tracking:**

- Every document ingested into the RAG corpus must have a lineage record: source system, ingestion timestamp, preprocessing steps applied (chunking strategy, metadata extraction), and the identity of the person or process that authorized ingestion.
- Lineage records must be stored alongside the corpus and exported as part of the daily log archival (Section 2.3).
- When a document is updated or re-ingested, the previous version's lineage must be retained for audit purposes.

**Embedding store versioning:**

- Embedding vectors must be versioned. When the embedding model changes, all vectors must be regenerated and the previous embedding store archived.
- The embedding model identity (name, version, hash) must be recorded in a manifest alongside the embedding store.
- Rolling back to a previous embedding model must be possible by restoring the archived embedding store and its associated manifest.

```nix
# ai-services/rag-data-governance.nix
{
  # Embedding store with version-tracked manifests
  environment.etc."ai/embedding-manifest.json" = {
    mode = "0644";
    text = builtins.toJSON {
      embedding_model = "nomic-embed-text";
      embedding_model_version = "1.5";
      embedding_model_hash = "sha256:...";
      embedding_dimensions = 768;
      corpus_version = "2026-01-15";
      chunk_strategy = "recursive-character-splitter-1024-overlap-128";
      document_count = "populated-at-ingest-time";
      last_full_reindex = "2026-01-15T00:00:00Z";
    };
  };

  # Embedding store directory structure
  systemd.tmpfiles.rules = [
    "d /var/lib/ai-embeddings/current 0750 ai-admin ai-services -"
    "d /var/lib/ai-embeddings/archive 0750 ai-admin ai-services -"
    "d /var/lib/ai-rag-data/lineage 0750 ai-admin ai-services -"
  ];
}
```

**Data quality metrics for retrieval accuracy:**

| Metric | Measurement method | Target | Review frequency |
|---|---|---|---|
| Retrieval precision (relevant docs in top-k) | Periodic evaluation against curated query-document pairs | > 80% precision at k=5 | Monthly |
| Retrieval recall (relevant docs not missed) | Same evaluation set | > 70% recall at k=10 | Monthly |
| Corpus freshness (age of oldest un-refreshed document) | Automated scan of ingestion timestamps | < 90 days for active sources | Weekly automated check |
| Embedding drift (similarity distribution shift after model update) | Compare similarity score distributions before/after re-embedding | KS statistic < 0.1 | On embedding model change |
| Chunk quality (are chunks semantically coherent) | Manual review of random sample | No split-sentence chunks | On chunk strategy change |

**Document retention and disposal:**

- Documents removed from the source system must be removed from the RAG corpus within the retention window defined by the data classification policy.
- When a document is removed from the corpus, its embedding vectors must also be deleted (not just the source text).
- Archived embedding stores (from previous versions) follow the same retention policy as the documents they represent.
- A quarterly audit must verify that the RAG corpus does not contain documents that should have been disposed of under the retention policy.
- Fine-tuning datasets, if any, must follow the same retention and disposal rules. Archive training run metadata (hyperparameters, dataset version, resulting model hash) before disposing of the training data.

### 3.3 Model Lifecycle Management

| Phase | Requirements | Implementation |
|---|---|---|
| **Selection** | Document selection criteria, evaluate alternatives, assess risk tier | Organizational process; record in model registry |
| **Deployment** | Hash verification, validation testing, registry update, controlled rollout | Technical: `ai-model-validate` script, Nix rebuild |
| **Monitoring** | Performance metrics, output quality, resource consumption | Technical: health checks, Prometheus, journald |
| **Update** | Re-validate, update registry, staged rollout, retain previous generation | Technical: NixOS generations for rollback |
| **Retirement** | Document retirement reason, remove from registry, archive logs, delete artifacts | Partially technical |

**Model retirement procedure:**

```bash
# 1. Stop services using the model
sudo systemctl stop agent-runner

# 2. Remove from Ollama
ollama rm <model-name>

# 3. Update model registry (remove entry or mark as retired)
# Edit /etc/ai/model-registry.json via flake and rebuild

# 4. Archive associated logs
sudo cp -r /var/lib/ai-audit-logs/ /var/lib/ai-archive/retired-<model-name>-$(date +%Y%m%d)/

# 5. Rebuild to apply registry change
sudo nixos-rebuild switch --flake .#ai-server

# 6. Verify removal
ollama list  # Should not include retired model
```

### 3.4 Third-Party and Supplier Controls

For open-weight models downloaded from external providers:

| Control | Requirement |
|---|---|
| Provider assessment | Document the model provider (Meta, Mistral AI, etc.), their security practices, and their model release process |
| License compliance | Record the license for each model in the registry; verify permitted use cases match intended deployment |
| Vulnerability monitoring | Subscribe to model provider security advisories; monitor for disclosed vulnerabilities or backdoor reports |
| Version pinning | Pin model versions by hash in the model registry; do not auto-update |
| Download verification | Verify checksums on every model download (see Section 5) |
| Dependency assessment | Evaluate CUDA, PyTorch, and runtime dependencies for known CVEs |

---

## 4. MITRE ATLAS Threat Model

MITRE ATLAS (Adversarial Threat Landscape for AI Systems) catalogs adversarial techniques against ML systems. The following maps ATLAS techniques to this system's threat model and mitigations.

**Note on ATLAS technique IDs:** MITRE ATLAS is under active development, and technique IDs and descriptions are reorganized across releases. The technique IDs and names referenced in this document were verified against the ATLAS knowledge base as of the document's publication date. These mappings should be re-verified against the current ATLAS knowledge base quarterly. Where an ID no longer resolves, check the ATLAS changelog for renames or merges.

### 4.1 Threat Model for Local Inference

#### 4.1.1 Exfiltration via ML Inference API (ATLAS: AML.T0024)

**Threat:** An attacker with host or LAN access exfiltrates model weights or sensitive data through the inference API, or copies model weights directly from `/var/lib/ollama/models/`.

**Attack vectors:**
- Compromised SSH credentials.
- Lateral movement from another LAN host.
- Physical access to the machine.
- Repeated inference queries designed to extract model parameters.

**Mitigations:**

| Control | ATLAS technique mitigated | Implementation |
|---|---|---|
| Full-disk encryption | AML.T0024 (Exfiltration via ML Inference API) | `stig-baseline` module — protects at-rest model files |
| File permissions on model directory | AML.T0024 | `ollama` user owns `/var/lib/ollama/models/`, mode 0700 |
| SSH key-only + no root | AML.T0024 | `stig-baseline` module — limits credential-based access |
| LAN-only firewall | AML.T0024 | `lan-only-network` module — no internet-facing attack surface |
| AIDE integrity monitoring | AML.T0024 | `audit-and-aide` — detects unauthorized file access patterns |

```nix
# ai-services/model-protection.nix
{
  systemd.tmpfiles.rules = [
    "d /var/lib/ollama 0700 ollama ollama -"
    "d /var/lib/ollama/models 0700 ollama ollama -"
  ];

  # Ollama service cannot be accessed by other local users
  systemd.services.ollama.serviceConfig = {
    UMask = "0077";
    ProtectHome = true;
    PrivateTmp = true;
  };
}
```

#### 4.1.2 Adversarial Inputs / Evasion (ATLAS: AML.T0015, AML.T0043)

**Threat:** Crafted inputs cause the model to produce incorrect, harmful, or manipulated outputs.

- AML.T0015: Evade ML Model — adversarial examples that cause misclassification or incorrect outputs.
- AML.T0043: Craft Adversarial Data — the broader technique of creating data specifically designed to manipulate ML system behavior, including poisoned training data and adversarial inputs.

**Attack vectors:**
- Malicious content in documents processed by RAG pipeline.
- Adversarial payloads in data submitted to the inference API.
- Indirect prompt injection via retrieved context.

**Mitigations:**

| Control | ATLAS technique | Implementation |
|---|---|---|
| Input validation at API layer | AML.T0015, AML.T0043 | Application-layer (port 8000 API must validate/sanitize) |
| Agent sandbox isolation | AML.T0015 | `agent-sandbox` module — limits blast radius of manipulated output |
| Human approval for high-risk actions | AML.T0043 | Approval gate (Section 2.4) — human reviews before execution |
| Output logging for review | AML.T0015 | `audit-and-aide` — all outputs logged for post-hoc analysis |
| Adversarial test suite | AML.T0015 | Pre-deployment testing (Section 1.3.1) |

**Detection requirements:**
- Log all inference requests with input hashes for anomaly detection.
- Alert on unusual input patterns: excessive length, encoding anomalies, repeated injection patterns.
- Monitor agent action patterns for deviations from baseline behavior.

#### 4.1.3 Backdoored Model Weights (ATLAS: AML.T0010, AML.T0018)

**Threat:** A downloaded model contains a backdoor that activates on specific trigger inputs, producing attacker-controlled outputs.

**Attack vectors:**
- Compromised model hosting platform.
- Supply chain attack on model provider.
- Trojaned fine-tuned variant distributed as legitimate.

**Mitigations:**

| Control | ATLAS technique | Implementation |
|---|---|---|
| Model provenance verification | AML.T0010 | Model registry with source, hash, signature (Section 5) |
| Download from trusted sources only | AML.T0010, AML.T0018 | Organizational policy — only official provider endpoints |
| Hash verification on download | AML.T0010 | Technical: checksum comparison (Section 5.1) |
| Behavioral testing post-download | AML.T0018 | `ai-model-validate` script with trigger-pattern test cases |
| AIDE monitoring of model files | AML.T0010 | Detect post-deployment modification of weight files |

**Detection requirements:**
- Verify model file hashes against registry on every service start.
- AIDE hourly integrity check of model directory.
- Behavioral baseline: periodic re-run of functional test suite to detect drift.

#### 4.1.4 Prompt Injection for Data Exfiltration (ATLAS: AML.T0051, AML.T0056)

**Threat:** An attacker injects prompts (directly or via retrieved context) that instruct the model to include sensitive data in outputs, which are then exfiltrated through agent actions or API responses.

**Attack vectors:**
- Poisoned documents in the RAG corpus.
- Malicious user input containing injection instructions.
- Indirect injection through chained agent tool outputs.

**Mitigations:**

| Control | ATLAS technique | Implementation |
|---|---|---|
| No internet egress | AML.T0051 | `lan-only-network` — even if injection succeeds, data cannot leave the LAN |
| Agent network restrictions | AML.T0051 | `RestrictAddressFamilies` in systemd — agent cannot open arbitrary connections |
| Output logging | AML.T0056 | All agent outputs logged for exfiltration pattern detection |
| Data classification enforcement | AML.T0051 | Organizational process — classified data segregated from model-accessible paths |
| Tool allowlisting | AML.T0056 | Only approved tools available — no arbitrary network or file access |

```nix
# agent-sandbox/network-isolation.nix
# NOTE: Canonical firewall and network isolation values are in prd.md
# Appendix A. The LAN subnets listed here are illustrative; the
# implementation flake should reference the canonical subnet list.
{
  systemd.services.agent-runner.serviceConfig = {
    # Agent can only communicate with localhost (Ollama, approval gate)
    # and the LAN subnet — no internet access even if firewall is misconfigured
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" ];
    IPAddressAllow = [ "127.0.0.0/8" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" ];
    IPAddressDeny = "any";
  };
}
```

**Detection requirements:**
- Monitor agent network connection attempts — alert on any denied connection.
- Scan agent outputs for patterns matching sensitive data formats (API keys, credential patterns, PII patterns).
- Log and review all data paths between RAG retrieval and agent output.

#### 4.1.5 Inference API Abuse (ATLAS: AML.T0040)

**Threat:** An attacker with LAN access abuses the inference API for unauthorized purposes: cryptomining via compute abuse, mass data extraction from model knowledge, or denial of service.

**Mitigations:**

| Control | ATLAS technique | Implementation |
|---|---|---|
| LAN-only access | AML.T0040 | `lan-only-network` — limits attacker pool to LAN users |
| Rate limiting | AML.T0040 | Application-layer rate limiting on port 8000; Ollama resource limits |
| Authentication on API | AML.T0040 | Application-layer — API keys or mTLS for inference endpoints |
| Resource limits | AML.T0040 | systemd `MemoryMax`, `CPUQuota` (Section 2.5) |
| Usage logging | AML.T0040 | Log all API calls with source IP, model, token count |

**Detection requirements:**
- Alert on unusual API call volume from any single source.
- Monitor GPU utilization — alert on sustained maximum utilization outside normal patterns.
- Track per-source token consumption.

### 4.2 ATLAS Technique-to-Mitigation Matrix

**Note:** ATLAS technique IDs are actively reorganized across ATLAS releases. Verify these mappings against the current ATLAS knowledge base at https://atlas.mitre.org quarterly.

| ATLAS ID | Technique | Primary mitigation | Module |
|---|---|---|---|
| AML.T0010 | ML Supply Chain Compromise | Hash verification, trusted sources, AIDE | `ai-services`, `audit-and-aide` |
| AML.T0015 | Evade ML Model | Input validation, adversarial testing | Application layer, `ai-services` |
| AML.T0018 | Backdoor ML Model | Provenance, behavioral testing | `ai-services` |
| AML.T0024 | Exfiltration via ML Inference API | FDE, permissions, LAN-only, SSH hardening | `stig-baseline`, `lan-only-network` |
| AML.T0040 | ML Model Inference API Access | Rate limiting, auth, resource limits | `ai-services`, `lan-only-network` |
| AML.T0043 | Craft Adversarial Data | Sandbox, approval gates, output review | `agent-sandbox` |
| AML.T0051 | LLM Prompt Injection | Input validation, no egress, tool allowlist | `agent-sandbox`, `lan-only-network` |
| AML.T0056 | LLM Data Leakage | Output logging, network isolation, data classification | `agent-sandbox`, `audit-and-aide` |

---

## 5. Model Supply Chain Security

### 5.1 Model Provenance and Integrity Verification

Every model downloaded to this system must pass provenance and integrity checks before deployment.

**Provenance limitation:** Ollama's model distribution does not currently support cryptographic provenance attestation (GPG signatures or SLSA). Verification is limited to hash comparison against a locally-maintained manifest. This is trust-on-first-download: the hash recorded on the first verified download becomes the baseline, but there is no cryptographic chain of trust back to the model author. If the Ollama registry or CDN is compromised at the time of first download, the compromised model would be accepted. Mitigations for this residual risk include downloading from multiple network vantage points and comparing hashes, or obtaining hashes out-of-band from the model provider's official documentation when available.

**Technical enforcement:**

```nix
# ai-services/model-supply-chain.nix
{
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "ai-model-fetch" ''
      set -euo pipefail

      MODEL_NAME="$1"
      EXPECTED_HASH="$2"  # sha256 hash from model registry

      if [ -z "$MODEL_NAME" ] || [ -z "$EXPECTED_HASH" ]; then
        echo "Usage: ai-model-fetch <model-name> <expected-sha256>"
        exit 1
      fi

      echo "$(date -Iseconds) Fetching model: $MODEL_NAME" | systemd-cat -p info -t model-supply-chain

      # Pull via Ollama
      ollama pull "$MODEL_NAME"

      # Verify the model is present in Ollama
      ollama show "$MODEL_NAME" --modelfile > /dev/null 2>&1
      if [ $? -ne 0 ]; then
        echo "ERROR: Model $MODEL_NAME not found in Ollama after pull" | systemd-cat -p err -t model-supply-chain
        exit 1
      fi

      # Ollama stores models as content-addressed blobs, not .bin files.
      # Blob filenames are their sha256 digests (e.g., sha256-<hex>).
      OLLAMA_BLOB_DIR="/var/lib/ollama/models/blobs"

      # Find the primary model blob by checking Ollama's manifest
      # The manifest lists layer digests; the largest layer is the model weights
      MANIFEST_DIR="/var/lib/ollama/models/manifests"
      # Parentheses required: without them, find applies -print to non-matching
      # files from the first -path pattern, producing incorrect results.
      MANIFEST_FILE=$(find "$MANIFEST_DIR" \( -path "*/$MODEL_NAME" -o -path "*/${MODEL_NAME/://}" \) 2>/dev/null | head -1)

      if [ -z "$MANIFEST_FILE" ] || [ ! -f "$MANIFEST_FILE" ]; then
        # Fallback: find the most recently modified blob
        ACTUAL_BLOB=$(ls -t "$OLLAMA_BLOB_DIR"/sha256-* 2>/dev/null | head -1)
      else
        # Extract the largest layer digest from the Ollama manifest
        LAYER_DIGEST=$(${pkgs.jq}/bin/jq -r '.layers[] | select(.mediaType | contains("model")) | .digest' "$MANIFEST_FILE" 2>/dev/null | head -1)
        if [ -n "$LAYER_DIGEST" ]; then
          # Convert "sha256:abc123" to filename "sha256-abc123"
          BLOB_NAME=$(echo "$LAYER_DIGEST" | tr ':' '-')
          ACTUAL_BLOB="$OLLAMA_BLOB_DIR/$BLOB_NAME"
        else
          ACTUAL_BLOB=$(ls -t "$OLLAMA_BLOB_DIR"/sha256-* 2>/dev/null | head -1)
        fi
      fi

      if [ -z "$ACTUAL_BLOB" ] || [ ! -f "$ACTUAL_BLOB" ]; then
        echo "ERROR: Could not locate model blob in $OLLAMA_BLOB_DIR" | systemd-cat -p err -t model-supply-chain
        exit 1
      fi

      ACTUAL_HASH=$(sha256sum "$ACTUAL_BLOB" | cut -d' ' -f1)

      if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
        echo "CRITICAL: Hash mismatch for $MODEL_NAME" | systemd-cat -p crit -t model-supply-chain
        echo "  Expected: $EXPECTED_HASH"
        echo "  Actual:   $ACTUAL_HASH"
        echo "Removing unverified model."
        ollama rm "$MODEL_NAME"
        exit 1
      fi

      echo "$(date -Iseconds) Model $MODEL_NAME verified: hash=$ACTUAL_HASH" | systemd-cat -p info -t model-supply-chain

      # Update provenance log
      echo "{\"timestamp\": \"$(date -Iseconds)\", \"model\": \"$MODEL_NAME\", \"hash\": \"$ACTUAL_HASH\", \"source\": \"ollama-registry\", \"verified\": true, \"provenance_method\": \"hash-comparison-trust-on-first-download\"}" \
        >> /var/lib/ai-audit-logs/model-provenance.jsonl
    '')
  ];
}
```

**Integrity verification script (for ongoing checks against locally-maintained manifest):**

```bash
#!/usr/bin/env bash
# Verify model integrity against manifest
MODEL_NAME="$1"
MANIFEST="/var/lib/ai-models/manifests/${MODEL_NAME}.json"

if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: No manifest for model $MODEL_NAME" >&2
  exit 1
fi

# Ollama stores models in ~/.ollama/models/blobs/
OLLAMA_BLOB_DIR="/var/lib/ollama/models/blobs"

# Verify each layer digest from the Ollama manifest
ollama show "$MODEL_NAME" --modelfile > /tmp/modelfile-check 2>&1
if [ $? -ne 0 ]; then
  echo "ERROR: Model $MODEL_NAME not found in Ollama" >&2
  exit 1
fi

# Compare expected hash from our manifest against Ollama's stored digest
EXPECTED_HASH=$(jq -r '.sha256' "$MANIFEST")
# Ollama blob filenames ARE their sha256 digests
ACTUAL_BLOB=$(find "$OLLAMA_BLOB_DIR" -name "sha256-*" -newer "$MANIFEST" 2>/dev/null | head -1)

if [ -n "$ACTUAL_BLOB" ]; then
  ACTUAL_HASH=$(sha256sum "$ACTUAL_BLOB" | cut -d' ' -f1)
  if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo "INTEGRITY FAILURE: Model $MODEL_NAME hash mismatch" >&2
    logger -p auth.crit "AI model integrity failure: $MODEL_NAME expected=$EXPECTED_HASH actual=$ACTUAL_HASH"
    exit 2
  fi
fi

echo "Model $MODEL_NAME integrity verified"
logger -p auth.info "AI model integrity verified: $MODEL_NAME hash=$EXPECTED_HASH"
```

### 5.2 Model Manifest Requirements

Each model in the registry must include:

| Field | Required | Example |
|---|---|---|
| `name` | Yes | `llama3.1-8b` |
| `provider` | Yes | `meta` |
| `version` | Yes | `3.1` |
| `source_url` | Yes | `https://ollama.com/library/llama3.1` |
| `hash_algorithm` | Yes | `sha256` |
| `hash` | Yes | `abc123...` |
| `license` | Yes | `llama3.1-community` |
| `license_compliant_uses` | Yes | `["research", "commercial-non-eu-military"]` |
| `known_limitations` | Yes | Array of documented limitation strings |
| `known_biases` | Yes | Array of documented bias descriptions |
| `risk_tier` | Yes | `minimal`, `limited`, `high` |
| `intended_use` | Yes | Free text description |
| `deployment_date` | Yes | ISO 8601 date |
| `review_due` | Yes | ISO 8601 date (max 6 months from deployment) |
| `validation_results_path` | Yes | Path to pre-deployment test results |
| `retired` | No | `false` (set to `true` on retirement) |
| `retirement_date` | No | ISO 8601 date |
| `retirement_reason` | No | Free text |

### 5.3 AI Runtime Dependency Verification

The NixOS flake approach provides strong guarantees for dependency verification:

```nix
# flake.nix — pin all AI runtime dependencies
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    # Pin to a specific commit for reproducibility
    # nixpkgs.url = "github:NixOS/nixpkgs/abc123def456";
  };

  # All CUDA, cuDNN, PyTorch, and other AI runtime dependencies
  # are resolved from the pinned nixpkgs input.
  # The flake.lock file records the exact commit hash and NAR hash.
}
```

**Dependency security requirements:**

| Dependency | Verification method |
|---|---|
| NVIDIA driver | Pinned via nixpkgs; version tracked in flake.lock |
| CUDA toolkit | Pinned via nixpkgs; hash-verified by Nix |
| Ollama | Pinned via nixpkgs or overlay; hash-verified |
| Python + ML libraries (if used) | Pinned via nixpkgs; hash-verified by Nix |
| Container images (if used) | Pinned by digest, not tag |

**Organizational process:** Review `flake.lock` changes in every PR. Verify that nixpkgs updates do not introduce known CVEs in AI runtime dependencies. Subscribe to security advisories for NVIDIA, CUDA, and Ollama.

### 5.4 Model Download, Storage, and Deployment Pipeline

```
+------------------+     +------------------+     +------------------+
| 1. Request       | --> | 2. Fetch +       | --> | 3. Validate      |
|    (model name,  |     |    Hash verify   |     |    (functional,  |
|     expected hash)|     |    ai-model-fetch|     |     adversarial) |
+------------------+     +------------------+     +------------------+
                                                          |
                                                          v
+------------------+     +------------------+     +------------------+
| 6. Monitor       | <-- | 5. Deploy        | <-- | 4. Register      |
|    (AIDE, health |     |    (rebuild from  |     |    (update model |
|     checks, logs)|     |     flake)        |     |     registry)    |
+------------------+     +------------------+     +------------------+
```

**Controls at each stage:**

1. **Request**: Only `ai-admin` role can initiate model downloads. Documented approval required for high-risk tier models.
2. **Fetch + Verify**: `ai-model-fetch` script enforces hash verification. Failed verification removes the model and logs a critical event.
3. **Validate**: `ai-model-validate` script runs functional and adversarial test suites. Results archived.
4. **Register**: Model added to `/etc/ai/model-registry.json` in the flake. Change tracked in Git.
5. **Deploy**: `nixos-rebuild switch` applies the new registry. Previous generation available for rollback.
6. **Monitor**: AIDE checks model file integrity hourly. Health checks verify service availability every 5 minutes. Logs exported daily.

---

## 6. Emerging Frameworks (Awareness)

The following frameworks are tracked for awareness purposes. Their unique control requirements are substantially covered by the primary frameworks (NIST AI RMF, EU AI Act, ISO 42001, MITRE ATLAS) already addressed in this document. No additional controls are derived from these frameworks at this time.

| Framework | Alignment with primary controls |
|---|---|
| **Google Secure AI Framework (SAIF)** | SAIF's six elements (strong foundations, detection/response, automated defenses, platform-level controls, adaptive controls, business context) map directly to the NixOS STIG baseline, ATLAS threat model, AIDE monitoring, declarative configuration, NixOS rollback, and per-use-case risk classification already implemented |
| **CISA/NSA/FBI AI Security Guidelines** (Nov 2023) | Secure-by-design, secure-by-default, secure deployment, and secure operations principles are addressed by the NixOS flake architecture, LAN-only defaults, hash-verified model supply chain, and AIDE/health-check monitoring |
| **Anthropic Responsible Scaling Policy (RSP)** | Capability evaluation, tiered safety, containment, and red-teaming principles align with pre-deployment validation (Section 1.3.1), risk-tier classification in model registry, agent sandbox, and adversarial testing |

These frameworks should be re-reviewed annually for any new control requirements not covered by the primary frameworks. If a future revision introduces a materially distinct control, it should be added to the combined control matrix (Section 7).

---

## 7. Combined AI Governance Control Matrix

This matrix maps specific implementation requirements across all frameworks covered in this document.

### 7.1 Infrastructure Controls (Implemented in Flake/Runtime)

| Control ID | Control | Priority | Phase | NIST AI RMF | EU AI Act | ISO 42001 | MITRE ATLAS | Supply Chain | NixOS Module |
|---|---|---|---|---|---|---|---|---|---|
| AI-INFRA-01 | Agent sandbox (systemd hardening) | Critical | 1 | MANAGE | Art. 15 (robustness) | A.6.4 | AML.T0043, T0051 | — | `agent-sandbox` |
| AI-INFRA-02 | Tool allowlisting for agents | Critical | 1 | GOVERN, MANAGE | Art. 14 (oversight) | A.9.1 | AML.T0051, T0056 | — | `agent-sandbox` |
| AI-INFRA-03 | Human approval gate (fail-closed) | Critical | 1 | MANAGE | Art. 14 (oversight) | A.9.2 | AML.T0043 | — | `agent-sandbox` |
| AI-INFRA-04 | Emergency kill switch | Critical | 1 | MANAGE | Art. 14 (oversight) | A.9.2 | — | — | `agent-sandbox` |
| AI-INFRA-05 | Model file integrity monitoring (AIDE) | High | 1 | MEASURE | Art. 15 (cybersecurity) | A.6.5 | AML.T0010, T0024 | Integrity | `audit-and-aide` |
| AI-INFRA-06 | Structured AI event logging | High | 1 | MEASURE | Art. 12 (logging) | A.6.5 | AML.T0040 | — | `audit-and-aide` |
| AI-INFRA-07 | Log export and archival | High | 2 | MEASURE | Art. 12 (logging) | A.6.5 | — | — | `audit-and-aide` |
| AI-INFRA-08 | Model file permissions (0700 ollama:ollama) | High | 1 | MANAGE | Art. 15 (cybersecurity) | A.4.1 | AML.T0024 | Storage | `ai-services` |
| AI-INFRA-09 | Agent network isolation (IPAddressAllow/Deny) | Critical | 1 | MANAGE | Art. 15 (cybersecurity) | A.6.4 | AML.T0051, T0056 | — | `agent-sandbox` |
| AI-INFRA-10 | Resource limits (MemoryMax, CPUQuota) | Medium | 2 | MANAGE | Art. 15 (robustness) | A.4.1 | AML.T0040 | — | `ai-services` |
| AI-INFRA-11 | Ollama health monitor and restart policy | High | 1 | MANAGE | Art. 15 (robustness) | A.6.5 | — | — | `ai-services` |
| AI-INFRA-12 | Role-separated user accounts | High | 1 | GOVERN | Art. 14 (oversight) | A.3.1, A.3.2 | AML.T0024 | — | `stig-baseline` |
| AI-INFRA-13 | Model hash verification on download | High | 1 | MANAGE | Art. 15 (cybersecurity) | A.7.2 | AML.T0010 | Provenance | `ai-services` |
| AI-INFRA-14 | Dependency pinning via flake.lock | Medium | 2 | MANAGE | Art. 15 (cybersecurity) | A.4.4 | AML.T0010 | Dependencies | `flake.nix` |
| AI-INFRA-15 | LAN-only network (no egress for agents) | Critical | 1 | MANAGE | Art. 15 (cybersecurity) | A.6.4 | AML.T0051 | — | `lan-only-network` |
| AI-INFRA-16 | NixOS generation rollback | Medium | 2 | MANAGE | Art. 15 (robustness) | A.6.4 | — | Deployment | NixOS core |
| AI-INFRA-17 | AI health check timer (5-minute interval) | High | 2 | MEASURE | Art. 12 (monitoring) | A.6.5 | AML.T0040 | — | `audit-and-aide` |
| AI-INFRA-18 | Model registry as /etc/ai/model-registry.json | High | 1 | MAP | Art. 11 (documentation) | A.7.2 | AML.T0010 | Manifest | `ai-services` |
| AI-INFRA-19 | System description as /etc/ai/system-description.json | Medium | 2 | MAP | Art. 11 (documentation) | A.8.1 | — | — | `ai-services` |
| AI-INFRA-20 | Full-disk encryption for model storage | High | 1 | MANAGE | Art. 15 (cybersecurity) | A.4.1 | AML.T0024 | Storage | `stig-baseline` |
| AI-INFRA-21 | Inference request/response logging middleware | High | 2 | MEASURE | Art. 12 (logging) | A.6.5 | AML.T0040 | — | Application layer |

**Implementation phases:**
- **Phase 1 (Deploy)**: Controls required before the system processes any real data. These establish the security boundary and basic accountability.
- **Phase 2 (Harden)**: Controls required within 30 days of initial deployment. These add monitoring depth, archival, and documentation completeness.

**Priority definitions:**
- **Critical**: Must be implemented before the system is operational. Failure to implement creates an immediate, exploitable risk or a regulatory non-compliance that cannot be mitigated by other controls.
- **High**: Must be implemented before processing sensitive data or operating in a high-risk use case. Essential for defense-in-depth.
- **Medium**: Should be implemented within 30 days. Improves auditability, recovery, and operational maturity.
- **Low**: Recommended. Improves posture but absence is tolerable for internal-only, low-risk deployments.

### 7.2 Organizational Process Controls (Cannot Be Fully Automated)

| Control ID | Control | Priority | Phase | NIST AI RMF | EU AI Act | ISO 42001 | Frequency |
|---|---|---|---|---|---|---|---|
| AI-ORG-01 | AI risk management policy | Critical | 1 | GOVERN | Art. 9 | A.2.1 | Annual review |
| AI-ORG-02 | Acceptable use policy for AI | Critical | 1 | GOVERN | Art. 9 | A.2.2 | Annual review |
| AI-ORG-03 | Role assignment and accountability | High | 1 | GOVERN | Art. 14 | A.3.1 | On personnel change |
| AI-ORG-04 | AI risk awareness training | Medium | 2 | GOVERN | Art. 14 | A.4.3 | Annual |
| AI-ORG-05 | Model risk classification per use case | Critical | 1 | MAP | Art. 6 | A.5.1 | On new model or use case |
| AI-ORG-06 | Intended-use documentation per model | High | 1 | MAP | Art. 11 | A.6.1 | On deployment, review 6-monthly |
| AI-ORG-07 | Bias assessment for people-affecting use cases | Medium | 2 | MEASURE | Art. 10 | A.5.1 | On deployment, annual re-assessment |
| AI-ORG-08 | Pre-deployment functional/safety testing | Critical | 1 | MEASURE | Art. 9 | A.6.3 | On every model change |
| AI-ORG-09 | AI incident response procedure | High | 2 | MANAGE | Art. 62 | A.8.2 | Annual review; post-incident update |
| AI-ORG-10 | Post-incident review | High | 2 | MANAGE | Art. 62 | A.8.2 | Within 5 business days of incident |
| AI-ORG-11 | Quarterly AI risk review | Medium | 2 | MANAGE | Art. 9 | A.5.2 | Quarterly |
| AI-ORG-12 | Model provider/supplier assessment | Medium | 2 | MAP | Art. 16 | A.10.1 | On new provider, annual re-assessment |
| AI-ORG-13 | License compliance verification | High | 1 | GOVERN | Art. 53 | A.10.2 | On model download |
| AI-ORG-14 | Data governance for training/RAG data | High | 1 | MAP | Art. 10 | A.7.1-A.7.4 | On data pipeline change |
| AI-ORG-15 | Model retirement procedure | Medium | 2 | MANAGE | Art. 11 | A.6.6 | On retirement decision |
| AI-ORG-16 | Transparency disclosure to users | High | 2 | GOVERN | Art. 13, 52 | A.8.1 | Continuous (application-layer) |
| AI-ORG-17 | Regulatory contact maintenance | Low | 2 | GOVERN | Art. 62 | A.3.3 | Annual |

#### 7.2.1 Tiered Implementation Guide

The 17 organizational processes above are the full set for comprehensive compliance. In practice, the required scope depends on the deployment context. Use the tier below that matches your situation.

**Tier 1 — Single operator, internal-only, low-risk AI** (5 core processes)

Implement: AI-ORG-01, AI-ORG-02, AI-ORG-05, AI-ORG-08, AI-ORG-14

This is the minimum viable governance for a single person running local inference for their own use (code assistance, document summarization, internal tooling). It covers: having a written policy (even a brief one), knowing what uses are acceptable, classifying each model's risk, testing before deployment, and governing the data the model sees.

Use cases: Personal productivity AI, internal dev tooling, experimentation with open-weight models, LAN-only inference with no sensitive data.

**Tier 2 — Small team, sensitive data, medium-risk AI** (11 total processes)

Add to Tier 1: AI-ORG-03, AI-ORG-04, AI-ORG-06, AI-ORG-09, AI-ORG-10, AI-ORG-15

This tier adds accountability (who is responsible), training (team members understand the risks), intended-use documentation (what the model is supposed to do), incident response (what happens when something goes wrong), and model lifecycle management.

Use cases: Team-shared AI services, RAG over internal knowledge bases, agent workflows with tool access, processing sensitive but non-regulated data, any deployment where multiple people rely on AI outputs.

Mandatory escalation to Tier 2: If processing ePHI, PII, financial data, or any data subject to regulatory retention requirements. If agent workflows can modify production systems. If AI outputs influence decisions affecting people (hiring, access, prioritization).

**Tier 3 — Full compliance, high-risk AI, regulated data** (all 17 processes)

Add to Tier 2: AI-ORG-07, AI-ORG-11, AI-ORG-12, AI-ORG-13, AI-ORG-16, AI-ORG-17

This is the complete set, required when: operating under the EU AI Act's high-risk classification, processing regulated data (ePHI under HIPAA, data under GDPR), AI outputs directly influence consequential decisions, or pursuing ISO 42001 certification.

Use cases: Health data processing (ePHI), AI-assisted decision-making in regulated domains, any Annex III high-risk classification under EU AI Act, deployments subject to external audit or regulatory inspection.

**Tier selection decision tree:**

1. Is any use case classified as high-risk under EU AI Act Annex III? Yes: Tier 3.
2. Does the system process ePHI, PII subject to GDPR, or financial data subject to regulatory requirements? Yes: minimum Tier 2, likely Tier 3.
3. Do multiple people use or depend on the system? Yes: minimum Tier 2.
4. Can agent workflows modify production systems or make decisions affecting people? Yes: minimum Tier 2.
5. Is this a single operator running inference for personal internal use only? Tier 1 is sufficient.

### 7.3 Combined Control Summary by Module

| Flake module | Infrastructure controls | Frameworks addressed |
|---|---|---|
| `stig-baseline` | AI-INFRA-12, AI-INFRA-20 | NIST AI RMF GOVERN/MANAGE, EU AI Act Art. 15, ISO 42001 A.3/A.4, ATLAS AML.T0024 |
| `lan-only-network` | AI-INFRA-15 | NIST AI RMF MANAGE, EU AI Act Art. 15, ISO 42001 A.6.4, ATLAS AML.T0051 |
| `audit-and-aide` | AI-INFRA-05, AI-INFRA-06, AI-INFRA-07, AI-INFRA-17 | NIST AI RMF MEASURE, EU AI Act Art. 12/15, ISO 42001 A.6.5, ATLAS AML.T0010/T0024/T0040 |
| `agent-sandbox` | AI-INFRA-01, AI-INFRA-02, AI-INFRA-03, AI-INFRA-04, AI-INFRA-09 | NIST AI RMF MANAGE, EU AI Act Art. 14/15, ISO 42001 A.9.1/A.9.2, ATLAS AML.T0043/T0051/T0056 |
| `ai-services` | AI-INFRA-08, AI-INFRA-10, AI-INFRA-11, AI-INFRA-13, AI-INFRA-18, AI-INFRA-19 | NIST AI RMF MAP/MANAGE, EU AI Act Art. 11/15, ISO 42001 A.4/A.6/A.7, ATLAS AML.T0010/T0024/T0040, Supply Chain |
| `gpu-node` | (supports AI-INFRA-10, AI-INFRA-14) | NIST AI RMF MANAGE, ISO 42001 A.4.4, Supply Chain dependencies |

---

## 8. Acceptance Criteria for This Module

- A model registry schema is defined and enforced in the `ai-services` module.
- Every deployed model has a documented intended use, risk tier, hash, license, and known limitations.
- Human approval gates are operational and fail-closed for agent high-risk actions.
- An emergency kill switch stops all AI services and is accessible to authorized personnel.
- AIDE monitors model file integrity with hourly checks.
- Structured AI event logs are exported daily with 18-month retention.
- A pre-deployment model validation script is available and documented.
- The AI governance control matrix (Section 7) is maintained and reviewed quarterly.
- All organizational process controls (Section 7.2) have designated owners and review schedules.
- AI-specific incident response procedures are documented and tested annually.
- The approval gate server is packaged as a Nix derivation and referenced via Nix store path.
- The application layer on port 8000 includes request/response logging middleware for EU AI Act Article 12 compliance.
- Ollama health monitoring uses a timer-based health check, not WatchdogSec.

## 9. Risks and Open Questions

- **Model hash availability**: Not all model providers publish SHA-256 hashes for their weights. For providers that do not, the first-download hash becomes the baseline — this accepts the risk of a compromised initial download.
- **Ollama abstraction layer**: Ollama manages its own model storage format internally. Models are stored as content-addressed blobs (not `.bin` files), with filenames derived from their sha256 digests. The `ai-model-fetch` script is written against this storage layout, but the layout could change across Ollama versions. Pin the Ollama version and re-verify blob layout on upgrades.
- **Ollama provenance limitations**: Ollama's model distribution does not support GPG signatures, SLSA provenance, or any cryptographic attestation back to the model author. All verification is hash-comparison against a locally-maintained manifest. This is trust-on-first-download.
- **EU AI Act classification uncertainty**: Whether a specific internal use case qualifies as high-risk under Annex III depends on the nature of decisions influenced by model outputs. Legal counsel should review classification decisions.
- **Bias assessment tooling**: No standardized bias assessment tooling is included in the NixOS package set. The operator must source or build evaluation benchmarks appropriate to their use cases.
- **Prompt injection is an unsolved problem**: Input validation and sandboxing reduce the impact of prompt injection but cannot eliminate it. The approval gate and network isolation are defense-in-depth layers, not prevention.
- **MITRE ATLAS is evolving**: ATLAS technique IDs and descriptions are actively reorganized across releases. The technique-to-mitigation matrix (Section 4.2) should be verified against the current ATLAS knowledge base quarterly, not just annually.
- **Emerging regulation**: The EU AI Act implementation timelines extend through 2027. Requirements may be clarified or amended through implementing acts and guidelines. ISO/IEC 42001 certification requirements may also evolve.
- **Ollama does not support sd_notify**: The Ollama process does not implement the systemd watchdog protocol. Do not use `WatchdogSec` or `Type=notify` with the Ollama service. Use the timer-based health monitor instead (Section 2.5).
