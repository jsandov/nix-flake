# PRD Module: HIPAA Compliance Mapping for NixOS AI Agentic Server

## 1. Purpose and Scope

This document is a compliance-specific PRD module that maps the NixOS AI Agentic Server (defined in `prd.md`) to the HIPAA Security Rule (45 CFR Part 164, Subpart C), the technical implementation aspects of the Privacy Rule (45 CFR Part 164, Subpart E), and the Breach Notification Rule (45 CFR Part 164, Subpart D). It does not replace the parent PRD; it extends the control mapping with HIPAA-specific depth.

The system may process electronic protected health information (ePHI) through several pathways: user prompts containing patient data, retrieval-augmented generation (RAG) context sourced from clinical documents, agent outputs that reference or derive from ePHI, and log entries that inadvertently capture ePHI fragments. Every component of the flake must be evaluated against these pathways.

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the HIPAA-specific rationale; the implementation flake uses only the canonical values.

This module distinguishes between what the NixOS host configuration can enforce, what requires application-layer controls, and what requires administrative or organizational measures outside the machine build entirely. HIPAA implementation specifications are marked as **Required (R)** or **Addressable (A)** per the regulation. Addressable does not mean optional; it means the covered entity must implement the specification or document why an equivalent alternative is reasonable and appropriate.

---

## CRITICAL RISK: Live Memory ePHI Exposure During Inference

**This is the most significant residual risk in the system and must be understood before evaluating any other control.**

### The Problem

During model inference, ePHI exists **unencrypted in system RAM and GPU VRAM**. When a prompt containing patient data is submitted, that data is loaded into memory in plaintext for tokenization, attention computation, and response generation. This applies to both the prompt itself and any RAG context retrieved to augment it.

**LUKS full-disk encryption provides ZERO protection for data in memory on a running system.** LUKS encrypts data at rest on the block device. Once the system is booted and the volume is unlocked, all data read from disk into RAM is decrypted. Any process with sufficient privileges (or any exploit achieving kernel-level access) can read ePHI directly from memory.

### Safe Harbor Does NOT Apply to Live Systems

The HITECH Act encryption safe harbor (45 CFR Section 164.402(2)) applies to ePHI that is encrypted on storage media. It does NOT cover ePHI resident in the memory of a running system. If an attacker gains access to a live, running server -- even one with LUKS enabled -- and extracts ePHI from RAM or VRAM, this is a potential breach that is NOT protected by the encryption safe harbor.

### Mitigation Options

**Hardware-based memory encryption (preferred if available):**

- **AMD SEV-SNP (Secure Encrypted Virtualization - Secure Nested Paging):** Provides per-VM memory encryption with hardware-enforced isolation. If the server uses AMD EPYC processors with SEV-SNP support, this can encrypt memory pages in use, protecting against physical memory attacks and certain hypervisor-level attacks.
- **Intel TDX (Trust Domain Extensions):** Provides similar hardware-enforced memory encryption for Intel platforms. Available on 4th Gen Xeon Scalable and later.

If the hardware supports either technology, enable it and document the configuration. Note that consumer-grade CPUs (including most workstation hardware this flake targets) typically do NOT support SEV-SNP or TDX.

**Software and operational mitigations (when hardware memory encryption is unavailable):**

- **Minimize ePHI retention in context windows:** Configure inference runtimes to use the smallest context window necessary. Do not maintain conversation history containing ePHI beyond the immediate request lifecycle. See Section 2.3.1 for model context persistence risks.
- **Implement session-level clearing:** After each inference request involving ePHI, explicitly clear session state. Application-layer code must null out prompt buffers and context arrays rather than relying on garbage collection.
- **Disable swap or encrypt it:** Swap can write memory contents (including ePHI) to disk. Encrypted swap is mandatory (see Section 5.1.4). Consider disabling swap entirely for inference workloads.
- **Disable core dumps:** Prevent ePHI in memory from being written to disk via core dumps (see Section 2.3.2).
- **Physical security:** Restrict physical access to the running server. Physical access to a running system allows cold boot attacks, DMA attacks via Thunderbolt/PCIe, and direct memory inspection.
- **Access control hardening:** Minimize the number of accounts and processes that could be used to read arbitrary memory. No unnecessary services, no development tools in production.
- **Monitoring:** Deploy host-based intrusion detection to alert on unexpected memory access patterns, ptrace attempts against inference processes, and attempts to load kernel modules.

### Accepted Risk Documentation

**If neither AMD SEV-SNP nor Intel TDX is available on the deployment hardware (which is the expected case for workstation-class hardware), the exposure of ePHI in live memory during inference is an ACCEPTED RISK with the following compensating controls:**

1. Physical access to the server is restricted to authorized personnel (Section 4.1).
2. No remote root access; SSH key-only with MFA where implemented (Section 5.4).
3. All inference services run under dedicated, unprivileged system users with systemd sandboxing (Section 2.4).
4. `kernel.yama.ptrace_scope = 2` prevents non-root processes from attaching to inference processes.
5. Core dumps are disabled system-wide (Section 2.3.2).
6. Swap is encrypted or disabled (Section 5.1.4).
7. Auditd monitors for privilege escalation and anomalous process behavior (Section 3.1.4).
8. Network is LAN-only, reducing remote exploitation surface (Section 5.5).

**This risk must be explicitly acknowledged in the organization's risk analysis (Section 3.1.1) and reviewed at each periodic evaluation (Section 3.8).**

---

## 2. ePHI Data Flow Through the AI System

Before mapping individual safeguards, the data flow must be understood. ePHI can enter and traverse the system through the following stages, each requiring specific controls.

### 2.1 Stage 1: Prompt Ingestion

User submits a prompt to Ollama (port 11434) or an application API (port 8000) that contains ePHI. This may be direct clinical text, patient identifiers embedded in questions, or coded references resolvable to individuals.

**Controls required:**
- Transmission encryption (TLS) from client to server, even on the LAN.
- Authentication of the requesting user or service before the prompt is accepted.
- Access logging: who submitted what prompt, when, from which source IP.
- Input validation: application-layer check for ePHI markers to trigger elevated handling (not solvable at the NixOS level alone).

### 2.2 Stage 2: RAG Context Retrieval

The application retrieves stored documents, embeddings, or database records that may contain ePHI to augment the prompt before inference.

**Controls required:**
- Filesystem-level access control on RAG data stores (`/var/lib/ai-services/rag` or equivalent), enforced via POSIX permissions and systemd sandboxing.
- Encryption at rest for RAG data stores (LUKS full-disk encryption covers this if the store resides on the encrypted volume).
- Audit trail of which documents were retrieved and by which service identity.
- Minimum necessary enforcement: application-layer filtering to retrieve only records relevant to the authorized query scope.

### 2.3 Stage 3: Model Inference

The prompt plus context is processed by Ollama or another local model runtime. During inference, ePHI exists in GPU VRAM, system RAM, and potentially in temporary files or swap. **This is the stage with the highest ePHI exposure risk -- see the Critical Risk section above.**

**Controls required:**
- Memory isolation: the inference service must run under a dedicated user with systemd sandboxing (`ProtectSystem=strict`, `PrivateTmp=true`). **Note:** `MemoryDenyWriteExecute=true` cannot be applied to CUDA/GPU inference services because CUDA requires W+X (write-and-execute) memory for JIT compilation of GPU kernels. Applying this directive to CUDA-facing services will break inference. See Section 2.3.3 for details.
- Swap encryption: if swap is enabled, it must be encrypted. NixOS option: `boot.kernel.sysctl."vm.swappiness"` set low, or encrypted swap via `swapDevices` with `randomEncryption.enable = true`.
- No model telemetry: Ollama and any other runtime must be configured to disable phone-home, usage reporting, or crash telemetry that could leak ePHI. Set `OLLAMA_HOST=127.0.0.1` or the LAN interface only.
- GPU memory is not directly addressable by NixOS config; this is a known gap documented in Section 8.

#### 2.3.1 Model Context Window Persistence Risk

Inference runtimes (including Ollama) may maintain conversation context in memory or on disk between requests to support multi-turn conversations. If session context containing ePHI persists beyond the request lifecycle, this creates an ePHI retention problem that is distinct from the transient in-memory exposure during a single inference call.

**Risks:**
- Ollama and similar runtimes may cache conversation state in memory for session continuity, keeping ePHI resident longer than necessary.
- Some runtimes write session state to disk (e.g., KV cache files, conversation logs) which persists across service restarts.
- Context windows from prior requests containing ePHI from Patient A may still be in memory when a request about Patient B arrives, creating a cross-contamination risk if the application does not enforce session isolation.

**Mitigations:**
- Configure inference runtimes to disable persistent sessions or set aggressive session timeouts.
- Application-layer code must explicitly clear or rotate sessions after ePHI-bearing requests complete.
- Monitor inference runtime data directories for unexpected persistent files that may contain cached context.
- If multi-turn conversations involving ePHI are required, implement per-patient session isolation at the application layer.

#### 2.3.2 Core Dump Controls

Core dumps can write the entire memory contents of a process -- including any ePHI in inference buffers -- to disk. Core dumps must be disabled system-wide for systems processing ePHI.

```nix
{
  # Disable core dump storage by systemd
  systemd.coredump.extraConfig = "Storage=none";

  # Redirect core dumps to /bin/false at the kernel level
  boot.kernel.sysctl."kernel.core_pattern" = "|/bin/false";

  # Enforce zero core dump size via PAM limits for all users
  security.pam.loginLimits = [
    { domain = "*"; type = "hard"; item = "core"; value = "0"; }
  ];
}
```

#### 2.3.3 MemoryDenyWriteExecute and CUDA Incompatibility

`MemoryDenyWriteExecute=true` is a systemd hardening directive that prevents a process from creating memory mappings that are both writable and executable. This is an excellent security control for most services, as it blocks common exploitation techniques (e.g., shellcode injection, JIT spray attacks).

**However, this directive cannot be applied to services using CUDA/GPU inference.** CUDA's runtime compiler (NVRTC) and driver stack require W+X memory to JIT-compile PTX code into device-specific GPU instructions. Enabling `MemoryDenyWriteExecute=true` on a CUDA-facing service will cause inference to fail at runtime.

**Where to apply `MemoryDenyWriteExecute=true`:**
- `agent-runner` service (does not use CUDA directly)
- API proxy / application gateway (port 8000)
- Monitoring and alerting services
- Any non-GPU helper services

**Where NOT to apply it:**
- `ollama` service
- Any direct CUDA/GPU inference service
- Model loading or conversion utilities that invoke GPU operations

**This is a known security gap.** Compensating controls for services that cannot use `MemoryDenyWriteExecute`:
- Apply `SystemCallFilter` to restrict available syscalls to the minimum needed for inference.
- Use `RestrictAddressFamilies` to limit network access.
- Use `ProtectSystem=strict`, `PrivateTmp=true`, `NoNewPrivileges=true`, and `ProtectHome=true`.
- Apply seccomp filters via `SystemCallFilter=~@privileged @resources` (excluding calls needed by CUDA).
- Run the service in a separate network namespace if feasible.
- Monitor for anomalous process behavior with auditd.

### 2.4 Stage 4: Agent Actions

Agents running in `agent-sandbox` may take actions based on inference output: writing files, calling APIs, querying databases, or generating reports that contain or derive from ePHI.

**Controls required:**
- Sandboxed execution via systemd service hardening (see parent PRD, snippet 5).
- Tool allowlisting: agents must not have access to tools that can exfiltrate data (e.g., unrestricted `curl`, `wget`, `nc`). Enforced via `RestrictAddressFamilies`, `IPAddressDeny`, and `SystemCallFilter` in the systemd unit.
- Write path restriction: agent outputs limited to designated directories (`ReadWritePaths`).
- Human approval gates for high-risk actions (application-layer, not OS-level).
- Output content scanning before delivery to end users (application-layer).

### 2.5 Stage 5: Output Delivery

Inference results or agent outputs are returned to the requesting user or downstream system.

**Controls required:**
- TLS on the response path.
- Response logging with enough metadata for audit without storing the full ePHI payload in logs (see Section 5.3 for the logging design tension).
- Access control verification: the response must go only to the authenticated, authorized requestor.

### 2.6 Stage 6: Log Persistence

Audit logs, application logs, systemd journal entries, and AIDE reports may contain ePHI fragments (e.g., error messages that include prompt text, or audit entries that capture request metadata).

**Controls required:**
- Log storage on the encrypted volume.
- Log access restricted to the audit/security role, not to the service accounts or general users.
- Log retention and rotation policy enforced via `systemd.journal` configuration and application-level log rotation.
- Log integrity protection via append-only storage or forwarding to a remote syslog host.
- Redaction strategy: application-layer logging should scrub or tokenize ePHI before writing. The NixOS host cannot enforce this.

### 2.7 Stage 7: Inter-Process Communication

If agents or services communicate via Unix sockets, shared memory segments, D-Bus, or named pipes, those IPC channels carry ePHI in transit within the host. This is often overlooked because IPC does not traverse the network, but it is still ePHI in motion between processes.

**IPC channels in this system that may carry ePHI:**
- Unix domain sockets between the application API (port 8000) and Ollama (if configured for socket-based communication instead of HTTP loopback).
- Shared memory segments used by CUDA for host-to-GPU data transfer.
- Any message queue or pipe used between the agent-runner and inference services.
- D-Bus messages if systemd activation or service coordination involves ePHI-bearing payloads.

**Controls required:**
- Unix socket file permissions must restrict access to the communicating service users only (e.g., `chmod 0660` with group-based access control).
- Shared memory segments (`/dev/shm`) must be isolated per service via systemd `PrivateTmp=true` and `ProtectSystem=strict`. Consider `PrivateDevices=true` for non-GPU services to restrict `/dev/shm` access.
- Audit IPC endpoints: include socket paths and shared memory usage in the ePHI data flow inventory for risk analysis.
- D-Bus policy configuration should restrict which services can send and receive messages on system buses.

---

## 3. Administrative Safeguards -- 45 CFR Section 164.308

Administrative safeguards are primarily organizational and procedural. However, several have technical implementation components that the NixOS configuration directly supports or enables.

### 3.1 Security Management Process -- Section 164.308(a)(1)

#### 3.1.1 Risk Analysis (R)

**Requirement:** Conduct an accurate and thorough assessment of the potential risks and vulnerabilities to the confidentiality, integrity, and availability of ePHI held by the covered entity.

**NixOS implementation support:**
- The declarative flake configuration serves as a complete, reviewable inventory of the system's security posture. Every enabled service, open port, user account, and firewall rule is visible in the Nix code, enabling systematic risk identification.
- `nixos-rebuild dry-build` can diff a proposed configuration against the running system to identify changes that introduce new risk.
- The AIDE integrity baseline (`audit-and-aide` module) provides a mechanism to detect undocumented changes to the system between risk assessments.

**What cannot be solved by host config alone:** The risk analysis itself is a human-driven process requiring threat modeling, asset classification, and likelihood/impact assessment. The NixOS configuration provides the technical inventory; the analysis requires a documented procedure maintained outside the system. The risk analysis MUST address the live memory ePHI exposure documented in the Critical Risk section above.

#### 3.1.2 Risk Management (R)

**Requirement:** Implement security measures sufficient to reduce risks and vulnerabilities to a reasonable and appropriate level.

**NixOS implementation support:**
- Each flake module (`stig-baseline`, `lan-only-network`, `agent-sandbox`, etc.) is a discrete risk reduction measure that can be traced to specific risks identified in the analysis.
- NixOS generations and Git history provide an auditable trail of when risk reduction measures were implemented.

#### 3.1.3 Sanction Policy (R)

**Requirement:** Apply appropriate sanctions against workforce members who fail to comply with security policies.

**NixOS implementation support:** None. This is entirely an HR and organizational policy matter.

#### 3.1.4 Information System Activity Review (R)

**Requirement:** Regularly review records of information system activity, such as audit logs, access reports, and security incident tracking reports.

**NixOS implementation requirements:**
- `security.auditd.enable = true` with rules targeting ePHI-relevant events (file access to data directories, authentication events, privilege escalation).
- `services.journald.extraConfig` with `Storage=persistent` and `SystemMaxUse=` set to a value supporting the retention period (minimum 6 years for HIPAA, though the regulation does not specify a log retention period explicitly; 6 years applies to documentation of policies).
- The `audit-and-aide` module must produce reports suitable for periodic review.
- Concrete auditd rules for ePHI data paths:

```nix
{
  security.audit.rules = [
    # Watch ePHI data directories
    "-w /var/lib/ai-services/ -p rwxa -k ephi-data-access"
    "-w /var/lib/ollama/ -p rwxa -k model-data-access"
    "-w /var/lib/agent-runner/ -p rwxa -k agent-output-access"
    # Watch authentication databases
    "-w /etc/passwd -p wa -k identity-file-change"
    "-w /etc/shadow -p wa -k identity-file-change"
    "-w /etc/group -p wa -k identity-file-change"
    # Log all privileged commands
    "-a always,exit -F arch=b64 -S execve -F euid=0 -k privileged-exec"
    # Log all failed access attempts
    "-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EACCES -k access-denied"
    "-a always,exit -F arch=b64 -S open,openat,creat -F exit=-EPERM -k access-denied"
  ];
}
```

### 3.2 Assigned Security Responsibility -- Section 164.308(a)(2)

**Requirement (R):** Identify the security official responsible for developing and implementing security policies and procedures.

**NixOS implementation support:** The flake repository should include a `SECURITY.md` or equivalent file identifying the responsible individual. The NixOS configuration itself does not enforce this, but the Git repository is the natural location for this documentation.

### 3.3 Workforce Security -- Section 164.308(a)(3)

#### 3.3.1 Authorization and/or Supervision (A)

**Requirement:** Implement procedures for the authorization and/or supervision of workforce members who work with ePHI.

**NixOS implementation requirements:**
- User accounts defined declaratively in the flake with explicit group memberships.
- `users.users.<name>.extraGroups` controls which users can access which service data.
- No shared accounts; each operator has a named account.

```nix
{
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "audit" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };
  users.users.analyst = {
    isNormalUser = true;
    extraGroups = [ "ai-services" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };
}
```

#### 3.3.2 Workforce Clearance Procedure (A)

**Requirement:** Implement procedures to determine that the access of a workforce member to ePHI is appropriate.

**NixOS implementation support:** The declarative user/group model means access grants are code-reviewed via Git pull requests before they take effect. This provides a technical clearance gate but does not replace HR-level background checks or role authorization procedures.

#### 3.3.3 Termination Procedures (A)

**Requirement:** Implement procedures for terminating access to ePHI when employment ends or access is no longer required.

**NixOS implementation requirements:**
- Remove the user from the flake configuration and rebuild. Because NixOS is declarative, removing a user definition and running `nixos-rebuild switch` removes the account and its SSH keys atomically.
- Secrets managed via `sops-nix` should have the terminated user's age key removed from the `.sops.yaml` recipients list, followed by re-encryption of all secrets (`sops updatekeys`).

### 3.4 Information Access Management -- Section 164.308(a)(4)

#### 3.4.1 Isolating Healthcare Clearinghouse Functions (R)

**Requirement:** If a covered entity is a healthcare clearinghouse that is part of a larger organization, it must implement safeguards to protect ePHI from unauthorized access by the larger organization.

**NixOS implementation requirements (if applicable):**
- Network namespace isolation for services processing ePHI.
- Separate systemd service users with no shared group memberships with non-ePHI services.
- Firewall rules restricting inter-service communication to only authorized paths.

#### 3.4.2 Access Authorization (A)

**Requirement:** Implement policies and procedures for granting access to ePHI.

**NixOS implementation requirements:**
- POSIX file permissions on ePHI data directories enforced by the flake.
- `systemd.tmpfiles.rules` to set and maintain directory ownership and permissions:

```nix
{
  systemd.tmpfiles.rules = [
    "d /var/lib/ai-services 0750 ai-services ai-services -"
    "d /var/lib/ai-services/rag 0750 ai-services ai-services -"
    "d /var/lib/ai-services/outputs 0750 ai-services ai-services -"
    "d /var/lib/ollama 0750 ollama ollama -"
    "d /var/lib/agent-runner 0750 agent agent -"
    "d /var/log/ai-audit 0700 root audit -"
  ];
}
```

#### 3.4.3 Access Establishment and Modification (A)

**Requirement:** Implement policies and procedures that establish, document, review, and modify access to ePHI.

**NixOS implementation support:** Git history of the flake provides a complete record of every access change: when a user was added, when group memberships changed, when a firewall rule was modified. Each change is attributable to a Git author and timestamp.

### 3.5 Security Awareness and Training -- Section 164.308(a)(5)

#### 3.5.1 Security Reminders (A)

**NixOS implementation support:**
- Login banners via `services.openssh.banner` (see parent PRD snippet 3) can include HIPAA-relevant warnings.
- `programs.bash.interactiveShellInit` or `environment.etc."motd".text` can display security reminders at login:

```nix
{
  environment.etc."motd".text = ''
    NOTICE: This system may process electronic Protected Health Information (ePHI).
    All access is logged and audited. Unauthorized access is prohibited.
    Report security incidents to the designated Security Officer immediately.
  '';
}
```

#### 3.5.2 Protection from Malicious Software (A)

**NixOS implementation requirements:**
- NixOS's immutable `/nix/store` and declarative package management inherently resist unauthorized software installation.
- `nix.settings.allowed-users` restricts who can install packages.
- ClamAV can be enabled for scanning uploaded files or RAG documents: `services.clamav.daemon.enable = true; services.clamav.updater.enable = true;`.
- Agent sandboxes prevent agents from installing or executing arbitrary binaries.

#### 3.5.3 Log-in Monitoring (A)

**NixOS implementation requirements:**
- PAM configuration with `security.pam.services.sshd.showMotd = true`.
- Failed login tracking via auditd and `pam_tally2` or `pam_faillock`:

```nix
{
  security.pam.services.sshd.faillock = {
    enable = true;
    deny = 5;
    unlockTime = 900;
  };
}
```

#### 3.5.4 Password Management (A)

**NixOS implementation requirements:**
- SSH key-only authentication eliminates password management for remote access (see parent PRD snippet 1).
- For local console access (if enabled), password complexity can be enforced via PAM: `security.pam.services.login.pwquality.enable = true`.
- This is largely addressed by the key-only authentication policy.

### 3.6 Security Incident Procedures -- Section 164.308(a)(6)

#### 3.6.1 Response and Reporting (R)

**Requirement:** Identify and respond to suspected or known security incidents; mitigate, to the extent practicable, harmful effects of known security incidents; and document security incidents and their outcomes.

**NixOS implementation requirements:**
- AIDE hourly integrity checks detect unauthorized file modifications (see parent PRD snippet 4).
- Auditd rules (Section 3.1.4 above) generate the event stream for incident identification.
- Systemd journal preserved on encrypted storage for forensic analysis.
- NixOS generation history provides a timeline of system configuration changes.
- The `audit-and-aide` module should include an alerting mechanism (e.g., systemd service that sends alerts via a LAN-accessible notification endpoint when AIDE detects changes or auditd detects anomalous patterns).

**Flake implementation requirement:**

The AIDE alerting mechanism uses `OnFailure=` to trigger an alert service when the AIDE check exits with a non-zero status (indicating detected changes). This is the correct systemd pattern; `$SERVICE_RESULT` is NOT available in a separate unit's `ExecStart`, so the previous approach of checking `$SERVICE_RESULT` in a conditional was broken.

```nix
{
  # AIDE check service -- runs the integrity check
  systemd.services.aide-check = {
    description = "AIDE integrity check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --check";
    };
    # When aide-check fails (integrity violation detected), trigger the alert service
    unitConfig.OnFailure = "aide-alert.service";
  };

  # AIDE alert service -- triggered only on integrity violations
  systemd.services.aide-alert = {
    description = "AIDE integrity violation alerter";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "aide-alert" ''
        echo "AIDE integrity check failed at $(date)" | ${pkgs.mailutils}/bin/mail -s "AIDE ALERT" admin@localhost
        logger -p auth.crit "AIDE integrity check detected unauthorized changes"
      '';
    };
  };

  # Timer to run AIDE checks hourly
  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };
}
```

**What cannot be solved by host config alone:** Incident response playbooks, escalation procedures, communication plans, and post-incident reviews are organizational processes.

### 3.7 Contingency Plan -- Section 164.308(a)(7)

#### 3.7.1 Data Backup Plan (R)

**NixOS implementation requirements:**
- The NixOS configuration itself is backed up via the Git repository containing the flake.
- ePHI data directories (`/var/lib/ai-services/`, `/var/lib/ollama/`) must be backed up to encrypted storage. This can be implemented via `services.borgbackup.jobs`:

```nix
{
  services.borgbackup.jobs.ephi-backup = {
    paths = [
      "/var/lib/ai-services"
      "/var/lib/ollama"
      "/var/lib/agent-runner"
      "/var/log/ai-audit"
    ];
    repo = "/mnt/backup/ephi-borg";
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/secrets/borg-passphrase";
    };
    startAt = "daily";
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
  };
}
```

#### 3.7.2 Disaster Recovery Plan (R)

**NixOS implementation support:**
- NixOS's declarative model means the entire system can be rebuilt from the flake on new hardware: `nixos-install --flake .#ai-server`.
- The NixOS generation system allows rollback to any previous configuration: `nixos-rebuild switch --rollback`.
- Recovery procedure: (1) install NixOS on replacement hardware, (2) clone the flake repo, (3) restore ePHI data from BorgBackup, (4) rebuild.

#### 3.7.3 Emergency Mode Operation Plan (R)

**NixOS implementation requirements:**
- A minimal NixOS profile that provides essential ePHI access without the full AI stack. This could be a separate flake output:

```nix
{
  # In flake.nix
  nixosConfigurations.ai-server-emergency = nixpkgs.lib.nixosSystem {
    modules = [
      ./modules/stig-baseline
      ./modules/lan-only-network
      ./modules/audit-and-aide
      # AI services and agent sandbox deliberately excluded
    ];
  };
}
```

#### 3.7.4 Testing and Revision Procedures (A)

**NixOS implementation support:**
- `nixos-rebuild build-vm` creates a virtual machine from the configuration for testing.
- The flake's CI pipeline (if configured) can validate that the configuration builds and that key services start correctly.
- BorgBackup restores can be tested in the VM.

#### 3.7.5 Applications and Data Criticality Analysis (A)

**NixOS implementation support:** The modular flake structure (`stig-baseline`, `gpu-node`, `lan-only-network`, `audit-and-aide`, `agent-sandbox`, `ai-services`) naturally segments the system into components that can be ranked by criticality. This analysis must be performed and documented outside the configuration.

### 3.8 Evaluation -- Section 164.308(a)(8)

**Requirement (R):** Perform a periodic technical and nontechnical evaluation based initially upon standards implemented under the Security Rule and subsequently in response to environmental or operational changes.

**NixOS implementation support:**
- `nix flake check` validates the configuration.
- AIDE reports provide point-in-time integrity snapshots that can be compared across evaluation periods.
- `nixos-rebuild dry-build` diffs can show configuration drift between evaluations.
- The Git history of the flake provides a complete change log for the evaluation period.

---

## 4. Physical Safeguards -- 45 CFR Section 164.310

Physical safeguards are predominantly facility and hardware controls. The NixOS configuration has limited but meaningful touchpoints.

### 4.1 Facility Access Controls -- Section 164.310(a)(1)

#### 4.1.1 Contingency Operations (A)

**Requirement:** Establish and implement procedures that allow facility access in support of restoration of lost data under the disaster recovery plan.

**NixOS implementation support:** The disaster recovery plan (Section 3.7.2) reduces physical facility dependency because the system can be rebuilt on any compatible hardware from the flake and backup data.

#### 4.1.2 Facility Security Plan (A)

**NixOS implementation support:** None directly. This is a physical security matter. However, the LAN-only network design means the server's physical location on the local network is a security boundary; it must be documented.

#### 4.1.3 Access Control and Validation Procedures (A)

**NixOS implementation support:** None directly. Physical access logs and badge readers are outside the NixOS scope.

#### 4.1.4 Maintenance Records (A)

**NixOS implementation support:** NixOS generation history and Git log provide a record of all software maintenance. Physical hardware maintenance records must be maintained separately.

### 4.2 Workstation Use -- Section 164.310(b)

**Requirement (R):** Implement policies and procedures that specify the proper functions to be performed, the manner in which those functions are to be performed, and the physical attributes of the surroundings of a specific workstation that can access ePHI.

**NixOS implementation requirements:**
- The server itself is a workstation (repurposed workstation hardware). Its function is defined by the flake: inference, agent execution, and API serving.
- Console access (if enabled) should auto-lock. `services.logind.extraConfig` can enforce idle session handling:

```nix
{
  services.logind.extraConfig = ''
    IdleAction=lock
    IdleActionSec=600
  '';
}
```

### 4.3 Workstation Security -- Section 164.310(c)

**Requirement (R):** Implement physical safeguards for all workstations that access ePHI, to restrict access to authorized users.

**NixOS implementation requirements:**
- Full-disk encryption (LUKS) ensures that physical theft of the server does not expose ePHI data at rest. The boot configuration must require a passphrase or TPM-backed unlock. **Note:** LUKS protects data at rest only. It provides no protection for ePHI in memory on a running system. See the Critical Risk section at the top of this document.

```nix
{
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/XXXX-XXXX";
    preLVM = true;
    allowDiscards = true;  # if SSD; evaluate security tradeoff
  };
}
```

- BIOS/UEFI password is outside NixOS scope but must be set.
- USB port disabling can be enforced at the kernel level if required:

```nix
{
  boot.blacklistedKernelModules = [ "usb-storage" "firewire-core" ];
}
```

### 4.4 Device and Media Controls -- Section 164.310(d)(1)

#### 4.4.1 Disposal (R)

**Requirement:** Implement policies and procedures to address the final disposition of ePHI and the hardware or electronic media on which it is stored.

**NixOS implementation support:**
- LUKS encryption means secure disposal can be achieved by destroying the encryption key (cryptographic erasure).
- `nix-collect-garbage -d` removes old NixOS generations and their associated store paths, but this does not securely wipe the underlying blocks. Secure deletion requires `shred` or equivalent on the raw device.
- Model artifacts that were fine-tuned on ePHI must be treated as ePHI themselves for disposal purposes.

#### 4.4.2 Media Re-use (R)

**Requirement:** Implement procedures for removal of ePHI from electronic media before the media are made available for re-use.

**NixOS implementation requirements:** Same as disposal. LUKS cryptographic erasure is the primary mechanism. The flake should include a documented procedure for secure media wiping.

#### 4.4.3 Accountability (A)

**Requirement:** Maintain a record of the movements of hardware and electronic media and any person responsible therefor.

**NixOS implementation support:** None. This is a physical inventory and chain-of-custody process.

#### 4.4.4 Data Backup and Storage (A)

**Requirement:** Create a retrievable, exact copy of ePHI before movement of equipment.

**NixOS implementation support:** BorgBackup configuration (Section 3.7.1) provides this capability. The backup job should be triggered before any planned hardware maintenance.

---

## 5. Technical Safeguards -- 45 CFR Section 164.312

Technical safeguards are the core of what the NixOS configuration directly enforces. This section provides the most detailed implementation requirements.

### 5.1 Access Control -- Section 164.312(a)(1)

#### 5.1.1 Unique User Identification (R)

**Requirement:** Assign a unique name and/or number for identifying and tracking user identity.

**NixOS implementation requirements:**
- Every human operator must have a named user account in the flake. No shared accounts.
- Every service must have a dedicated system user. No service runs as `root` or as another service's user.
- The `users.users` and `users.groups` blocks in the flake are the authoritative source for identity:

```nix
{
  users.users = {
    admin = {
      uid = 1000;
      isNormalUser = true;
      extraGroups = [ "wheel" "audit" ];
      openssh.authorizedKeys.keys = [ /* unique key */ ];
    };
    # Service accounts
    ollama = {
      isSystemUser = true;
      group = "ollama";
      home = "/var/lib/ollama";
    };
    ai-services = {
      isSystemUser = true;
      group = "ai-services";
      home = "/var/lib/ai-services";
    };
    agent = {
      isSystemUser = true;
      group = "agent";
      home = "/var/lib/agent-runner";
    };
  };
  users.groups = {
    ollama = {};
    ai-services = {};
    agent = {};
    audit = {};
  };
}
```

- Application-layer APIs (port 8000) must implement their own user authentication mapping requests to identities. The NixOS host provides the OS-level identity; the application must extend this to API consumers.

#### 5.1.2 Emergency Access Procedure (R)

**Requirement:** Establish and implement procedures for obtaining necessary ePHI during an emergency.

**NixOS implementation requirements:**
- A documented emergency access account with a sealed credential (e.g., a break-glass SSH key stored in a physical safe or a separate encrypted medium).
- This account should be defined in the flake but with its key managed outside the normal secrets flow:

```nix
{
  users.users.emergency = {
    isNormalUser = true;
    extraGroups = [ "wheel" "ai-services" "ollama" ];
    openssh.authorizedKeys.keys = [ /* break-glass key */ ];
  };
}
```

- Every use of this account must trigger an alert. Auditd rules should flag logins by this user:

```nix
{
  security.audit.rules = [
    "-a always,exit -F arch=b64 -S execve -F auid=EMERGENCY_UID -k emergency-access"
  ];
}
```

- The emergency flake output (Section 3.7.3) provides a minimal operating mode.

#### 5.1.3 Automatic Logoff (A)

**Requirement:** Implement electronic procedures that terminate an electronic session after a predetermined time of inactivity.

**NixOS implementation requirements:**
- SSH idle timeout via the `stig-baseline` module:

```nix
{
  services.openssh.settings = {
    ClientAliveInterval = 300;
    ClientAliveCountMax = 0;  # disconnect after 300s idle
  };
}
```

- Console session timeout via shell configuration:

```nix
{
  programs.bash.interactiveShellInit = ''
    TMOUT=600
    readonly TMOUT
    export TMOUT
  '';
}
```

- API session timeouts must be implemented at the application layer (port 8000 service).

#### 5.1.4 Encryption and Decryption (A)

**Requirement:** Implement a mechanism to encrypt and decrypt ePHI.

**NixOS implementation requirements:**
- **At rest:** LUKS full-disk encryption (Section 4.3). This is the primary control and covers all data on the encrypted volume including model artifacts, RAG stores, agent outputs, and logs. **Note:** This does not cover ePHI in live memory. See the Critical Risk section.
- **Swap:** Must be encrypted.

```nix
{
  swapDevices = [
    {
      device = "/dev/disk/by-uuid/XXXX";
      randomEncryption.enable = true;
    }
  ];
}
```

- **Application-layer encryption:** For ePHI that must be encrypted at a finer granularity than the full disk (e.g., individual database fields, specific files), the application layer must implement field-level or file-level encryption. This is outside the NixOS host config scope.
- **Temporary files:** `PrivateTmp=true` in systemd units ensures each service has its own `/tmp`, and full-disk encryption covers the underlying storage.

### 5.2 Audit Controls -- Section 164.312(b)

**Requirement (R):** Implement hardware, software, and/or procedural mechanisms that record and examine activity in information systems that contain or use ePHI.

**NixOS implementation requirements:**

This is one of the most implementation-intensive HIPAA requirements for this system. The AI inference pipeline creates audit challenges because the "activity" includes prompt submission, context retrieval, inference, agent action, and output delivery.

- **OS-level audit:** `security.auditd.enable = true` with the rules specified in Section 3.1.4.
- **Systemd journal:** Persistent storage with defined retention:

```nix
{
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=10G
    SystemMaxFileSize=500M
    # NOTE: Canonical retention is 365day per prd.md Appendix A.5
    # The 26280h (~3yr) value here reflects HIPAA's conservative interpretation.
    # The implementation flake uses the resolved value from Appendix A.5.
    MaxRetentionSec=26280h
  '';
}
```

The `26280h` value equals approximately 3 years of journal retention. Adjust based on available storage and organizational policy. HIPAA requires retention of security documentation for 6 years (Section 164.530(j)); log retention should align with organizational policy.

- **Application-level audit:** The application API (port 8000) and Ollama wrapper must log:
  - Request timestamp, source IP, authenticated user identity
  - API endpoint called
  - Request size (not content, to avoid logging ePHI)
  - Response status code
  - Inference model used
  - Agent actions taken (tool name, target, outcome)
  - Approval gate decisions (approved/denied, by whom)

  This logging must be implemented in the application layer. The NixOS host provides the journal infrastructure and the auditd event stream.

- **Log protection:**

```nix
{
  # Restrict journal access to the audit group
  services.journald.extraConfig = ''
    SystemMaxUse=10G
  '';
  # Audit log directory permissions
  systemd.tmpfiles.rules = [
    "d /var/log/ai-audit 0700 root audit -"
    "d /var/log/audit 0700 root audit -"
  ];
}
```

### 5.3 Integrity -- Section 164.312(c)(1)

#### 5.3.1 Mechanism to Authenticate Electronic Protected Health Information (A)

**Requirement:** Implement electronic mechanisms to corroborate that ePHI has not been altered or destroyed in an unauthorized manner.

**NixOS implementation requirements:**
- **AIDE integrity monitoring** (parent PRD snippet 4) detects unauthorized changes to files on the system, including ePHI data stores if configured to monitor those paths.
- AIDE configuration must include ePHI data directories:

```nix
{
  environment.etc."aide.conf".text = ''
    database_in=file:/var/lib/aide/aide.db
    database_out=file:/var/lib/aide/aide.db.new
    /var/lib/ai-services R+sha512
    /var/lib/ollama/models R+sha512
    /etc R+sha512
    /boot R+sha512
  '';
}
```

  The `R+sha512` rule checks permissions, ownership, size, and SHA-512 hash. This detects unauthorized modification of ePHI data files and model artifacts.

- **NixOS store integrity:** The Nix store (`/nix/store`) is inherently content-addressed. Any modification to a store path changes its hash, making tampering detectable. This protects system binaries and configuration but not runtime data.

- **Backup integrity:** BorgBackup provides deduplication with integrity verification. `borg check` can verify backup integrity.

### 5.4 Person or Entity Authentication -- Section 164.312(d)

**Requirement (R):** Implement procedures to verify that a person or entity seeking access to ePHI is the one claimed.

**NixOS implementation requirements:**
- **SSH:** Key-based authentication (parent PRD snippet 1). Each user has a unique key pair. The public key in the flake is the identity binding.
- **MFA:** For environments where HIPAA risk analysis determines MFA is required:

```nix
{
  # Google Authenticator PAM module for SSH MFA
  security.pam.services.sshd.googleAuthenticator.enable = true;
  # Canonical SSH config per prd.md Appendix A.4
  services.openssh.settings.AuthenticationMethods = "publickey,keyboard-interactive";
}
```

  Alternatively, FIDO2/U2F keys can be used with OpenSSH 8.2+ (NixOS supports this natively via `ed25519-sk` or `ecdsa-sk` key types).

- **Service-to-service authentication:** Ollama (port 11434) does not natively support authentication. The application API (port 8000) must implement authentication and act as the authenticated gateway to Ollama. Ollama should be bound to `127.0.0.1` or the loopback interface only:

```nix
{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";  # Not exposed on LAN; accessed only via the authenticated API
    port = 11434;
  };
}
```

  The application API on port 8000 then proxies requests to Ollama after authenticating the caller. This is a critical architectural decision: Ollama must not be directly accessible from the LAN if it processes ePHI, because it has no authentication mechanism.

### 5.5 Transmission Security -- Section 164.312(e)(1)

#### 5.5.1 Integrity Controls (A)

**Requirement:** Implement security measures to ensure that electronically transmitted ePHI is not improperly modified without detection until disposed of.

**NixOS implementation requirements:**
- TLS on all API endpoints. The application API (port 8000) must terminate TLS:

```nix
{
  # Nginx as a TLS-terminating reverse proxy for the application API
  services.nginx = {
    enable = true;
    virtualHosts."ai-server.lan" = {
      forceSSL = true;
      sslCertificate = "/run/secrets/tls-cert";
      sslCertificateKey = "/run/secrets/tls-key";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
      };
      locations."/ollama/" = {
        proxyPass = "http://127.0.0.1:11434/";
      };
    };
  };
}
```

- TLS certificates should be managed via `security.acme` (if an internal CA is available) or via secrets management for internally-generated certificates.
- SSH already provides integrity via its encrypted transport.

#### 5.5.2 Encryption (A)

**Requirement:** Implement a mechanism to encrypt ePHI whenever deemed appropriate.

**NixOS implementation requirements:**
- TLS 1.2 or 1.3 for all HTTP-based API traffic (enforced by the Nginx configuration above).
- SSH for all administrative traffic.
- The LAN-only design reduces but does not eliminate the transmission encryption requirement. Even on a private LAN, ARP spoofing, rogue devices, or compromised switches could intercept unencrypted traffic. TLS is strongly recommended even in LAN-only deployments.
- Enforce minimum TLS version and use explicit AEAD cipher suites rather than cipher class strings. The `HIGH:!aNULL:!MD5:!RC4` shorthand includes ciphers that may not meet NIST SP 800-52 requirements (e.g., CBC-mode ciphers vulnerable to padding oracle attacks). Use explicit AEAD-only ciphers:

```nix
{
  services.nginx.commonHttpConfig = ''
    ssl_protocols TLSv1.2 TLSv1.3;
    # Canonical TLS ciphers per prd.md Appendix A.9
    ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
  '';
}
```

---

## 6. Organizational Requirements -- 45 CFR Section 164.314

### 6.1 Business Associate Agreements -- Section 164.314(a)(1)

**Requirement (R):** A covered entity must obtain satisfactory assurances from its business associates that they will appropriately safeguard ePHI.

**Applicability to this system:**

Because this is a LAN-only server running local inference, the BAA surface is significantly reduced compared to cloud-hosted AI services. However, BAAs may still be required for:

| Component | BAA Required? | Rationale |
|---|---|---|
| Ollama (local runtime) | No | Open-source software running locally. No data leaves the host. No business associate relationship exists with the Ollama project. |
| Model providers (Hugging Face, Meta, Mistral, etc.) | Generally no | Model weights are downloaded once and run locally. No ePHI is transmitted to the model provider during inference. However, if a model provider offers a cloud-based fine-tuning service and ePHI is used in training data, a BAA is required. |
| NixOS / Nixpkgs | No | Open-source infrastructure. No data relationship. |
| Hardware vendor | Possibly | If the hardware vendor provides on-site maintenance and could access the server while it contains ePHI, a BAA may be required for the maintenance relationship. |
| IPMI / Remote management vendors | Possibly | If the server has an IPMI, iLO, iDRAC, or similar baseboard management controller, the BMC vendor may have remote access capabilities that operate independently of the OS. If the BMC has network access and could theoretically expose ePHI (e.g., via KVM-over-IP, virtual media, or SOL console access), evaluate whether a BAA is needed. At minimum, the BMC must be on an isolated management VLAN with strong credentials. |
| Local contractors with system access | Yes, if accessing ePHI | Any individual contractor or consulting firm with administrative access to the system (SSH, physical console) who is not a workforce member of the covered entity requires a BAA. This includes IT support contractors, security assessors with access to live data, and system integrators. |
| Backup storage provider | Yes, if off-site | If BorgBackup targets are on a NAS or server managed by a third party, a BAA is required. If the backup target is locally managed hardware, no BAA is needed. |
| Network service providers | Possibly | If the LAN traverses infrastructure managed by a third party (e.g., managed switches, managed WiFi, ISP-provided equipment on the LAN segment), and that provider could access traffic containing ePHI, evaluate whether a BAA is required. Self-managed network equipment eliminates this concern. |
| VPN provider (if used for remote admin) | Possibly | If a third-party VPN service is used and could theoretically access traffic containing ePHI, evaluate whether a BAA is required. Self-hosted WireGuard eliminates this. |
| Cloud model APIs (if ever added) | Yes | If the architecture ever adds a cloud-based model API (OpenAI, Anthropic, etc.) that receives prompts containing ePHI, a BAA is required with that provider before any ePHI is transmitted. |

**Flake implementation requirement:** The `ai-services` module must enforce that Ollama and any other inference runtime are configured for local-only operation with no external API calls:

```nix
{
  # Ensure Ollama does not phone home
  systemd.services.ollama.environment = {
    OLLAMA_HOST = "127.0.0.1";
    OLLAMA_ORIGINS = "http://127.0.0.1:*";
  };
}
```

**Note:** `OLLAMA_NOPRUNE=1` was previously listed here as a security control. This flag controls whether Ollama automatically deletes unused model blobs during pulls -- it is a storage management flag, not a security measure. It does not prevent data exfiltration, disable telemetry, or enforce access control. It has been removed from the security configuration. If blob retention is desired for operational reasons, set it outside the security-relevant configuration block.

### 6.2 Requirements for Group Health Plans -- Section 164.314(b)

Not applicable to this system unless it is operated by a group health plan. No NixOS implementation required.

---

## 7. Breach Notification Rule -- 45 CFR Sections 164.400 through 164.414

### 7.1 Breach vs. Security Incident Definitions for This System

HIPAA distinguishes between a **security incident** and a **breach**. For this specific system, the following definitions apply:

**Security incident** (45 CFR Section 164.304): The attempted or successful unauthorized access, use, disclosure, modification, or destruction of information or interference with system operations in an information system. For this AI server, security incidents include:
- Failed SSH login attempts exceeding the lockout threshold
- AIDE integrity violations on any monitored path
- Auditd alerts for unauthorized file access to ePHI directories
- Firewall `BREACH-DETECT` log entries (attempted outbound traffic from service users)
- Unauthorized `sudo` or privilege escalation attempts
- Unexpected service restarts or crashes in ePHI-handling services

**Breach** (45 CFR Section 164.402): The acquisition, access, use, or disclosure of unsecured ePHI in a manner not permitted by the Privacy Rule which compromises the security or privacy of the ePHI. For this AI server, a breach specifically includes:
- Confirmed unauthorized access to files in `/var/lib/ai-services/`, `/var/lib/ollama/`, or `/var/lib/agent-runner/` by an unauthorized user or process
- Extraction of ePHI from system memory (e.g., via a memory dump, ptrace, or exploit)
- Exfiltration of inference results, prompts, or RAG context containing ePHI to an unauthorized destination
- Unauthorized access to logs containing ePHI fragments
- Compromise of the LUKS encryption key AND access to the encrypted volume
- A model fine-tuned on ePHI being copied to an unauthorized system
- An agent action that discloses ePHI to an unauthorized recipient (e.g., writing ePHI to an uncontrolled output path, sending ePHI via an unauthorized API call)

**Not a breach** (presumption applies per 45 CFR Section 164.402(1)):
- Unintentional acquisition by a workforce member acting in good faith and within scope of authority, provided the ePHI is not further used or disclosed improperly
- Inadvertent disclosure between persons authorized to access ePHI at the covered entity
- Unauthorized disclosure where the covered entity has a good faith belief that the unauthorized person would not have been able to retain the ePHI (e.g., encrypted data without the key)

Every security incident must be logged and reviewed. The four-factor breach risk assessment (Section 7.3) determines whether a security incident rises to the level of a reportable breach.

### 7.2 Detection Capabilities

The system must be able to detect potential breaches of unsecured ePHI. "Unsecured" means ePHI that is not rendered unusable, unreadable, or indecipherable to unauthorized persons through encryption or destruction.

**NixOS implementation requirements for breach detection:**

- **Unauthorized access detection:** Auditd rules (Section 3.1.4) detect unauthorized file access, failed authentication, and privilege escalation.
- **Data exfiltration detection:** Network monitoring for unusual outbound traffic. Since the system is LAN-only, any outbound Internet traffic is anomalous and should trigger an alert:

```nix
{
  # Block and log all outbound Internet traffic from AI services.
  # nftables per prd.md Appendix A.2 — per-UID egress filtering via
  # `meta skuid`, not iptables `--uid-owner` (which does not exist
  # in the nftables backend). Never use `networking.firewall.extraCommands`
  # with iptables syntax on NixOS 24.11+.
  networking.nftables.tables.per-uid-egress = {
    family = "inet";
    content = ''
      chain output-filter {
        type filter hook output priority 0; policy drop;
        ct state established,related accept
        oif lo accept

        # ollama: LAN-only outbound
        meta skuid ollama ip daddr 10.0.0.0/8 accept
        meta skuid ollama ip daddr 172.16.0.0/12 accept
        meta skuid ollama ip daddr 192.168.0.0/16 accept
        meta skuid ollama log prefix "BREACH-DETECT ollama: " drop

        # ai-services: LAN-only outbound
        meta skuid ai-services ip daddr 10.0.0.0/8 accept
        meta skuid ai-services ip daddr 172.16.0.0/12 accept
        meta skuid ai-services ip daddr 192.168.0.0/16 accept
        meta skuid ai-services log prefix "BREACH-DETECT ai-services: " drop

        # agent: LAN-only outbound
        meta skuid agent ip daddr 10.0.0.0/8 accept
        meta skuid agent ip daddr 172.16.0.0/12 accept
        meta skuid agent ip daddr 192.168.0.0/16 accept
        meta skuid agent log prefix "BREACH-DETECT agent: " drop
      }
    '';
  };
}
```

- **Integrity violation detection:** AIDE checks (parent PRD snippet 4) detect unauthorized modification of ePHI data.
- **Agent anomaly detection:** Application-layer logging of agent actions, with alerting on actions outside the expected behavioral envelope (e.g., an agent attempting to access files outside its `ReadWritePaths`, or invoking a tool not on the allowlist).
- **SSH intrusion detection:** Failed login monitoring and account lockout (Section 3.5.3).

### 7.3 Forensic Preservation

When a potential breach is detected, the system must preserve evidence for the breach risk assessment required by Section 164.402.

**NixOS implementation requirements:**

- **Log immutability:** Forward audit logs and journal entries to a remote syslog host in near-real-time so that an attacker who compromises the server cannot destroy the evidence. Log transmission MUST use TLS to comply with Section 164.312(e) -- transmitting audit logs containing potential ePHI fragments in cleartext is itself a transmission security violation:

```nix
{
  services.journald.extraConfig = ''
    ForwardToSyslog=yes
  '';
  services.rsyslogd = {
    enable = true;
    extraConfig = ''
      module(load="omrelp")
      action(type="omrelp" target="syslog.internal" port="2514"
             tls="on" tls.caCert="/var/lib/secrets/syslog-ca.pem"
             tls.myCert="/var/lib/secrets/syslog-client.pem"
             tls.myPrivKey="/var/lib/secrets/syslog-client-key.pem")
    '';
  };
}
```

  The RELP (Reliable Event Logging Protocol) transport with TLS ensures both encryption in transit and reliable delivery (no silent message loss on connection interruption, unlike plain TCP syslog). Certificate files must be managed via `sops-nix` and must not reside in the Nix store.

  Alternatively, use `services.vector` or `services.fluentbit` for structured log forwarding with TLS.

- **NixOS generation preservation:** Do not garbage-collect NixOS generations during a forensic investigation. The generation history shows the exact system configuration at any point in time.
- **Filesystem snapshots:** If the underlying storage supports snapshots (e.g., ZFS or Btrfs), take an immediate snapshot when a potential breach is detected. For ZFS:

```nix
{
  # ZFS snapshot capability (if using ZFS)
  boot.supportedFilesystems = [ "zfs" ];
  # Snapshot script triggered by breach detection
}
```

- **Memory preservation:** For advanced forensics, the system should support memory dumps. This is outside normal NixOS configuration but the `makedumpfile` and `crash` tools can be included:

```nix
{
  environment.systemPackages = with pkgs; [
    makedumpfile
    volatility3
  ];
}
```

### 7.4 Breach Risk Assessment Support

Section 164.402(2) requires a risk assessment considering four factors to determine if notification is required:
1. The nature and extent of the ePHI involved.
2. The unauthorized person who used the ePHI or to whom the disclosure was made.
3. Whether the ePHI was actually acquired or viewed.
4. The extent to which the risk to the ePHI has been mitigated.

**NixOS implementation support for each factor:**

| Factor | System capability |
|---|---|
| Nature and extent of ePHI | Application-layer logging must record what data was accessed (by reference, not by copying ePHI into logs). Auditd file-access rules show which files were touched. |
| Unauthorized person | Auditd and SSH logs identify the accessor. Failed login records show attempted access. The unique user ID requirement (Section 5.1.1) ensures attribution. |
| Whether ePHI was acquired or viewed | Auditd `read` vs `write` distinction on watched paths. Network logs showing data transfer volumes. Agent action logs showing what was retrieved. |
| Mitigation extent | LUKS encryption means stolen media containing ePHI is "secured" under the HITECH Act safe harbor (if the encryption key was not also compromised). **This safe harbor applies only to data at rest on the encrypted media, NOT to ePHI that was in live memory on a running system at the time of compromise.** Network containment via LAN-only firewall limits exfiltration paths. |

### 7.5 Notification Triggers

The system should generate alerts that map to breach notification triggers:

**Flake implementation requirement -- breach detection alerting service:**

The breach monitor uses `journalctl --follow` with `Restart=always` on the systemd service to ensure resilience. A bare `journalctl -f | grep` in a bash `while read` loop silently dies on pipe breaks (e.g., if journald rotates or restarts), and the monitoring gap would go undetected. The systemd watchdog provides automatic recovery.

```nix
{
  systemd.services.breach-monitor = {
    description = "HIPAA breach indicator monitoring";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      User = "root";
      ExecStart = pkgs.writeShellScript "breach-monitor" ''
        ${pkgs.systemd}/bin/journalctl --follow -t kernel --grep="BREACH-DETECT" | while read line; do
          echo "ALERT: Potential breach indicator at $(date): $line" >> /var/log/ai-audit/breach-alerts.log
          logger -p auth.crit "BREACH-DETECT: $line"
        done
      '';
      Restart = "always";
      RestartSec = "5s";
      WatchdogSec = "300s";
      # Ensure the service restarts even if journalctl exits cleanly (pipe break)
      SuccessExitStatus = "0 1 2";
    };
  };
}
```

**What cannot be solved by host config alone:**
- The 60-day notification deadline to individuals (Section 164.404).
- The notification to the Secretary of HHS (Section 164.408).
- The notification to media for breaches affecting more than 500 residents of a state (Section 164.406).
- The actual breach risk assessment decision.
- Maintaining the breach notification log required by Section 164.414 for breaches affecting fewer than 500 individuals (annual reporting).

These are organizational processes that must be documented in a Breach Notification Policy separate from the NixOS configuration.

### 7.6 Encryption Safe Harbor

Under 45 CFR Section 164.402(2) and the HHS Guidance on securing ePHI (74 FR 42740), ePHI that is encrypted in accordance with NIST Special Publication 800-111 (storage) or NIST Special Publication 800-52 (transmission) is considered "secured" and is exempt from breach notification requirements.

**NixOS implementation requirements to qualify for the safe harbor:**

- **At rest:** LUKS with AES-256. NixOS LUKS configuration should specify:

```nix
{
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/XXXX";
    preLVM = true;
    # LUKS2 with AES-256-XTS is the default for modern cryptsetup
    # Verify with: cryptsetup luksDump /dev/sdX
  };
}
```

- **In transit:** TLS 1.2+ with NIST-approved cipher suites (Section 5.5.2).
- **Key management:** The LUKS passphrase and TLS private keys must be protected. If the encryption key is compromised alongside the data, the safe harbor does not apply. Keys must be managed via `sops-nix`, not stored in the Nix store or Git repository.

**Critical limitation:** The encryption safe harbor applies ONLY to data at rest on encrypted media and data in transit over encrypted channels. It does NOT apply to ePHI resident in live memory during inference. See the Critical Risk section at the top of this document.

---

## 8. Privacy Rule Technical Requirements -- 45 CFR Section 164.500 et seq.

If this system processes ePHI, the Privacy Rule grants individuals specific rights regarding their data. While these rights are primarily administrative and procedural, the system must provide technical capabilities to support them.

### 8.1 Right of Access -- Section 164.524

**Requirement:** An individual has the right to inspect and obtain a copy of their ePHI in a designated record set.

**Applicability to this system:** If the AI system processes a patient's data (via prompts, RAG context, or agent actions), the patient may request access to know what data about them was processed and what outputs were generated.

**Technical implementation requirements:**
- Structured logging of all ePHI access with hashed patient identifiers. Each log entry should include: timestamp, hashed patient ID, data type accessed, service that accessed it, purpose/context.
- The application layer must maintain an index of which patient data was used in which inference requests, without storing the ePHI itself in the index (use hashed identifiers with a separate lookup capability).
- An API endpoint or administrative procedure to query all system interactions involving a specific patient's data within a requested time range.
- Responses to access requests must be provided within 30 days (with one 30-day extension if needed), per Section 164.524(b)(2).

### 8.2 Right of Amendment -- Section 164.526

**Requirement:** An individual has the right to request amendment of their ePHI in a designated record set.

**Applicability to this system:** If the RAG data store or any persistent data store contains ePHI that is inaccurate, the patient may request an amendment.

**Technical implementation requirements:**
- The application layer must support modification or annotation of RAG data to reflect amendments.
- Amendment requests and their outcomes must be logged with timestamps and the identity of the person processing the amendment.
- If an amendment is accepted, any cached or derived data (embeddings, summaries) based on the original ePHI should be regenerated or flagged.

### 8.3 Accounting of Disclosures -- Section 164.528

**Requirement:** An individual has the right to receive an accounting of disclosures of their ePHI made by the covered entity in the six years prior to the request.

**Applicability to this system:** If the AI system discloses ePHI -- even internally between system components -- an accounting must be maintained. For this system, "disclosures" include:
- Inference outputs containing ePHI delivered to an end user (the authorized requestor is typically exempt, but outputs shared beyond the requestor are disclosures).
- Agent actions that transmit or write ePHI to locations accessible by persons other than the requestor.
- Any data shared with external systems (if the LAN-only restriction is ever relaxed).
- Reports or summaries containing ePHI generated by the system and provided to third parties.

**Technical implementation requirements:**

```nix
{
  # Ensure the disclosure accounting log directory exists with proper permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/ai-services/disclosure-log 0750 ai-services audit -"
  ];
}
```

- The application layer must log each disclosure with: date, recipient, description of ePHI disclosed, and purpose.
- Disclosure logs must be retained for a minimum of 6 years from the date of disclosure.
- An API endpoint or administrative query capability must be provided to generate an accounting of disclosures for a specific patient (by hashed identifier) within a requested time range.
- Routine disclosures for treatment, payment, and health care operations are generally exempt from the accounting requirement, but the system should still log them for completeness.

---

## 9. Policies and Documentation Requirements -- 45 CFR Section 164.316

This is a Required standard that applies to all HIPAA safeguards. The covered entity must maintain written documentation of all policies, procedures, and actions required by the Security Rule.

### 9.1 Policies and Procedures -- Section 164.316(a)

**Requirement (R):** Implement reasonable and appropriate policies and procedures to comply with the standards, implementation specifications, and other requirements of the Security Rule. A covered entity may change its policies and procedures at any time, provided that the changes are documented and implemented in accordance with the Security Rule.

**NixOS implementation support:**
- The NixOS flake itself constitutes a machine-readable, version-controlled policy for the technical safeguards it implements. Each module (`stig-baseline`, `lan-only-network`, etc.) is a technical policy expressed as code.
- However, the flake does NOT replace written policies. Administrative and organizational policies (risk analysis procedures, incident response plans, sanctions, training requirements) must exist as separate documents.

**Required policy documents (stored in `/docs/policies/` within the flake repository):**

| Policy Document | HIPAA Reference | Description |
|---|---|---|
| Risk Analysis and Management Policy | 164.308(a)(1) | Procedures for conducting and updating the risk analysis |
| Workforce Security Policy | 164.308(a)(3) | Authorization, supervision, clearance, and termination procedures |
| Information Access Management Policy | 164.308(a)(4) | Procedures for granting, reviewing, and modifying access to ePHI |
| Security Awareness Training Policy | 164.308(a)(5) | Training program, frequency, and content requirements |
| Security Incident Response Policy | 164.308(a)(6) | Incident identification, response, mitigation, and documentation |
| Contingency Plan | 164.308(a)(7) | Backup, disaster recovery, emergency mode, and testing procedures |
| Evaluation Policy | 164.308(a)(8) | Periodic evaluation schedule and methodology |
| Facility Security Policy | 164.310(a) | Physical access controls and facility security plan |
| Device and Media Controls Policy | 164.310(d) | Disposal, re-use, accountability, and data backup procedures |
| Breach Notification Policy | 164.400-414 | Breach identification, risk assessment, notification procedures |

### 9.2 Documentation Requirements -- Section 164.316(b)(1)

**Requirement (R):** Maintain the policies and procedures implemented to comply with the Security Rule in written (which may be electronic) form. If an action, activity, or assessment is required by the Security Rule to be documented, maintain a written (which may be electronic) record of the action, activity, or assessment.

**Retention requirement:** Documentation must be retained for 6 years from the date of its creation or the date when it was last in effect, whichever is later.

**NixOS implementation requirements:**

```nix
{
  # Git-based documentation retention: configure the repository to retain
  # all policy documents with full history. The Git repository serves as
  # the documentation retention mechanism.
  #
  # Repository structure:
  # /docs/policies/          - All written HIPAA policies
  # /docs/risk-analysis/     - Risk analysis documents and updates
  # /docs/incident-reports/  - Security incident documentation
  # /docs/evaluations/       - Periodic evaluation records
  # /docs/training/          - Training materials and completion records
  # /docs/baa/               - Business associate agreements
  # /docs/breach-log/        - Breach notification log
}
```

- The Git repository containing the flake MUST retain full history for a minimum of 6 years. Configure repository retention policies accordingly. Do NOT use `git rebase`, `git filter-branch`, or force-push operations that destroy history on branches containing policy documents.
- Each policy document must include: effective date, last review date, version number, and approving authority.
- Git tags should mark significant policy revisions (e.g., `policy/v2.0-2026-01-15`).

### 9.3 Availability -- Section 164.316(b)(2)(i)

**Requirement (R):** Make documentation available to those persons responsible for implementing the procedures to which the documentation pertains.

**NixOS implementation support:**
- Policy documents in the Git repository are accessible to all workforce members with repository access.
- The login MOTD (Section 3.5.1) should reference where policies are located.
- Consider hosting rendered policy documents on an internal web server accessible via the LAN.

### 9.4 Updates -- Section 164.316(b)(2)(ii)

**Requirement (R):** Review documentation periodically and update as needed in response to environmental or operational changes that affect the security of ePHI.

**NixOS implementation support:**
- Establish a review cadence (at minimum annually, or after any significant system change).
- Git-based pull request workflow for policy updates ensures review and approval tracking.
- The periodic evaluation (Section 3.8) should include a policy review component.
- Maintain a policy review schedule in `/docs/policies/REVIEW-SCHEDULE.md` with assigned reviewers and due dates.

---

## 10. Nix Store Leakage Warning

The Nix store (`/nix/store`) is **world-readable** (`0444` for files, `0555` for directories). Any data that ends up in a Nix store path is accessible to every user and process on the system. Store paths are also persistent -- they survive `nixos-rebuild switch` until explicitly garbage-collected, and even then the underlying blocks are not securely wiped.

**This is a critical concern if secrets or ePHI-derived configuration end up in the store.**

Common ways secrets leak into the Nix store:
- Embedding secrets directly in Nix configuration expressions (e.g., passwords, API keys, TLS private keys in `services.nginx.virtualHosts.*.sslCertificateKey` pointing to a store path).
- Using `pkgs.writeText` or `builtins.toFile` with secret content -- these write to the store.
- Configuration files generated by NixOS modules that interpolate secrets (e.g., database connection strings with passwords).
- Scripts in `environment.systemPackages` or `systemd.services.*.serviceConfig.ExecStart` that contain hardcoded secrets.

**Mitigations (required):**
- Use `sops-nix` for all secrets management. It decrypts secrets at activation time into `/run/secrets/` (a tmpfs), keeping them out of the store entirely.
- Never reference secrets directly in Nix expressions. Always reference runtime secret paths (e.g., `/run/secrets/tls-key`).
- Audit the Nix store periodically for accidentally committed secrets: `nix-store --query --references /nix/store/*-nginx-*` and similar queries.
- If ePHI-derived data (e.g., patient-specific configuration, allow-lists with patient identifiers) is ever generated as part of the NixOS configuration, it MUST be handled as a runtime secret, not a build-time input.

---

## 11. Known Gaps and Limitations

The following HIPAA requirements cannot be fully addressed by NixOS host configuration alone. Each requires supplementary controls.

| Gap | HIPAA Reference | Required Supplementary Control |
|---|---|---|
| **Live memory ePHI exposure** | Section 164.312(a)(1), 164.402 | **Highest risk.** ePHI is unencrypted in RAM/VRAM during inference. LUKS does not protect live memory. Requires hardware memory encryption (AMD SEV-SNP / Intel TDX) or acceptance as residual risk with compensating controls. See Critical Risk section. |
| GPU VRAM isolation | Section 164.312(a)(1) | CUDA does not provide memory isolation between processes by default. If multiple services share the GPU, ePHI in VRAM could be accessed by another process. Mitigation: run only one inference service per GPU, or use NVIDIA MPS/MIG if supported. |
| MemoryDenyWriteExecute incompatibility with CUDA | Section 164.312(a)(1) | This systemd hardening directive cannot be applied to CUDA inference services. See Section 2.3.3 for compensating controls. |
| Application-layer authentication for APIs | Section 164.312(d) | Ollama has no built-in authentication. The application API must implement authentication and proxy all Ollama requests. |
| ePHI-aware logging (redaction) | Section 164.312(b) | Application-layer log redaction to prevent ePHI from appearing in logs. The OS cannot determine what constitutes ePHI in log content. |
| Minimum necessary enforcement | Section 164.502(b) | The Privacy Rule's minimum necessary standard requires that ePHI access be limited to what is needed for the purpose. For RAG retrieval, this means the application must filter retrieved documents, not return the entire corpus. This is purely application-layer logic. |
| Model artifact classification | Section 164.310(d)(1) | Models fine-tuned on ePHI may themselves constitute ePHI (via memorization or extraction attacks). There is no NixOS-level mechanism to classify a model artifact. Organizational policy must determine when a model is ePHI. |
| Model context window persistence | Section 164.312(a)(1) | Inference runtimes may retain conversation context in memory or on disk beyond request lifecycle. See Section 2.3.1. |
| Nix store world-readability | Section 164.312(a)(1) | Secrets or ePHI-derived config in `/nix/store` are world-readable and persistent. See Section 10 for mitigations. |
| De-identification | Section 164.514 | If ePHI is de-identified per the Safe Harbor or Expert Determination methods before being sent to the model, HIPAA no longer applies to that data. De-identification is an application-layer function, not an OS function. |
| Consent and authorization tracking | Section 164.508 | Patient authorization for use of ePHI in AI inference is a legal and application-layer concern. The NixOS host has no role here. |
| Privacy Rule individual rights | Section 164.524, 164.526, 164.528 | Right of access, amendment, and accounting of disclosures require application-layer support. See Section 8. |
| Training and awareness verification | Section 164.308(a)(5) | Workforce training completion tracking is an HR/organizational process. |
| Physical security | Section 164.310(a) | Facility access controls, visitor logs, and environmental controls are outside the OS scope. |
| Incident response playbooks | Section 164.308(a)(6) | Documented procedures for incident classification, escalation, and communication. |
| BAA execution and management | Section 164.314(a) | Contract management with any business associates. |
| IPC channel ePHI exposure | Section 164.312(e)(1) | Unix sockets, shared memory, and D-Bus channels carrying ePHI require access control. See Section 2.7. |

---

## 12. Implementation Priority Matrix

The following prioritization considers both HIPAA compliance impact and implementation complexity within the flake.

### Priority 1 -- Must have before any ePHI processing

| Control | Module | HIPAA Citation | Implementation |
|---|---|---|---|
| LUKS full-disk encryption | `stig-baseline` | 164.312(a)(2)(iv), 164.310(c) | `boot.initrd.luks.devices` configuration |
| Encrypted swap | `stig-baseline` | 164.312(a)(2)(iv) | `swapDevices.*.randomEncryption.enable` |
| Core dump disabling | `stig-baseline` | 164.312(a)(1) | `systemd.coredump.extraConfig`, `kernel.core_pattern`, PAM limits |
| Unique user accounts | `stig-baseline` | 164.312(a)(2)(i) | Declarative `users.users` with no shared accounts |
| SSH key-only, no root | `stig-baseline` | 164.312(d) | `services.openssh.settings` |
| LAN-only firewall | `lan-only-network` | 164.312(e)(1) | `networking.firewall` with interface-level rules |
| Auditd enabled | `audit-and-aide` | 164.312(b) | `security.auditd.enable` with ePHI-relevant rules |
| Ollama bound to localhost | `ai-services` | 164.312(d) | `services.ollama.host = "127.0.0.1"` |
| Service user isolation | `ai-services`, `agent-sandbox` | 164.312(a)(1) | Dedicated system users per service |
| Live memory risk documented | Documentation | 164.308(a)(1), 164.402 | Risk analysis acknowledging unencrypted ePHI in RAM/VRAM |
| Written policies created | `/docs/policies/` | 164.316(a) | All required policy documents in place |

### Priority 2 -- Required for ongoing compliance

| Control | Module | HIPAA Citation | Implementation |
|---|---|---|---|
| AIDE integrity monitoring | `audit-and-aide` | 164.312(c)(2) | AIDE with ePHI directory coverage |
| TLS on API endpoints | `ai-services` | 164.312(e)(2) | Nginx reverse proxy with TLS termination and AEAD ciphers |
| Agent sandbox hardening | `agent-sandbox` | 164.312(a)(1), 164.308(a)(3) | systemd `ProtectSystem`, `ReadWritePaths`, `RestrictAddressFamilies`, `MemoryDenyWriteExecute` (non-GPU services only) |
| Outbound traffic blocking for services | `lan-only-network` | 164.312(e)(1) | nftables per-UID egress rules (`meta skuid`) per service user |
| Persistent journal with retention | `audit-and-aide` | 164.312(b) | `services.journald.extraConfig` |
| BorgBackup for ePHI data | `stig-baseline` | 164.308(a)(7) | `services.borgbackup.jobs` with encryption |
| Account lockout on failed auth | `stig-baseline` | 164.312(d) | `security.pam.services.sshd.faillock` |
| Automatic session timeout | `stig-baseline` | 164.312(a)(2)(iii) | SSH `ClientAliveInterval`, shell `TMOUT` |
| TLS-encrypted syslog forwarding | `audit-and-aide` | 164.312(b), 164.312(e) | `services.rsyslogd` with RELP+TLS |
| Disclosure accounting logging | `ai-services` | 164.528 | Application-layer disclosure log with 6-year retention |
| Documentation retention | Git repository | 164.316(b)(1) | 6-year Git history retention for all policy documents |

### Priority 3 -- Strengthening and depth

| Control | Module | HIPAA Citation | Implementation |
|---|---|---|---|
| MFA for SSH | `stig-baseline` | 164.312(d) | `security.pam.services.sshd.googleAuthenticator` or FIDO2 |
| USB storage disabling | `stig-baseline` | 164.310(d)(1) | `boot.blacklistedKernelModules` |
| ClamAV for uploaded content | `ai-services` | 164.308(a)(5)(ii)(B) | `services.clamav.daemon.enable` |
| Emergency access account | `stig-baseline` | 164.312(a)(2)(ii) | Dedicated user with sealed credentials and audit alerting |
| Breach detection alerting | `audit-and-aide` | 164.400-414 | Kernel log monitoring for `BREACH-DETECT` prefix with watchdog |
| Emergency mode flake output | Top-level flake | 164.308(a)(7)(ii)(C) | Separate `nixosConfigurations` entry |
| IPC channel access control | `agent-sandbox` | 164.312(e)(1) | Socket permissions, shared memory isolation |
| Secrets management audit | `stig-baseline` | 164.312(a)(1) | Nix store leakage checks, sops-nix enforcement |

---

## 13. Compliance Evidence Generation

For each HIPAA audit or assessment, the NixOS system can generate the following evidence artifacts directly from the configuration and runtime state.

| Evidence Type | Generation Method | HIPAA Use |
|---|---|---|
| System configuration snapshot | `nixos-rebuild dry-build --flake .#ai-server 2>&1` and Git revision hash | Demonstrates the exact security configuration in effect at a point in time |
| User account inventory | `nix eval .#nixosConfigurations.ai-server.config.users.users --json` | Proves unique user identification and access authorization |
| Open port inventory | `nix eval .#nixosConfigurations.ai-server.config.networking.firewall --json` | Proves network access controls |
| Audit log sample | `journalctl --since "7 days ago" -u auditd` | Demonstrates audit control operation |
| AIDE integrity report | `/var/lib/aide/aide-report-YYYY-MM-DD.txt` | Demonstrates integrity controls |
| Backup verification | `borg list /mnt/backup/ephi-borg` and `borg check` output | Demonstrates contingency plan implementation |
| Generation history | `nix-env --list-generations --profile /nix/var/nix/profiles/system` | Demonstrates change management and rollback capability |
| Encryption verification | `cryptsetup luksDump /dev/sdX` | Demonstrates encryption at rest |
| Service isolation verification | `systemctl show agent-runner.service -p ProtectSystem,PrivateTmp,ReadWritePaths` | Demonstrates access controls on agent processes |
| Policy document inventory | `ls -la /docs/policies/` with Git log of last modification | Demonstrates Section 164.316 compliance |
| Disclosure accounting query | Application-layer API query for a specific patient's disclosures | Demonstrates Section 164.528 compliance |

---

## 14. Relationship to Other Compliance Frameworks

This HIPAA mapping shares significant control overlap with the STIG baseline and NIST controls already addressed in the parent PRD. The following cross-references avoid duplication while ensuring coverage.

| HIPAA Safeguard | STIG/NIST Equivalent | Shared NixOS Control |
|---|---|---|
| Access Control 164.312(a) | NIST AC-2, AC-3, AC-6; STIG V-ID user/group findings | Declarative `users.users`, `users.groups`, SSH config |
| Audit Controls 164.312(b) | NIST AU-2, AU-3, AU-6, AU-9; STIG auditd findings | `security.auditd`, `services.journald` |
| Integrity 164.312(c) | NIST SI-7; STIG AIDE findings | AIDE configuration and timers |
| Transmission Security 164.312(e) | NIST SC-8, SC-13; STIG TLS/SSH findings | Nginx TLS, SSH hardening |
| Contingency Plan 164.308(a)(7) | NIST CP-9, CP-10 | BorgBackup, NixOS generation rollback |

The HIPAA-specific additions beyond what STIG/NIST already require for this system are:
1. ePHI data flow analysis and per-stage controls (Section 2 of this document), including IPC channels and context window persistence.
2. BAA analysis for model providers, supporting services, contractors, and remote management vendors (Section 6.1).
3. Breach notification detection and forensic preservation capabilities (Section 7), including breach vs. incident definitions.
4. Encryption safe harbor qualification and its limitations for live memory (Section 7.6).
5. Application-layer gaps that the OS cannot address (Section 11).
6. Privacy Rule individual rights (Section 8): access, amendment, and accounting of disclosures.
7. Policies and documentation retention requirements (Section 9).
8. Live memory ePHI exposure as the primary residual risk (Critical Risk section).
9. Nix store leakage risks and mitigations (Section 10).
