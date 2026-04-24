# PRD Module: HITRUST CSF v11 Control Mapping

## Overview

This module extends the base PRD for the Control-Mapped NixOS AI Agentic Server by providing a comprehensive mapping to the HITRUST Common Security Framework (CSF) version 11. HITRUST CSF is a certifiable framework that incorporates requirements from HIPAA, NIST 800-53, ISO 27001/27002, PCI DSS v4.0, COBIT, and other authoritative sources into a single prescriptive control set.

Unlike NIST SP 800-53, which offers flexible control descriptions and expects organizations to define their own implementation parameters, HITRUST CSF is **prescriptive**: it specifies exact password lengths, encryption algorithm requirements, scan frequencies, retention periods, and configuration thresholds. The NixOS flake configuration must meet these prescriptive thresholds directly in code, making declarative NixOS configuration a natural fit for demonstrable HITRUST compliance.

This document targets **HITRUST CSF v11** and is structured around the **19 HITRUST control domains** (numbered 00-18). Each domain section maps HITRUST control references to specific NixOS options, runtime controls, or procedural requirements, and specifies implementation level targets for i1 (readiness) and r2 (validated) assessment paths.

> **MyCSF Traceability Note**: Throughout this document, HITRUST control references use the CSF v11 domain/control numbering scheme. During formal assessment, each technical control should be traced to specific MyCSF requirement statement IDs (format: e.g., "19748v2"). The implementation team should use the MyCSF portal to map these controls to their exact requirement statement IDs once the assessment scope is finalized.

> **Alternate Controls**: Where prescriptive HITRUST requirements cannot be met exactly as specified (e.g., wireless security on a wired-only host), HITRUST uses the term **"alternate controls"** (not "compensating controls," which is PCI DSS terminology). Sections that rely on alternate control justifications are marked accordingly. Alternate control requests must be formally submitted through the MyCSF portal during assessment.

> **Threat-Adaptive Controls (CSF v11)**: HITRUST CSF v11 introduced a threat-adaptive control selection model for i1 assessments. The i1 control set is periodically updated based on the **HITRUST Threat Catalogue**, which tracks current threat intelligence to ensure the 219 i1 requirement statements address the most relevant threats. Organizations should review the current Threat Catalogue during assessment preparation to ensure no newly added controls are missed.

---

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the HITRUST-specific rationale; the implementation flake uses only the canonical values.

## HITRUST Assessment Methodology

### Assessment Types and This Configuration's Role

HITRUST offers three assessment types:

| Assessment | Purpose | This System's Target |
|---|---|---|
| **e1 (Essentials)** | Basic cyber hygiene, 44 requirement statements | Fully met by flake config + operational procedures |
| **i1 (Implemented)** | Threat-adaptive, 219 requirement statements | Primary target; all technical controls implemented in Nix |
| **r2 (Risk-based)** | Full validated assessment, 2000+ requirement statements across scoped controls | Stretch target; requires external assessor, policy documentation, and operational evidence beyond host config |

### How the Flake Supports Each Assessment Tier

**e1 support**: The flake's `stig-baseline`, `lan-only-network`, and `audit-and-aide` modules directly implement the 44 essential security practices. A `nixos-rebuild` to the committed flake configuration constitutes evidence of implementation.

**i1 support**: The full module set (`stig-baseline`, `gpu-node`, `lan-only-network`, `audit-and-aide`, `agent-sandbox`, `ai-services`) covers all 219 i1 requirement statements that have technical implementation components. The declarative nature of NixOS means configuration IS documentation IS evidence. Note: The i1 control set is informed by the HITRUST Threat Catalogue and may be updated between assessment cycles. Review the current Threat Catalogue during preparation.

**r2 support**: The flake provides the technical implementation layer. r2 additionally requires:
- Formal policies (documented outside the flake, referenced in `/docs/policies/`)
- Procedures (runbooks, incident response plans)
- Evidence of operation over time (log archives, scan results, review records)
- External assessor validation

### HITRUST Maturity Model Mapping

HITRUST scores each control across five maturity levels. The NixOS flake addresses them as follows:

| Maturity Level | HITRUST Definition | NixOS Flake Contribution |
|---|---|---|
| **1 - Policy** | A formal policy exists | Flake comments and module documentation serve as machine-readable policy; formal policy documents must supplement |
| **2 - Procedure** | Documented procedures exist | NixOS module structure IS the procedure; `nixos-rebuild` is the execution procedure |
| **3 - Implemented** | Controls are deployed and operating | `nixos-rebuild switch` deploys all controls atomically; flake lock pins exact versions |
| **4 - Measured** | Controls are monitored with defined metrics, regular measurement, and reporting to management | Requires: defined KPIs per control, quarterly metric reports, management review evidence, trend analysis over time. Technical hooks: `audit-and-aide` provides raw data, but measurement requires documented metrics program and reporting cadence |
| **5 - Managed** | Controls are continuously improved based on measurement data over multiple review cycles | Requires: multiple review cycles of measurement data, documented improvement actions driven by metrics, evidence of control optimization over time. This level is NOT achievable in Year 1 for any domain |

**Maturity scoring constraints**:
- **Year 1 target**: Level 3 (Implemented) for all in-scope domains. Level 3 means controls are deployed and operating as intended.
- **Year 2 target**: Level 4 (Measured) for priority domains, requiring at least 4 quarters of metric collection, documented management reviews, and trend reporting.
- **Level 5 (Managed)** requires evidence of continuous improvement driven by measurement data across multiple review cycles. Realistically achievable no earlier than Year 3 for mature domains.
- Having auditd running is Level 3 (Implemented). Having quarterly metric reports with tuning evidence reviewed by management is Level 4 (Measured). Level 5 requires demonstrated improvement actions based on that measurement data over multiple cycles.

---

## Domain 00: Information Security Management Program

### HITRUST Control References
- 0.a Information Security Management Program

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Document an information security program | Flake repository structure with named modules (`stig-baseline`, `audit-and-aide`, etc.) constitutes the technical security program. Supplement with `/docs/policies/information-security-policy.md` |
| **2** | Program includes risk management integration and resource allocation | AIDE drift detection + automated compliance scanning integrated into rebuild pipeline; document resource allocation |
| **3** | Program is fully operational with regular reviews | Annual review via Git tags (`hitrust-review-YYYY`); quarterly evidence collection automated |

### NixOS Configuration Mapping

The flake structure itself is the information security management program artifact:

```
flake.nix
├── modules/stig-baseline/      # OS hardening controls
├── modules/gpu-node/            # Hardware-specific security
├── modules/lan-only-network/    # Network boundary controls
├── modules/audit-and-aide/      # Monitoring and integrity
├── modules/agent-sandbox/       # AI-specific isolation
├── modules/ai-services/         # Service-layer controls
└── docs/policies/               # Supplemental policy documents
```

### Evidence Artifacts for r2 Assessment
- Git repository with signed commits showing configuration history
- Module-level documentation in each NixOS module file
- Annual review records (Git tags: `hitrust-review-YYYY`)
- Information security management program charter document

### Cross-References
- NIST SP 800-53: PM-1 (Information Security Program Plan)
- HIPAA: 164.308(a)(1) Security Management Process
- PCI DSS v4.0: Requirement 12.1 (Information Security Policy)
- ISO 27001: A.5.1 (Policies for information security)

---

## Domain 01: Access Control

### HITRUST Control References
- 01.a Access Control Policy
- 01.b User Registration
- 01.c Privilege Management
- 01.d User Password Management
- 01.e Review of User Access Rights
- 01.f Password Use
- 01.g Unattended User Equipment
- 01.h Clear Desk and Clear Screen Policy
- 01.i Policy on the Use of Network Services
- 01.j Network Access Control
- 01.k Network Routing Control
- 01.l Operating System Access Control
- 01.n Network Connection Control
- 01.r Password Management System
- 01.s Session Time-out
- 01.v Information Access Restriction
- 01.x Mobile Computing and Communications
- 01.y Teleworking

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Role-based access; unique user IDs; session timeouts; minimum 8-character passwords | Named user accounts; group-based permissions; SSH/shell timeouts; PAM configuration |
| **2** | Least privilege enforced; access reviews quarterly; MFA for privileged access; 15-character passwords; password history of 24 | Per-service users; systemd sandboxing; quarterly Git-based access audit; enhanced PAM settings |
| **3** | Just-in-time access; automated provisioning/deprovisioning; continuous access monitoring | Dynamic sudo grants; agent approval gates; auditd real-time monitoring |

### NixOS Configuration Mapping

#### User and Role Management

```nix
# Access control - stig-baseline module + agent-sandbox module
{
  # Named user accounts with role separation
  users.users.admin = {
    isNormalUser = true;
    description = "System administrator";
    extraGroups = [ "wheel" "systemd-journal" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... admin@workstation"
    ];
  };

  users.users.ai-operator = {
    isNormalUser = true;
    description = "AI services operator";
    extraGroups = [ "ai-services" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAA... operator@workstation"
    ];
  };

  # Service accounts (non-login, least privilege)
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    home = "/var/lib/ollama";
    shell = pkgs.shadow + "/bin/nologin";
  };

  users.users.agent = {
    isSystemUser = true;
    group = "agent";
    home = "/var/lib/agent-runner";
    shell = pkgs.shadow + "/bin/nologin";
  };

  # Sudo restricted to wheel group with logging
  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    execWheelOnly = true;
    extraConfig = ''
      Defaults  logfile="/var/log/sudo.log"
      Defaults  log_input, log_output
      Defaults  timestamp_timeout=5
      Defaults  passwd_tries=3
    '';
  };

  # Session timeout (HITRUST prescriptive: 15 minutes for Level 2)
  programs.bash.interactiveShellInit = ''
    export TMOUT=900  # 15-minute idle timeout
    readonly TMOUT
  '';

  services.openssh.settings = {
    ClientAliveInterval = 300;     # Check every 5 minutes
    ClientAliveCountMax = 3;       # Disconnect after 15 minutes idle
  };

  # Agent access control - tool allowlisting
  # Agents cannot execute arbitrary commands; only allowlisted tools
  systemd.services.agent-runner.serviceConfig = {
    User = "agent";
    Group = "agent";
    NoNewPrivileges = true;
    PrivateTmp = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectControlGroups = true;
    ProtectKernelLogs = true;
    ProtectHostname = true;
    ProtectClock = true;
    LockPersonality = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    MemoryDenyWriteExecute = true;
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
      "~@resources"
    ];
    SystemCallArchitectures = "native";
    ReadWritePaths = [ "/var/lib/agent-runner" ];
    ReadOnlyPaths = [ "/var/lib/ollama/models" ];
  };
}
```

#### Password Management

```nix
# Password management - stig-baseline module
{
  # HITRUST prescriptive password requirements using PAM text override
  # Note: security.pam.services.<name>.rules hierarchy does not match NixOS
  # options directly; use .text override for precise control.
  security.pam.services.passwd = {
    text = lib.mkDefault ''
      password required pam_pwhistory.so remember=24 use_authtok
      password requisite pam_pwquality.so retry=3 minlen=15 dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1
      password required pam_unix.so shadow use_authtok
    '';
  };

  security.pam.services.login = {
    text = lib.mkDefault ''
      # Authentication with account lockout
      auth required pam_faillock.so preauth deny=5 unlock_time=1800 fail_interval=900 audit
      auth required pam_unix.so
      auth required pam_faillock.so authfail deny=5 unlock_time=1800 fail_interval=900 audit

      # Account
      account required pam_unix.so

      # Password with history, quality, and storage
      password required pam_pwhistory.so remember=24 use_authtok
      password requisite pam_pwquality.so retry=3 minlen=15 dcredit=-1 ucredit=-1 lcredit=-1 ocredit=-1
      password required pam_unix.so shadow use_authtok

      # Session
      session required pam_unix.so
      session required pam_limits.so
    '';
  };

  # Password aging (HITRUST prescriptive thresholds)
  environment.etc."login.defs".text = ''
    PASS_MAX_DAYS   365
    PASS_MIN_DAYS   1
    PASS_MIN_LEN    15
    PASS_WARN_AGE   14
    LOGIN_RETRIES   3
    LOGIN_TIMEOUT   60
    ENCRYPT_METHOD  SHA512
    SHA_CRYPT_ROUNDS 65536
  '';

  # SSH key-only authentication (strongest control - eliminates password attack surface)
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    # DEPRECATED: ChallengeResponseAuthentication removed in OpenSSH 8.7+
    # Use KbdInteractiveAuthentication only (see prd.md Appendix A.4)
  };
}
```

HITRUST prescriptive password requirements (all explicit, unlike NIST flexibility):

| Parameter | HITRUST Level 1 | HITRUST Level 2 | This Config |
|---|---|---|---|
| Minimum length | 8 characters | 15 characters | 15 characters |
| Complexity | 3 of 4 categories | All 4 categories | All 4 required |
| Maximum age | 90 days | 365 days | 365 days |
| History | 6 passwords | 24 passwords | 24 (via pam_pwhistory, configured in PAM text) |
| Lockout threshold | 10 attempts | 5 attempts | 5 attempts |
| Lockout duration | 15 minutes | 30 minutes | 30 minutes |
| Hash algorithm | Not specified | SHA-512 or stronger | SHA-512 (65536 rounds) |

HITRUST prescriptive access control thresholds:

| Control | HITRUST Requirement | NixOS Implementation |
|---|---|---|
| Session timeout | 15 minutes maximum idle | `TMOUT=900` + SSH `ClientAliveInterval` |
| Privilege escalation | Logged and audited | `sudo` with `log_input, log_output` |
| Service accounts | No interactive login | `shell = nologin` for all service users |
| Access reviews | Quarterly minimum | Git-tracked user list; scheduled review reminders |
| Failed login lockout | 5 attempts, 30-minute lock | PAM `faillock` configuration |

**Key HITRUST differentiator vs. NIST**: NIST SP 800-63B recommends **against** complexity requirements and periodic rotation, favoring length and breach checking. HITRUST **still requires** complexity and rotation. The NixOS config must satisfy HITRUST's more prescriptive stance, even where NIST has moved away from these controls.

#### Mobile Device and Teleworking (01.x, 01.y)

This sub-domain is **N/A (Not Applicable)** for a LAN-only GPU inference server. The server itself is not a mobile device, and its services are restricted to the local network. No mobile-specific APIs are exposed.

**Alternate control justification**: LAN-only enforcement means any client device must be on the trusted network to access services. No remote/mobile access paths exist. This is documented as a scoping exclusion, not scored at a maturity level.

```nix
# LAN-only enforcement means mobile devices must be on the trusted network
{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];  # No ports open on non-LAN interfaces
    interfaces.enp3s0.allowedTCPPorts = [ 22 11434 8000 ];
  };
}
```

### Evidence Artifacts for r2 Assessment
- `getent passwd` output showing all user accounts and shells
- `getent group` output showing group memberships
- `/var/log/sudo.log` samples showing privileged access audit trail
- SSH authorized_keys inventory per user
- systemd service unit files showing sandboxing parameters for each service
- Agent tool allowlist configuration
- Quarterly access review records (dated, with reviewer notation)
- Session timeout test evidence (idle session disconnect after 15 minutes)
- PAM configuration output showing pwquality, pwhistory, and faillock settings
- `/etc/login.defs` showing password aging parameters
- `/etc/shadow` hashing algorithm verification (SHA-512 prefix `$6$`)
- SSH configuration showing password authentication disabled
- Account lockout test results (5 failed attempts trigger 30-minute lock)
- Password history enforcement test results
- Scoping document explaining mobile device sub-domain non-applicability

### Cross-References
- NIST SP 800-53: AC-2 (Account Management), AC-3 (Access Enforcement), AC-6 (Least Privilege), AC-7 (Unsuccessful Logon Attempts), AC-11 (Device Lock), AC-12 (Session Termination), AC-19 (Access Control for Mobile Devices), IA-5 (Authenticator Management)
- HIPAA: 164.312(a)(1) Access Control, 164.312(d) Person or Entity Authentication, 164.310(b) Workstation Use
- PCI DSS v4.0: Requirement 7 (Restrict Access by Business Need), Requirement 8 (Identify Users and Authenticate Access)
- ISO 27001: A.9.1-A.9.4 (Access control), A.6.2 (Mobile devices and teleworking)

---

## Domain 02: Human Resources Security

### HITRUST Control References
- 02.a Management Commitment to Information Security
- 02.b Information Security Coordination
- 02.c Allocation of Information Security Responsibilities
- 02.d Management Responsibilities
- 02.e Information Security Awareness, Education, and Training

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Security roles assigned; basic awareness training annually | Define `security.adminEmail` in flake config; login banners for awareness reinforcement |
| **2** | Pre-employment screening; role-based training; training before system access; termination procedures | Procedural: training completion gates, HR process documentation |
| **3** | Continuous awareness program; training effectiveness measurement | Procedural: outside scope of host config |

This domain is **primarily organizational/procedural**. The NixOS host configuration contributes awareness reinforcement mechanisms but cannot implement HR processes.

### NixOS Configuration Mapping (Awareness Reinforcement)

```nix
# Education and awareness - stig-baseline module
{
  # Login banner serving as continuous awareness reinforcement
  services.openssh.banner = ''
    ================================================================
    AUTHORIZED USERS ONLY - All activity is monitored and logged.
    This system processes sensitive data subject to security controls.
    Unauthorized access or misuse is prohibited and may result in
    disciplinary or legal action. By continuing, you acknowledge
    your security training obligations and data handling responsibilities.
    ================================================================
  '';

  # MOTD with security reminders and policy references
  environment.etc."motd".text = ''
    === Security Reminders ===
    - Report suspicious activity to the security team immediately
    - Do not share credentials or SSH keys
    - Agent outputs may contain sensitive data - handle accordingly
    - Review security policies at: /docs/policies/
    - Last security training must be within 365 days

    System: NixOS AI Agentic Server (HITRUST-scoped)
    Contact: Security Administrator
  '';  # NixOS does not have users.motd; use environment.etc

  # Console banner for local sessions
  environment.etc."issue".text = ''
    WARNING: This system is for authorized users only.
    All sessions are monitored and logged.
  '';
}
```

### Required Organizational Processes (Outside Flake)

The following must be documented in `/docs/policies/` and maintained as organizational processes:

- **Pre-employment screening**: Background checks appropriate to role sensitivity
- **Security responsibilities in job descriptions**: All roles with system access must have security responsibilities documented
- **Termination/transfer procedures**: SSH key revocation, account disablement, access review upon role change. NixOS supports this via Git-tracked user configuration -- removing a user's SSH key and running `nixos-rebuild switch` atomically revokes access
- **Annual security awareness training program** with completion records
- **Role-specific training** for AI operators (prompt injection risks, model handling, data sensitivity)
- **Training records** with dates and acknowledgments
- **Security responsibility assignment matrix** (RACI)

### Evidence Artifacts for r2 Assessment
- SSH banner and MOTD configuration showing awareness messaging
- Training program documentation and curriculum
- Training completion records per user with dates
- Role-specific training materials for AI system operators
- Security awareness acknowledgment forms (signed)
- Pre-employment screening procedure documentation
- Termination checklist showing access revocation steps
- Organizational chart mapping security responsibilities
- Git history showing user account additions/removals tied to HR events

### Cross-References
- NIST SP 800-53: AT-1 (Security Awareness and Training Policy), AT-2 (Security Awareness Training), AT-3 (Role-Based Security Training), PS-1 through PS-8 (Personnel Security)
- HIPAA: 164.308(a)(3) Workforce Security, 164.308(a)(5) Security Awareness and Training
- PCI DSS v4.0: Requirement 12.6 (Security awareness program), Requirement 12.7 (Personnel screening)
- ISO 27001: A.7.1-A.7.3 (Human resource security)

---

## Domain 03: Risk Management

### HITRUST Control References
- 03.a Risk Management Program
- 03.b Performing Risk Assessments
- 03.c Risk Mitigation
- 03.d Risk Evaluation

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Risk assessment performed; risks identified and documented | Technical risk data from vulnix scans and AIDE reports feeds risk register |
| **2** | Annual risk assessments; risk register maintained; risk treatment plans documented | Automated vulnerability data provides technical evidence; risk register maintained in `/docs/policies/risk-register.md` |
| **3** | Continuous risk monitoring; risk-based decision making integrated into operations | vulnix + AIDE + auditd provide continuous technical risk signals; operational integration requires process |

This domain is **primarily organizational** with technical evidence hooks. The NixOS host configuration provides risk-relevant technical data but cannot perform risk assessment, maintain a risk register, or execute risk treatment decisions.

### Technical Evidence Hooks

```nix
# Risk management evidence sources - audit-and-aide module
{
  # vulnix provides vulnerability risk data (see Domain 10 for full config)
  # AIDE provides integrity/drift risk data (see Domain 09 for full config)
  # auditd provides security event risk data (see Domain 09 for full config)

  # These technical signals feed the organizational risk management process:
  # - vulnix scan results -> input to risk register for software vulnerability risks
  # - AIDE drift reports -> input to risk register for configuration integrity risks
  # - auditd anomaly events -> input to risk register for operational security risks
}
```

### Required Organizational Processes (Outside Flake)

- **Risk assessment methodology**: Document the approach (e.g., HITRUST-aligned, using likelihood x impact scoring)
- **Annual risk assessment**: Formal assessment at least annually, more frequently for significant changes
- **Risk register**: Maintained in `/docs/policies/risk-register.md` with:
  - Risk ID, description, likelihood, impact, risk score
  - Risk owner, treatment decision (accept/mitigate/transfer/avoid)
  - Mitigation controls (mapped to NixOS modules where applicable)
  - Residual risk rating
- **Risk treatment plans**: For risks requiring mitigation, document control implementations (many will reference NixOS module configurations)
- **Risk acceptance criteria**: Define thresholds for risk acceptance vs. required mitigation
- **Risk review cadence**: Quarterly review of risk register, annual full reassessment

### Evidence Artifacts for r2 Assessment
- Risk assessment document referencing flake modules as mitigations
- Risk register with treatment decisions
- vulnix scan results as input to vulnerability risk assessment
- AIDE reports as input to integrity risk assessment
- Quarterly risk review meeting minutes
- Risk acceptance documentation for accepted residual risks

### Cross-References
- NIST SP 800-53: RA-1 (Risk Assessment Policy), RA-2 (Security Categorization), RA-3 (Risk Assessment), RA-7 (Risk Response)
- HIPAA: 164.308(a)(1)(ii)(A) Risk Analysis, 164.308(a)(1)(ii)(B) Risk Management
- PCI DSS v4.0: Requirement 12.3 (Risk assessment process)
- ISO 27001: A.8.2-A.8.3 (Information classification, media handling), Clause 6.1 (Actions to address risks)

---

## Domain 04: Security Policy

### HITRUST Control References
- 04.a Information Security Policy Document
- 04.b Review of the Information Security Policy

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Information security policy documented and approved by management | Flake repository structure + `/docs/policies/information-security-policy.md` |
| **2** | Policy reviewed at planned intervals or when significant changes occur | Git tags for annual review cycles; policy version control via Git |
| **3** | Policy integrated into organizational processes; compliance measured | Policy references embedded in NixOS module comments; automated compliance checks |

This domain is **primarily organizational**. The NixOS flake contributes by:
- Serving as a machine-readable encoding of technical security policy
- Providing version control and change history for policy documents stored in `/docs/policies/`
- Enabling policy compliance verification through `nixos-rebuild` (the configuration IS the enforced policy)

### Required Organizational Processes (Outside Flake)

- **Information Security Policy** document covering: purpose, scope, roles, responsibilities, compliance requirements, review schedule
- **Policy review schedule**: At least annual, or upon significant change
- **Policy approval records**: Management sign-off (can be tracked via Git signed commits/tags)
- **Policy distribution**: Evidence that all relevant personnel have received and acknowledged the policy

### Evidence Artifacts for r2 Assessment
- Information security policy document with approval signatures
- Git history showing policy review and update dates
- Git tags for annual policy reviews (`policy-review-YYYY`)
- Policy acknowledgment records per user

### Cross-References
- NIST SP 800-53: PL-1 (Security Planning Policy), PM-1 (Information Security Program Plan)
- HIPAA: 164.316(a) Policies and Procedures
- PCI DSS v4.0: Requirement 12.1 (Information Security Policy)
- ISO 27001: A.5.1 (Policies for information security), A.5.2 (Review of policies)

---

## Domain 05: Organization of Information Security

### HITRUST Control References
- 05.a Management Direction for Information Security
- 05.b Screening (see also Domain 02)
- 05.i Identification of Risks Related to External Parties
- 05.j Addressing Security When Dealing with Customers
- 05.k Addressing Security in Third Party Agreements

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Security responsibilities assigned; third-party risks identified | Flake module ownership documents security responsibility allocation; flake inputs inventory identifies third parties |
| **2** | Security coordination across functions; third-party contractual requirements | Git-based change approval workflow; flake input hash verification |
| **3** | Continuous third-party monitoring; integrated security governance | Automated flake input vulnerability scanning; SBOM generation |

### NixOS Configuration Mapping (Third-Party Assurance)

```nix
# Third party assurance - flake-level controls
{
  # flake.nix inputs section provides cryptographic pinning of all third-party code
  # Every input has a SHA-256 hash in flake.lock
  # This constitutes a Software Bill of Materials (SBOM) for the system

  # Restrict substituters to trusted sources only
  nix.settings = {
    # HITRUST: third-party code must come from verified sources
    substituters = [
      "https://cache.nixos.org"
      # Add only explicitly approved binary caches
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    require-sigs = true;  # All binary substitutions must be signed
  };

  # Model integrity verification (AI-specific third-party assurance)
  systemd.services.model-integrity-check = {
    description = "Verify AI model file integrity";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "check-models" ''
        # Verify model checksums against known-good manifest
        cd /var/lib/ollama/models
        if [ -f /etc/model-checksums.sha256 ]; then
          ${pkgs.coreutils}/bin/sha256sum -c /etc/model-checksums.sha256 \
            >> /var/log/model-integrity.log 2>&1
          if [ $? -ne 0 ]; then
            echo "MODEL INTEGRITY FAILURE: $(date)" | ${pkgs.util-linux}/bin/wall
          fi
        fi
      '';
    };
  };
  systemd.timers.model-integrity-check = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
  };
}
```

HITRUST third-party assurance requirements specific to this system:

| Third Party | Risk Category | Verification Mechanism |
|---|---|---|
| Nixpkgs (package repository) | Software supply chain | `flake.lock` SHA-256 pinning; signed binary cache |
| NVIDIA drivers | Proprietary hardware drivers | Hash-locked Nix derivation; version pinning |
| Ollama | AI inference runtime | Pinned flake input; binary hash verification |
| AI Models (LLama, etc.) | Trained model artifacts | SHA-256 checksum manifest; daily integrity check |
| NTP servers | Time synchronization | Chrony authentication; multiple source consensus |

### Evidence Artifacts for r2 Assessment
- Organizational chart mapping security responsibilities
- `flake.lock` showing all third-party input hashes and sources
- `nix flake metadata` output showing input provenance
- Model checksum manifest (`/etc/model-checksums.sha256`)
- Model integrity check logs (`/var/log/model-integrity.log`)
- Nix binary cache trust configuration showing `require-sigs = true`
- Third-party vendor risk assessment documents
- Software Bill of Materials generated from Nix closure

### Cross-References
- NIST SP 800-53: PM-2 (Senior Information Security Officer), SA-9 (External System Services), SR-3 (Supply Chain Controls), SR-4 (Provenance)
- HIPAA: 164.308(a)(2) Assigned Security Responsibility, 164.308(b)(1) Business Associate Contracts
- PCI DSS v4.0: Requirement 12.8 (Service provider management), Requirement 6.3 (Security vulnerabilities identified)
- ISO 27001: A.6.1 (Internal organization), A.15.1-A.15.2 (Supplier relationships)

---

## Domain 06: Compliance

### HITRUST Control References
- 06.a Identification of Applicable Legislation
- 06.b Intellectual Property Rights
- 06.c Protection of Organizational Records
- 06.d Data Privacy and Protection of Personally Identifiable Information
- 06.e Prevention of Misuse of Information Processing Facilities
- 06.f Regulation of Cryptographic Controls
- 06.g Compliance with Security Policies and Standards
- 06.h Technical Compliance Checking
- 06.i Information Systems Audit Controls

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Applicable legal/regulatory requirements identified; records retention defined | Document applicable regulations; journald retention configuration |
| **2** | Compliance monitoring program; technical compliance checking | vulnix scanning; AIDE integrity checks; automated evidence collection |
| **3** | Continuous compliance verification; audit controls integrated | Continuous monitoring via systemd timers; evidence generation automation |

### NixOS Configuration Mapping

```nix
# Compliance - technical compliance checking
{
  # Automated compliance evidence collection (see Evidence Generation section)
  # vulnix for vulnerability compliance (see Domain 10)
  # AIDE for configuration compliance (see Domain 09)
  # auditd for audit compliance (see Domain 09)

  # Record retention via journald (see Domain 09 for full config)
  services.journald.extraConfig = ''
    Storage=persistent
    MaxRetentionSec=365day
  '';

  # Cryptographic compliance: FIPS-equivalent cipher suites
  # (Full SSH and TLS configuration in Domain 09)
}
```

### Required Organizational Processes (Outside Flake)

- **Regulatory inventory**: Document all applicable laws, regulations, and contractual obligations (HIPAA, state privacy laws, etc.)
- **Compliance monitoring schedule**: Define cadence for compliance reviews
- **Records retention schedule**: Map record types to required retention periods
- **Audit facilitation procedures**: How to provide system access and evidence to auditors
- **Login banner** (configured in NixOS) serves as notice against misuse of information processing facilities

### Evidence Artifacts for r2 Assessment
- Regulatory applicability matrix
- Technical compliance scan results (vulnix, AIDE)
- Records retention schedule
- Audit log showing system audit activities
- Cryptographic controls inventory

### Cross-References
- NIST SP 800-53: SA-15 (Development Process), AU-11 (Audit Record Retention), SC-13 (Cryptographic Protection)
- HIPAA: 164.316(b)(2) Documentation Retention, 164.308(a)(8) Evaluation
- PCI DSS v4.0: Requirement 12.4 (PCI DSS compliance management)
- ISO 27001: A.18.1-A.18.2 (Compliance)

---

## Domain 07: Asset Management

### HITRUST Control References
- 07.a Inventory of Assets
- 07.b Ownership of Assets
- 07.c Acceptable Use of Assets
- 07.d Classification of Information
- 07.e Labeling and Handling of Information

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Asset inventory maintained; ownership assigned | Nix system closure provides complete software asset inventory; hardware documented in flake comments |
| **2** | Information classification scheme; labeling procedures | Document data classification for AI model data, inference inputs/outputs, logs |
| **3** | Automated asset discovery and classification | Nix closure analysis; automated SBOM generation |

### NixOS Configuration Mapping

```nix
# Asset management - software inventory via Nix
{
  # The Nix store provides a complete, cryptographically verified
  # inventory of all software assets on the system.
  # `nix-store --query --requisites /run/current-system` produces the full asset list.

  # Hardware asset documentation (in flake module comments)
  # GPU: NVIDIA [model] - documented in gpu-node module
  # Network: enp3s0 wired Ethernet - documented in lan-only-network module

  # Software asset inventory automation
  environment.systemPackages = with pkgs; [
    nix-index    # Package indexing for audit purposes
  ];
}
```

### Required Organizational Processes (Outside Flake)

- **Asset inventory**: Hardware and software assets with owners. NixOS provides automated software inventory via `nix-store --query --requisites /run/current-system`
- **Information classification scheme**: Define classification levels (e.g., Public, Internal, Confidential, Restricted) applicable to:
  - AI model files (likely Confidential - proprietary or licensed)
  - Inference input/output data (classification depends on content - may contain PII)
  - System logs (Internal - contain security-relevant information)
  - Configuration files (Internal - contain security architecture details)
- **Acceptable use policy**: Document permitted uses of system resources
- **Asset disposal procedures**: Tie to media sanitization (Domain 09)

### Evidence Artifacts for r2 Assessment
- `nix-store --query --requisites /run/current-system` output (software asset inventory)
- `nix flake metadata` output showing input provenance
- Hardware asset inventory document
- Information classification policy
- Acceptable use policy

### Cross-References
- NIST SP 800-53: CM-8 (Information System Component Inventory), MP-4 (Media Storage), RA-2 (Security Categorization)
- HIPAA: 164.310(d)(1) Device and Media Controls
- PCI DSS v4.0: Requirement 9.4 (Restrict physical access), Requirement 12.5 (PCI DSS scope)
- ISO 27001: A.8.1-A.8.3 (Asset management)

---

## Domain 08: Physical and Environmental Security

### HITRUST Control References
- 08.a Physical Security Perimeter
- 08.b Physical Entry Controls
- 08.c Securing Offices, Rooms, and Facilities
- 08.d Protecting Against External and Environmental Threats
- 08.e Working in Secure Areas
- 08.f Public Access, Delivery, and Loading Areas
- 08.g Equipment Siting and Protection
- 08.h Supporting Utilities
- 08.i Cabling Security
- 08.j Equipment Maintenance
- 08.k Security of Equipment Off-Premises
- 08.l Secure Disposal or Re-Use of Equipment

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Physical access controls documented; equipment siting considered | Host-level: USB blocking, screen lock, disk encryption. Organizational: locked room documentation |
| **2** | Physical entry logging; environmental monitoring; equipment maintenance records | Host-level: USBGuard logging, LUKS encryption. Organizational: visitor logs, maintenance records |
| **3** | Automated physical security integration; comprehensive environmental monitoring | Primarily organizational; host config provides defense-in-depth layers |

This domain is **primarily physical/organizational**. Even for a LAN server in a private environment, HITRUST requires documented physical controls. The NixOS host configuration contributes defense-in-depth measures for the scenario where physical security is bypassed.

### NixOS Configuration Mapping (Host-Level Physical Controls)

```nix
# Physical security defense-in-depth - stig-baseline module
{
  # Disable USB mass storage (prevents data exfiltration via physical access)
  boot.blacklistedKernelModules = [ "usb-storage" "firewire-core" "thunderbolt" ];

  # USBGuard for granular device policy
  services.usbguard = {
    enable = true;
    rules = ''
      # Allow only known HID devices (keyboard, mouse)
      allow with-interface one-of { 03:*:* }
      # Block all storage devices
      reject with-interface one-of { 08:*:* }
      # Default deny
      reject
    '';
  };

  # Full disk encryption (protects data if equipment is stolen)
  # LUKS configuration is handled at install time, not in flake config
  # Document: boot.initrd.luks.devices should be configured for the root partition

  # Screen lock timeout (HITRUST: clear screen policy)
  # For headless servers, console auto-logout serves this purpose
  programs.bash.interactiveShellInit = ''
    export TMOUT=900  # 15-minute idle timeout (also serves clear screen policy)
    readonly TMOUT
  '';

  # Audit USB device connections for physical access monitoring
  security.auditd.enable = true;
  # USB audit rules included in Domain 09 audit configuration
}
```

### Required Organizational/Physical Measures (Outside Flake)

- **Physical security perimeter**: Server must be in a locked room/cabinet with controlled access
- **Physical entry controls**: Access logs (sign-in sheet or electronic badge log) for the server room
- **Visitor procedures**: Visitor logs, escort requirements
- **Environmental monitoring**: Temperature/humidity monitoring appropriate for server equipment (even a single-server environment should have a temperature alert)
- **Equipment siting**: Document server location, rack/placement, cable routing
- **Supporting utilities**: UPS/power protection documentation
- **Cabling security**: Network cables physically secured, not passing through public areas
- **Equipment maintenance**: Maintenance log for hardware (GPU, drives, etc.)
- **Secure disposal**: Documented procedure for disk wiping/destruction when decommissioning (tie to LUKS: destroying the LUKS header effectively wipes encrypted data)

### Evidence Artifacts for r2 Assessment
- Physical security documentation (room location, lock type, access list)
- Physical access logs (visitor sign-in sheets or badge logs)
- Equipment inventory with locations
- USBGuard policy and blocked device logs
- LUKS encryption status verification
- Environmental monitoring records (if applicable)
- Equipment maintenance logs
- Secure disposal procedures and records

### Cross-References
- NIST SP 800-53: PE-1 through PE-20 (Physical and Environmental Protection family)
- HIPAA: 164.310(a) Facility Access Controls, 164.310(b) Workstation Use, 164.310(c) Workstation Security, 164.310(d) Device and Media Controls
- PCI DSS v4.0: Requirement 9 (Restrict Physical Access to Cardholder Data)
- ISO 27001: A.11.1-A.11.2 (Physical and environmental security)

---

## Domain 09: Communications and Operations Management

### HITRUST Control References
- 09.a Documented Operating Procedures
- 09.b Change Management
- 09.c Segregation of Duties
- 09.d Separation of Development, Test, and Operational Facilities
- 09.e External Information Exchange Agreements
- 09.j Controls Against Malicious Code
- 09.k Controls Against Mobile Code
- 09.m Network Controls
- 09.n Security of Network Services
- 09.o Management of Removable Media
- 09.p Disposal of Media
- 09.q Information Handling Procedures
- 09.s Information Exchange Policies and Procedures
- 09.v Electronic Messaging
- 09.w Interconnected Business Information Systems
- 09.x Electronic Commerce Services
- 09.y On-line Transactions
- 09.aa Audit Logging
- 09.ab Monitoring System Use
- 09.ac Protection of Log Information
- 09.ad Administrator and Operator Logs
- 09.ae Fault Logging
- 09.af Clock Synchronization

This is the largest HITRUST domain. It encompasses configuration management, malware protection, network protection, media controls, transmission protection, and audit logging.

### 09.a-09.d: Operations and Change Management

#### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Baseline configurations documented; changes tracked | NixOS flake IS the baseline configuration; Git tracks all changes |
| **2** | Automated configuration enforcement; change approval workflow; separation of environments | `nixos-rebuild switch` atomically enforces declared state; Git branch protection; `nixos-rebuild build` for testing |
| **3** | Continuous configuration compliance monitoring with drift remediation | AIDE hourly checks + systemd timer-based compliance scans; automatic rollback to last-known-good generation |

```nix
# Configuration and change management - the NixOS flake model
{
  # Pin all inputs for reproducible builds (HITRUST: configuration baselines must be documented)
  # flake.lock provides cryptographic hashes of all dependencies

  # System profile management enables rollback
  system.stateVersion = "24.11";

  # Nix garbage collection policy (retain recent generations for rollback)
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 90d";  # Retain 90 days of generations
  };

  # Canonical value per prd.md Appendix A.14: [ "admin" ]
  # Restrict who can modify the system configuration
  nix.settings.allowed-users = [ "root" "admin" ];
  nix.settings.trusted-users = [ "root" ];

  # AIDE baseline for drift detection
  systemd.services.aide-check = {
    description = "AIDE integrity check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --check";
    };
  };
  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "hourly";
  };
}
```

HITRUST prescriptive requirement: Configuration baselines must be reviewed and updated **at least annually**, and unauthorized changes must be detected within **24 hours**. NixOS exceeds this: the flake lock provides a cryptographically pinned baseline, AIDE runs hourly (well within 24 hours), and Git history provides full change audit trail.

**Key HITRUST differentiator vs. NIST**: NIST CM-3 says "track, review, approve changes." HITRUST specifies that changes must be tested in a non-production environment, approved by an authorized individual, and documented with rollback procedures. NixOS generations provide built-in rollback. The flake supports test builds via `nixos-rebuild build` before `switch`.

### 09.j-09.k: Endpoint/Malware Protection

#### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Anti-malware deployed on endpoints | NixOS immutable store provides inherent malware resistance; ClamAV available for file scanning of uploaded content |
| **2** | Anti-malware signatures updated at least daily; scan frequency defined | Automated ClamAV freshclam updates via systemd timer; AIDE integrity checks hourly |
| **3** | Endpoint detection and response with centralized alerting | AIDE + auditd + journal forwarding to centralized log analysis |

```nix
# Endpoint hardening - stig-baseline module
{
  # Canonical value per prd.md Appendix A.14: [ "admin" ]
  # Immutable system packages via Nix store (inherent malware resistance)
  nix.settings.allowed-users = [ "@wheel" ];
  nix.settings.trusted-users = [ "root" ];

  # ClamAV for file content scanning (ai-services uploads, agent artifacts)
  services.clamav = {
    daemon.enable = true;
    updater.enable = true;
    updater.interval = "daily";
    updater.frequency = 12;  # Check 12 times per day per HITRUST prescriptive threshold
  };

  # Restrict kernel module loading (prevents rootkit insertion)
  security.lockKernelModules = true;

  # Disable core dumps (prevent credential/memory leakage)
  security.pam.loginLimits = [
    { domain = "*"; type = "hard"; item = "core"; value = "0"; }
  ];

  # Restrict ptrace scope
  boot.kernel.sysctl."kernel.yama.ptrace_scope" = 2;
}
```

HITRUST prescriptive requirement: Anti-malware signatures must be updated **no less than daily**. The `updater.frequency = 12` setting exceeds this by checking every 2 hours.

### 09.m-09.n: Network Protection

#### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Firewall deployed; network segmentation documented | `networking.firewall.enable = true`; LAN-only interface binding |
| **2** | Stateful inspection; IDS/IPS deployed; network flows logged | nftables stateful firewall; Suricata or Snort IDS; connection logging via auditd |
| **3** | Network behavior analysis; automated threat response; micro-segmentation | Per-service network namespaces; agent sandbox network isolation; automated firewall rule tightening |

```nix
# Network protection - lan-only-network module
# NOTE: NixOS 24.11 defaults to nftables. Use networking.nftables.enable = true
# (or explicitly set networking.nftables.enable = false to use legacy iptables).
# The configuration below uses nftables syntax.
{
  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];  # Default: no ports open globally

    # LAN-only interface binding (HITRUST: network access must be restricted)
    interfaces.enp3s0 = {
      allowedTCPPorts = [
        22     # SSH - management
        11434  # Ollama - inference API
        8000   # App API - application services
      ];
    };

    # Log dropped packets for forensic analysis
    logRefusedConnections = true;
    logRefusedPackets = true;
    logReversePathDrops = true;
  };

  # Outbound traffic restriction via nftables
  networking.nftables.tables.outbound-filter = {
    family = "inet";
    content = ''
      chain output {
        type filter hook output priority 0; policy drop;
        ct state established,related accept
        oif lo accept
        tcp dport 443 accept comment "Allow HTTPS for Nix cache and updates"
        udp dport 53 accept comment "Allow DNS"
        tcp dport 53 accept comment "Allow DNS over TCP"
        log prefix "OUTBOUND_DENIED: " drop
      }
    '';
  };

  # DNS restricted to local resolver
  networking.nameservers = [ "192.168.1.1" ];

  # Disable IP forwarding (server is not a router)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 0;
    "net.ipv6.conf.all.forwarding" = 0;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;
  };

  # Agent sandbox network isolation
  systemd.services.agent-runner.serviceConfig = {
    # Restrict agent to localhost + LAN only
    RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    IPAddressDeny = "any";
    IPAddressAllow = [ "127.0.0.0/8" "192.168.0.0/16" "10.0.0.0/8" ];
  };
}
```

HITRUST prescriptive requirements for network protection:
- Firewalls must use **default-deny** rules (implemented: `allowedTCPPorts = [ ]` globally)
- Network traffic must be **logged** (implemented: `logRefusedConnections = true`)
- Outbound traffic must be **restricted to business-necessary destinations** (implemented: nftables outbound rules)
- Internal network segmentation must isolate sensitive systems (implemented: per-service network restrictions via systemd)

#### Wireless Security (09.m subset)

Wireless controls are **N/A (Not Applicable)** for this system. The server uses wired Ethernet only. This is scoped out, not scored at a maturity level.

```nix
# Wireless security - disable all wireless interfaces
{
  networking.wireless.enable = false;

  # NOTE: Canonical kernel module blacklist is in prd.md Appendix A.10
  # Defined once in stig-baseline module. This list is illustrative only.
  # Blacklist wireless kernel modules as defense in depth
  boot.blacklistedKernelModules = [
    "iwlwifi" "iwlmvm" "iwldvm"   # Intel wireless
    "ath9k" "ath10k" "ath11k"      # Atheros/Qualcomm wireless
    "brcmfmac" "brcmsmac"          # Broadcom wireless
    "rtw88" "rtw89"                 # Realtek wireless
    "mt76" "mt7921e"               # MediaTek wireless
  ];

  # Ensure only wired interface is configured
  # DEPRECATED in NixOS 23.11+. Use networking.useDHCP or systemd.network instead.
  networking.interfaces.enp3s0.useDHCP = true;
}
```

**Alternate control justification**: Wireless access controls (WPA3/Enterprise, 802.1X, wireless IDS) are not applicable because no wireless interface exists on the system. Wireless kernel modules are blacklisted as defense-in-depth. This should be documented as a scoping exclusion in the MyCSF portal with alternate control request if the assessor requires it.

### 09.o-09.q: Portable Media Security

```nix
# Portable media controls - stig-baseline module
{
  # NOTE: Canonical kernel module blacklist is in prd.md Appendix A.10
  # Defined once in stig-baseline module. This list is illustrative only.
  # Disable USB mass storage (HITRUST prescriptive: removable media must be controlled)
  boot.blacklistedKernelModules = [ "usb-storage" "firewire-core" "thunderbolt" ];

  # USBGuard for granular device policy
  services.usbguard = {
    enable = true;
    rules = ''
      # Allow only known HID devices (keyboard, mouse)
      allow with-interface one-of { 03:*:* }
      # Block all storage devices
      reject with-interface one-of { 08:*:* }
      # Default deny
      reject
    '';
  };

  # Audit USB device connections
  security.auditd.enable = true;
  # Audit rules for device events (added via audit-and-aide module)
}
```

HITRUST prescriptive requirement: Removable media must be **disabled by default** and only enabled with documented business justification. The kernel module blacklist enforces this at the OS level.

### 09.v-09.y: Transmission Protection

#### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Encryption in transit for sensitive data; TLS 1.2 minimum | TLS termination for all API services; SSH for management |
| **2** | TLS 1.2+ enforced; certificate management; encrypted internal communications | Self-signed CA for internal services; cipher suite restrictions |
| **3** | Perfect forward secrecy required; automated certificate rotation | Strong cipher-only configuration; automated cert renewal |

```nix
# Transmission protection - ai-services module and stig-baseline module
{
  # Canonical SSH settings per prd.md Appendix A.4
  # SSH transport hardening (HITRUST: encryption in transit for management)
  services.openssh.settings = {
    # HITRUST prescriptive: TLS 1.2 equivalent - strong ciphers only
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
    ];
    KexAlgorithms = [
      "curve25519-sha256@libssh.org"
      "curve25519-sha256"
      "diffie-hellman-group16-sha512"
      "diffie-hellman-group18-sha512"
    ];
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
  };

  # Nginx reverse proxy for API services with TLS
  # NOTE: sslProtocols and sslCiphers are NOT top-level nginx options.
  # Use recommendedTlsSettings or place directives in appendHttpConfig/extraConfig.
  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    # HITRUST prescriptive: TLS 1.2 minimum, prefer 1.3
    appendHttpConfig = ''
      ssl_protocols TLSv1.2 TLSv1.3;
      ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
      ssl_prefer_server_ciphers on;
    '';

    virtualHosts."ai-server.local" = {
      forceSSL = true;
      sslCertificate = "/var/lib/secrets/tls/server.crt";
      sslCertificateKey = "/var/lib/secrets/tls/server.key";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
      };
      locations."/ollama/" = {
        proxyPass = "http://127.0.0.1:11434";
      };
    };
  };

  # NOTE: ACME/Let's Encrypt cannot validate .local domains.
  # For LAN-only servers, use manual certificate management via sops-nix.
  # This block is illustrative only; the implementation uses manual certs.
  # Internal service TLS certificate management
  security.acme = {
    acceptTerms = true;
    defaults.email = "admin@internal.local";
  };
}
```

HITRUST prescriptive requirements for transmission protection:
- **TLS 1.2 minimum** required for all transmissions containing sensitive data (HITRUST is explicit where NIST says "FIPS-validated cryptography")
- **SSH Protocol 2 only** (NixOS OpenSSH defaults to Protocol 2)
- Cipher suites must provide **128-bit equivalent strength minimum** (AES-128-GCM or stronger)
- Perfect forward secrecy ciphers **required at Level 3** (ECDHE key exchange)

### 09.aa-09.af: Audit Logging and Monitoring

#### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Audit logging enabled; logs retained 90 days minimum; log access restricted | auditd + journald; log retention policy; root-only log access |
| **2** | Centralized log collection; tamper detection; 1-year retention; daily log review | Journal forwarding; log integrity via append-only storage; 365-day retention; automated alerting |
| **3** | Real-time SIEM integration; automated anomaly detection; 6-year retention for regulated data | External log shipping; ML-based anomaly detection on agent behavior; long-term archive |

```nix
# Audit logging and monitoring - audit-and-aide module
{
  # Enable auditd (HITRUST: audit logging must capture security-relevant events)
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # Login/logout events
      "-w /var/log/lastlog -p wa -k logins"
      "-w /var/log/faillog -p wa -k logins"
      "-w /var/run/faillock -p wa -k logins"

      # Authentication events
      "-w /etc/pam.d/ -p wa -k pam_changes"
      "-w /etc/shadow -p wa -k shadow_changes"
      "-w /etc/passwd -p wa -k passwd_changes"
      "-w /etc/group -p wa -k group_changes"

      # Privilege escalation
      "-w /usr/bin/sudo -p x -k privilege_escalation"
      "-w /usr/bin/su -p x -k privilege_escalation"
      "-a always,exit -F arch=b64 -S setuid -S setgid -k privilege_escalation"

      # File system changes to critical paths
      "-w /etc/nixos/ -p wa -k nixos_config"
      "-w /etc/ssh/sshd_config -p wa -k ssh_config"

      # Network configuration changes
      "-w /etc/hosts -p wa -k network_config"
      "-w /etc/resolv.conf -p wa -k network_config"
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_config"

      # Kernel module operations
      "-w /sbin/modprobe -p x -k kernel_modules"
      "-w /sbin/insmod -p x -k kernel_modules"
      "-a always,exit -F arch=b64 -S init_module -S delete_module -k kernel_modules"

      # Time changes (HITRUST: clock synchronization must be audited)
      "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time_change"
      "-w /etc/localtime -p wa -k time_change"

      # AI-specific: monitor agent working directories
      "-w /var/lib/agent-runner/ -p wa -k agent_activity"
      "-w /var/lib/ollama/ -p r -k model_access"

      # Ensure audit configuration is immutable (must be last rule)
      "-e 2"
    ];
  };

  # Journal retention (HITRUST prescriptive: 1 year minimum for Level 2)
  services.journald.extraConfig = ''
    Storage=persistent
    SystemMaxUse=10G
    SystemKeepFree=2G
    MaxRetentionSec=365day
    MaxFileSec=1month
    ForwardToSyslog=yes
    Compress=yes
  '';

  # NTP synchronization (HITRUST: system clocks must be synchronized)
  services.chrony = {
    enable = true;
    servers = [
      "0.pool.ntp.org"
      "1.pool.ntp.org"
      "2.pool.ntp.org"
      "3.pool.ntp.org"
    ];
    extraConfig = ''
      # HITRUST: clock accuracy within 1 second
      maxdistance 1.0
      makestep 0.1 3
      rtcsync
    '';
  };

  # Log file permissions (HITRUST: logs must be protected from unauthorized access)
  systemd.tmpfiles.rules = [
    "d /var/log/audit 0700 root root -"
    "d /var/log/vulnix 0750 root systemd-journal -"
    "d /var/log/aide 0750 root systemd-journal -"
  ];

  # Automated log review alerting
  systemd.services.log-alert = {
    description = "Security log alert scanner";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "log-alert" ''
        # Check for security-relevant events in last hour
        ${pkgs.systemd}/bin/journalctl --since "1 hour ago" --priority=warning \
          | ${pkgs.gawk}/bin/awk '/authentication failure|Failed password|session opened for user root/ {
            print strftime("%Y-%m-%d %H:%M:%S"), $0
          }' > /var/log/security-alerts.log

        # Alert if critical events found
        if [ -s /var/log/security-alerts.log ]; then
          echo "SECURITY ALERT: Review /var/log/security-alerts.log" | \
            ${pkgs.util-linux}/bin/wall
        fi
      '';
    };
  };
  systemd.timers.log-alert = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "hourly";
  };
}
```

HITRUST prescriptive audit logging requirements:

| Requirement | HITRUST Threshold | NixOS Implementation |
|---|---|---|
| Events captured | Authentication, authorization, system changes, data access | auditd rules cover all categories |
| Log retention | 90 days (L1), 1 year (L2), 6 years (L3 for regulated) | `MaxRetentionSec=365day` |
| Log protection | Read-only to non-root; integrity verification | `0700` permissions; immutable audit rules (`-e 2`) |
| Clock sync | Authoritative time source; 1-second accuracy | chrony with `maxdistance 1.0` |
| Log review | Daily (L2), real-time (L3) | Hourly automated scan; alerting on critical events |
| Audit trail | User, event type, date/time, success/failure, affected resource | auditd fields capture all required elements |

### Evidence Artifacts for r2 Assessment
- `flake.lock` file showing pinned dependency hashes
- Git log showing all configuration changes with author, date, and commit message
- AIDE report outputs from hourly scans
- `nixos-rebuild list-generations` output showing available rollback points
- Change management records (Git PR/merge history with approval)
- ClamAV update logs showing daily signature updates (`journalctl -u clamav-freshclam`)
- AIDE scan reports with timestamps proving hourly execution
- Nix store hash verification output showing package integrity
- `nft list ruleset` output showing active firewall rules (nftables)
- `ss -tlnp` output showing listening services limited to expected ports
- Firewall log samples showing denied connection attempts
- Network architecture diagram with data flow annotations
- `ip link show` output confirming no wireless interfaces active
- Kernel module blacklist showing wireless drivers blocked
- USBGuard policy file and blocked device logs
- `sshd -T` output showing enforced cipher suites and key exchange algorithms
- `openssl s_client` test results against each TLS-enabled service
- Nginx configuration showing TLS version and cipher restrictions via `appendHttpConfig`
- `auditctl -l` output showing active audit rules
- Sample audit log entries for each monitored event category
- `journalctl --disk-usage` showing retention capacity
- chrony tracking output (`chronyc tracking`) showing time synchronization status
- Security alert log samples showing automated review
- Log access permission verification (`ls -la /var/log/audit/`)

### Cross-References
- NIST SP 800-53: CM-2 (Baseline Configuration), CM-3 (Configuration Change Control), CM-6 (Configuration Settings), CM-7 (Least Functionality), SI-3 (Malicious Code Protection), SI-7 (Software/Firmware Integrity), SC-7 (Boundary Protection), AC-4 (Information Flow Enforcement), SC-5 (DoS Protection), AC-18 (Wireless Access), MP-2 (Media Access), MP-6 (Media Sanitization), MP-7 (Media Use), SC-8 (Transmission Confidentiality), SC-13 (Cryptographic Protection), AU-2 through AU-9 (Audit family)
- HIPAA: 164.312(b) Audit Controls, 164.308(a)(8) Evaluation, 164.308(a)(5)(ii)(B) Protection from Malicious Software, 164.312(e)(1) Transmission Security, 164.310(d)(1) Device and Media Controls
- PCI DSS v4.0: Requirement 1 (Network Security Controls), Requirement 2.1.1 (Wireless security -- N/A for this system), Requirement 4 (Encrypt Transmission), Requirement 5 (Protect Against Malware), Requirement 6.5 (Change control), Requirement 9.4.5 (Media destruction), Requirement 10 (Log and Monitor All Access), Requirement 11.3.1 (Vulnerability scans)
- ISO 27001: A.10.1 (Cryptographic controls), A.12.1-A.12.7 (Operations security), A.13.1-A.13.2 (Communications security), A.14.2 (Security in development)

---

## Domain 10: Information Systems Acquisition, Development, and Maintenance

### HITRUST Control References
- 10.a Security Requirements Analysis and Specification
- 10.b Input Data Validation
- 10.c Internal Processing
- 10.f Policy on the Use of Cryptographic Controls
- 10.g Key Management
- 10.h Control of Operational Software
- 10.j Access Control to Program Source Code
- 10.k Change Control Procedures
- 10.m Control of Technical Vulnerabilities

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Vulnerability scanning at least quarterly; critical patches within 90 days | `nix flake update` pulls latest security patches; Nix security tracker integration |
| **2** | Scanning at least monthly; critical patches within 30 days; vulnerability prioritization process | Automated monthly `vulnix` scans via systemd timer; CVSS-based prioritization |
| **3** | Continuous vulnerability assessment; critical patches for actively-exploited vulnerabilities as soon as possible with risk-based prioritization | Continuous `vulnix` integration; immediate `nix flake update` for critical CVEs; AIDE verification post-patch |

### NixOS Configuration Mapping

```nix
# Vulnerability management - audit-and-aide module
{
  environment.systemPackages = with pkgs; [
    vulnix       # NixOS-native vulnerability scanner (queries NIST NVD)
    nix-index    # Package indexing for audit purposes
  ];

  # Automated vulnerability scanning (HITRUST: at least monthly for Level 2)
  systemd.services.vulnix-scan = {
    description = "NixOS vulnerability scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.vulnix}/bin/vulnix --system";
      StandardOutput = "append:/var/log/vulnix/scan-results.log";
    };
  };
  systemd.timers.vulnix-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";      # Exceeds monthly HITRUST Level 2 requirement
      Persistent = true;
    };
  };

  # Automated security updates channel
  system.autoUpgrade = {
    enable = true;
    flake = "github:owner/nix-flake";
    flags = [ "--update-input" "nixpkgs" ];
    dates = "04:00";
    allowReboot = false;  # Require manual reboot decision for availability
  };
}
```

HITRUST prescriptive thresholds for vulnerability/patch management:

| Severity | HITRUST Maximum Remediation Time | NixOS Mechanism |
|---|---|---|
| Critical (CVSS 9.0+) | Level 1: 90 days / Level 2: 30 days / Level 3: As soon as possible with risk-based prioritization (72-hour target for actively-exploited vulnerabilities only) | Immediate `nix flake update` + `nixos-rebuild switch` |
| High (CVSS 7.0-8.9) | 30 days (Level 2) | Weekly `vulnix` scan triggers update cycle |
| Medium (CVSS 4.0-6.9) | 90 days | Monthly review cycle |
| Low (CVSS 0.1-3.9) | Next scheduled maintenance | Quarterly flake input update |

> **Note on 72-hour remediation**: The 72-hour target at Level 3 applies specifically to **actively-exploited critical vulnerabilities** (i.e., known zero-days with active exploitation in the wild). For critical vulnerabilities without evidence of active exploitation, a 30-day window with risk-based prioritization is appropriate. The general "as soon as possible" language at Level 3 should be interpreted through the lens of risk-based prioritization, not as a blanket 72-hour SLA for all critical CVEs.

**Key HITRUST differentiator vs. NIST**: NIST RA-5 requires vulnerability scanning but does not prescribe specific remediation timelines. HITRUST mandates exact maximum remediation windows by severity level.

### Evidence Artifacts for r2 Assessment
- `vulnix --system` scan reports with timestamps
- Git history showing security update commits with CVE references
- `nix flake update` logs showing input version changes
- Remediation timeline records (time from CVE publication to `nixos-rebuild switch`)
- `nixos-rebuild list-generations` showing patched generations and their dates
- Source code access control documentation (Git repository permissions)
- Cryptographic key management procedures

### Cross-References
- NIST SP 800-53: RA-5 (Vulnerability Monitoring and Scanning), SI-2 (Flaw Remediation), SA-3 (System Development Life Cycle), SA-11 (Developer Testing)
- HIPAA: 164.308(a)(1)(ii)(B) Risk Management
- PCI DSS v4.0: Requirement 6.2 (Bespoke and custom software security), Requirement 6.3 (Security vulnerabilities identified), Requirement 11.3 (Vulnerability scans)
- ISO 27001: A.14.1-A.14.3 (System acquisition, development, maintenance)

---

## Domain 11: Information Security Incident Management

### HITRUST Control References
- 11.a Reporting Information Security Events
- 11.b Reporting Security Weaknesses
- 11.c Responsibilities and Procedures
- 11.d Learning from Information Security Incidents
- 11.e Collection of Evidence

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Incident reporting procedures defined; security events reported | auditd alerting; log-alert systemd service; login banner references reporting obligations |
| **2** | Incident classification scheme; defined response timelines; post-incident review process | AIDE anomaly detection feeds incident triage; auditd provides forensic evidence; documented IR plan |
| **3** | Automated incident detection and escalation; integrated IR workflow; evidence preservation | Real-time auditd alerting; automated evidence collection; preserved audit trails |

### NixOS Configuration Mapping

```nix
# Incident management technical controls - audit-and-aide module
{
  # AIDE detects integrity anomalies that may indicate security incidents
  # (Full AIDE configuration in Domain 09)

  # auditd provides security event detection and forensic evidence
  # (Full auditd configuration in Domain 09)

  # Automated security event alerting (incident detection trigger)
  # (log-alert service configured in Domain 09)

  # Evidence preservation: immutable audit rules prevent log tampering
  # The `-e 2` auditd rule locks audit configuration until reboot
  # Journal persistence ensures incident evidence survives across sessions

  # Incident evidence collection on demand
  systemd.services.incident-evidence-collector = {
    description = "Collect evidence for security incident investigation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "incident-evidence" ''
        INCIDENT_DIR="/var/lib/incident-evidence/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$INCIDENT_DIR"

        # Capture current system state
        ${pkgs.iproute2}/bin/ss -tlnp > "$INCIDENT_DIR/connections.txt"
        ${pkgs.procps}/bin/ps auxf > "$INCIDENT_DIR/processes.txt"
        ${pkgs.systemd}/bin/journalctl --since "24 hours ago" > "$INCIDENT_DIR/journal-24h.txt"
        ${pkgs.audit}/bin/ausearch --start recent > "$INCIDENT_DIR/recent-audit.txt" 2>&1 || true
        ${pkgs.aide}/bin/aide --check > "$INCIDENT_DIR/aide-check.txt" 2>&1 || true

        # Create integrity manifest
        find "$INCIDENT_DIR" -type f -exec sha256sum {} \; > "$INCIDENT_DIR/manifest.sha256"

        echo "Incident evidence collected: $INCIDENT_DIR"
      '';
    };
  };
}
```

### Incident Classification Scheme

| Severity | Description | Response Timeline | Examples |
|---|---|---|---|
| **Critical** | Active compromise; data exfiltration; system integrity loss | Immediate (within 1 hour): contain and investigate | AIDE detects unauthorized binary changes; auditd shows privilege escalation by unknown process |
| **High** | Attempted compromise; policy violation; significant vulnerability exploited | Within 4 hours: investigate and contain | Multiple failed login attempts from unknown source; USB device insertion attempt |
| **Medium** | Policy deviation; minor vulnerability; suspicious activity | Within 24 hours: investigate | Configuration drift detected by AIDE; unusual agent activity patterns |
| **Low** | Informational; minor policy reminder | Within 72 hours: log and review | Failed login from known user (forgotten password); routine alert |

### Required Organizational Processes (Outside Flake)

- **Incident Response Plan** (`/docs/policies/incident-response-plan.md`):
  - Incident classification scheme (as above)
  - Roles and responsibilities (incident commander, technical lead, communications)
  - Escalation procedures and contact information
  - Communication templates (internal notification, external notification if required)
  - Evidence handling procedures (chain of custody)
- **Post-Incident Review Process**:
  - Root cause analysis template
  - Lessons learned documentation
  - Control improvement recommendations (fed back into NixOS flake updates)
- **Notification Procedures**:
  - HIPAA breach notification timelines (60 days to HHS, "without unreasonable delay" to individuals)
  - State breach notification requirements (vary by state)
  - Internal escalation matrix
- **Evidence Collection Procedures**:
  - Run `systemctl start incident-evidence-collector` immediately upon incident detection
  - Preserve audit logs and journal entries for the incident timeframe
  - Document chain of custody for all evidence artifacts

### Evidence Artifacts for r2 Assessment
- Incident Response Plan document
- Incident classification scheme
- Evidence of incident response testing/tabletop exercises
- Post-incident review reports (if incidents occurred)
- Notification procedure documentation
- Evidence collection procedure and chain-of-custody forms
- auditd and AIDE configuration showing automated detection capabilities
- log-alert service configuration showing automated event scanning

### Cross-References
- NIST SP 800-53: IR-1 through IR-10 (Incident Response family), AU-6 (Audit Record Review)
- HIPAA: 164.308(a)(6) Security Incident Procedures, 164.404-164.410 (Breach Notification)
- PCI DSS v4.0: Requirement 12.10 (Incident response plan)
- ISO 27001: A.16.1 (Management of information security incidents)

---

## Domain 12: Business Continuity Management

### HITRUST Control References
- 12.a Including Information Security in the Business Continuity Management Process
- 12.b Business Continuity and Risk Assessment
- 12.c Developing and Implementing Continuity Plans Including Information Security
- 12.d Business Continuity Planning Framework
- 12.e Testing, Maintaining, and Re-assessing Business Continuity Plans

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Business continuity plan exists; backup procedures defined | NixOS generation rollback; BorgBackup configuration for data backup |
| **2** | RTO/RPO defined; backup testing performed; continuity plan tested annually | Documented RTO/RPO; backup restoration testing; generation rollback testing |
| **3** | Integrated continuity testing; automated failover capabilities | Automated backup verification; NixOS declarative rebuild from scratch capability |

### NixOS Configuration Mapping

```nix
# Business continuity - backup and recovery
{
  # NixOS generation rollback provides instant system recovery
  # `nixos-rebuild switch --rollback` restores previous known-good configuration
  # System generations retained for 90 days (configured in Domain 09)

  # BorgBackup for data backup
  services.borgbackup.jobs.system-backup = {
    paths = [
      "/var/lib/ollama/models"      # AI model files
      "/var/lib/agent-runner"       # Agent working data
      "/var/log"                    # Log archives
      "/etc/nixos"                  # NixOS configuration (also in Git)
      "/var/lib/hitrust-evidence"   # Assessment evidence
    ];
    repo = "/backup/borg";  # Local backup repository (supplement with off-site)
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/secrets/borg-passphrase";
    };
    compression = "auto,lzma";
    startAt = "daily";
    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
  };

  # Backup verification timer
  systemd.services.backup-verify = {
    description = "Verify BorgBackup integrity";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "verify-backup" ''
        ${pkgs.borgbackup}/bin/borg check /backup/borg \
          >> /var/log/backup-verify.log 2>&1
        echo "Backup verification completed: $(date)" >> /var/log/backup-verify.log
      '';
    };
  };
  systemd.timers.backup-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
```

### Recovery Targets

| Asset | RTO (Recovery Time Objective) | RPO (Recovery Point Objective) | Recovery Method |
|---|---|---|---|
| NixOS system configuration | 30 minutes | 0 (Git repository is authoritative) | `nixos-rebuild switch` from Git; or generation rollback |
| AI model files | 4 hours | 24 hours (daily BorgBackup) | Restore from BorgBackup; or re-download from source |
| Agent working data | 4 hours | 24 hours (daily BorgBackup) | Restore from BorgBackup |
| Audit logs | 8 hours | 24 hours (daily BorgBackup) | Restore from BorgBackup |
| Full system rebuild from scratch | 2 hours | 0 (flake is declarative and version-controlled) | Fresh NixOS install + `nixos-rebuild switch` from flake |

### Required Organizational Processes (Outside Flake)

- **Business Continuity Plan** (`/docs/policies/business-continuity-plan.md`):
  - RTO/RPO targets (as above)
  - Recovery procedures for each asset category
  - Communication plan during outages
  - Roles and responsibilities during recovery
- **Continuity Testing Schedule**:
  - **Quarterly**: Verify BorgBackup restoration for a subset of data
  - **Semi-annually**: Full system rebuild test from flake (new NixOS install on test hardware or VM)
  - **Annually**: Full business continuity exercise including communication and decision-making
- **Backup Monitoring**: Review backup-verify logs weekly; alert on failures
- **Off-site Backup**: BorgBackup repo should be replicated off-site (e.g., to a remote server or encrypted cloud storage)

### Evidence Artifacts for r2 Assessment
- Business continuity plan document
- RTO/RPO definitions with business justification
- BorgBackup configuration and job logs
- Backup verification logs (`/var/log/backup-verify.log`)
- Backup restoration test records (dated, with results)
- NixOS generation rollback test records
- Full system rebuild test records
- Continuity testing schedule and completion records
- `nixos-rebuild list-generations` showing generation availability

### Cross-References
- NIST SP 800-53: CP-1 through CP-13 (Contingency Planning family)
- HIPAA: 164.308(a)(7) Contingency Plan, 164.310(a)(2)(i) Contingency Operations
- PCI DSS v4.0: Requirement 12.10.2 (Incident response plan review)
- ISO 27001: A.17.1-A.17.2 (Information security continuity)

---

## Domain 13: Privacy Practices

### HITRUST Control References
- 13.a Privacy Notice and Consent
- 13.b Choice and Consent
- 13.c Collection
- 13.d Use, Retention, and Disposal
- 13.e Access
- 13.f Disclosure to Third Parties
- 13.g Security for Privacy
- 13.h Quality
- 13.i Monitoring and Enforcement
- 13.j Openness and Transparency
- 13.k Individual Participation and Redress

### Implementation Level Targets

| Level | Requirement | NixOS Implementation |
|---|---|---|
| **1** | Privacy practices documented; data handling procedures defined | Data flow documentation; log retention configuration; data minimization in agent sandbox |
| **2** | Consent management; data subject access procedures; privacy impact assessments | Procedural: privacy policies, DPA templates. Technical: data isolation via systemd sandboxing |
| **3** | Automated privacy controls; continuous privacy monitoring | Agent sandbox prevents unauthorized data access; audit logging tracks data access patterns |

This domain is **critical if the AI system processes personal data** (e.g., user prompts containing PII, inference outputs that reference individuals). Even if the system is intended for non-personal data processing, privacy practices must be documented.

### NixOS Configuration Mapping (Technical Privacy Controls)

```nix
# Privacy-relevant technical controls
{
  # Data minimization: Agent sandbox restricts data access
  systemd.services.agent-runner.serviceConfig = {
    # Agent can only access its own working directory
    ReadWritePaths = [ "/var/lib/agent-runner" ];
    ReadOnlyPaths = [ "/var/lib/ollama/models" ];
    ProtectHome = true;
    PrivateTmp = true;
    # No access to system-wide user data
  };

  # Data retention: Log retention limits prevent indefinite PII retention in logs
  services.journald.extraConfig = ''
    MaxRetentionSec=365day
  '';

  # Audit trails for data access (tracks who accessed what data)
  # auditd rules for agent_activity and model_access (configured in Domain 09)
}
```

### Required Organizational Processes (Outside Flake)

- **Privacy Policy** (`/docs/policies/privacy-policy.md`):
  - What personal data the AI system may process
  - Legal basis for processing (consent, legitimate interest, etc.)
  - Data retention periods
  - Data subject rights procedures
- **Data Subject Rights Procedures**:
  - Right of access: How to extract/provide data the system holds about an individual
  - Right to deletion: How to purge individual data from agent working directories and logs
  - Right to rectification: How to correct inaccurate data
  - Right to data portability: Export format for personal data
- **Consent Management** (if applicable):
  - How consent is obtained before processing personal data through the AI system
  - How consent withdrawal is handled
- **Data Minimization Assessment**:
  - Document what data the AI system actually needs to function
  - Ensure agent prompts do not unnecessarily include PII
  - Configure prompt templates to strip or anonymize PII where possible
- **Privacy Impact Assessment (PIA)**:
  - Required before deploying AI processing that involves personal data
  - Should address: data flows, risks to data subjects, mitigation measures
- **Data Processing Agreements (DPAs)**: Required with any third parties whose models or services process personal data

### Evidence Artifacts for r2 Assessment
- Privacy policy document
- Data flow diagram showing where personal data may enter and exit the AI system
- Data subject rights procedure documentation
- Privacy Impact Assessment (if personal data is processed)
- Agent sandbox configuration showing data access restrictions
- Log retention configuration
- auditd configuration showing data access audit trails
- Consent management procedures (if applicable)
- Data Processing Agreements with third parties (if applicable)

### Cross-References
- NIST SP 800-53: SI-12 (Information Handling), PT-1 through PT-8 (PII Processing and Transparency family)
- HIPAA: 164.520 (Notice of Privacy Practices), 164.522 (Rights to Request Privacy Protection), 164.524 (Access of Individuals), 164.526 (Amendment), 164.528 (Accounting of Disclosures)
- PCI DSS v4.0: Requirement 3 (Protect Stored Account Data), Requirement 7 (Restrict Access)
- ISO 27001: A.18.1.4 (Privacy and protection of PII)
- ISO 27701: Full privacy information management system framework

---

## Domains 14-18: Additional HITRUST Domains

> **Note**: HITRUST CSF v11 domains 14-18 address specialized areas that may or may not apply depending on assessment scope. Domain 14 (Endpoint Protection) is largely covered by Domain 09 controls (09.j-09.k). The controls below are organized by their HITRUST domain number for completeness but may overlap with controls already documented in earlier domains.

For this LAN-only AI inference server, Domains 14-18 are addressed through controls already documented in Domains 00-13. During formal MyCSF assessment, map specific requirement statements from these domains to the technical implementations documented in the relevant earlier domain sections.

---

## Evidence Generation Automation

### Automated Evidence Collection Script

The flake can include a systemd service that generates assessment evidence artifacts on demand or on a scheduled basis:

```nix
# Evidence generation - audit-and-aide module
{
  systemd.services.hitrust-evidence-collector = {
    description = "HITRUST assessment evidence collection";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "collect-evidence" ''
        EVIDENCE_DIR="/var/lib/hitrust-evidence/$(date +%Y-%m-%d)"
        mkdir -p "$EVIDENCE_DIR"

        # Domain 09 (Operations): Endpoint Protection
        ${pkgs.clamav}/bin/freshclam --version > "$EVIDENCE_DIR/clamav-version.txt"
        ${pkgs.aide}/bin/aide --check > "$EVIDENCE_DIR/aide-report.txt" 2>&1 || true

        # Domain 09 (Operations): Configuration Management
        cp /etc/nixos/flake.lock "$EVIDENCE_DIR/flake-lock-snapshot.json"
        ${pkgs.nix}/bin/nix-store --query --requisites /run/current-system \
          > "$EVIDENCE_DIR/system-closure.txt"
        nixos-rebuild list-generations > "$EVIDENCE_DIR/generations.txt"

        # Domain 10: Vulnerability Management
        ${pkgs.vulnix}/bin/vulnix --system > "$EVIDENCE_DIR/vulnix-scan.txt" 2>&1 || true

        # Domain 09 (Operations): Network Protection
        ${pkgs.nftables}/bin/nft list ruleset > "$EVIDENCE_DIR/firewall-rules.txt"
        ${pkgs.iproute2}/bin/ss -tlnp > "$EVIDENCE_DIR/listening-ports.txt"
        ${pkgs.iproute2}/bin/ip link show > "$EVIDENCE_DIR/network-interfaces.txt"

        # Domain 09 (Operations): Transmission Protection
        ${pkgs.openssh}/bin/sshd -T > "$EVIDENCE_DIR/sshd-config.txt" 2>&1

        # Domain 01: Password Management
        grep -E "^(PASS_|LOGIN_|ENCRYPT)" /etc/login.defs \
          > "$EVIDENCE_DIR/password-policy.txt"

        # Domain 01: Access Control
        getent passwd > "$EVIDENCE_DIR/user-accounts.txt"
        getent group > "$EVIDENCE_DIR/group-memberships.txt"
        cat /etc/sudoers > "$EVIDENCE_DIR/sudoers-config.txt" 2>/dev/null || true

        # Domain 09 (Operations): Audit Logging
        ${pkgs.audit}/bin/auditctl -l > "$EVIDENCE_DIR/audit-rules.txt"
        ${pkgs.systemd}/bin/journalctl --disk-usage > "$EVIDENCE_DIR/log-retention.txt"
        ${pkgs.chrony}/bin/chronyc tracking > "$EVIDENCE_DIR/time-sync.txt"

        # Domain 05: Third Party Assurance
        ${pkgs.nix}/bin/nix flake metadata > "$EVIDENCE_DIR/flake-metadata.txt" 2>&1 || true

        # Domain 07: Asset Management
        ${pkgs.nix}/bin/nix-store --query --requisites /run/current-system \
          > "$EVIDENCE_DIR/software-asset-inventory.txt"

        # Domain 12: Business Continuity
        ${pkgs.borgbackup}/bin/borg list /backup/borg > "$EVIDENCE_DIR/backup-inventory.txt" 2>&1 || true

        # Generate evidence manifest
        find "$EVIDENCE_DIR" -type f -exec sha256sum {} \; \
          > "$EVIDENCE_DIR/manifest.sha256"

        echo "Evidence collection complete: $EVIDENCE_DIR"
      '';
    };
  };

  systemd.timers.hitrust-evidence-collector = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "monthly";
      Persistent = true;
    };
  };
}
```

### Evidence Artifact Matrix

| HITRUST Domain | Automated Evidence | Manual Evidence Required |
|---|---|---|
| 00. Info Security Mgmt Program | Git repo history, module structure | Program charter, management approval |
| 01. Access Control | User/group lists, sudo logs, PAM config, session timeout test | Access review records, access policy, mobile scoping justification |
| 02. Human Resources Security | Login banners, MOTD, user provisioning Git history | Training records, screening procedures, termination checklists |
| 03. Risk Management | vulnix scans, AIDE reports | Risk register, risk assessment document, treatment plans |
| 04. Security Policy | Git-tracked policy documents with review dates | Policy approval records, distribution acknowledgments |
| 05. Organization of Information Security | flake.lock, SBOM, model checksums, cache config | Org chart, vendor assessments, BAAs, contracts |
| 06. Compliance | Compliance scan results, log retention config | Regulatory inventory, records retention schedule |
| 07. Asset Management | Nix system closure, flake metadata | Hardware inventory, classification scheme |
| 08. Physical & Environmental | USBGuard logs, kernel module list, LUKS status | Physical access logs, room documentation, environmental monitoring |
| 09. Communications & Operations | ClamAV logs, AIDE reports, firewall rules, audit rules, NTP status, SSH config, TLS test results | Network diagram, change management procedures, media handling procedure |
| 10. Systems Acquisition & Maintenance | vulnix scans, update logs, CVE timelines, flake.lock | Source code access controls, crypto key management procedures |
| 11. Incident Management | auditd config, log-alert service, evidence collector | IR plan, classification scheme, post-incident review records |
| 12. Business Continuity | BorgBackup logs, backup verification, generations list | BCP document, continuity test records, RTO/RPO definitions |
| 13. Privacy Practices | Agent sandbox config, data access audit trails, retention config | Privacy policy, PIA, data subject rights procedures, DPAs |

---

## Gap Analysis: HITRUST vs. Pure NIST + HIPAA

HITRUST CSF v11 incorporates NIST and HIPAA requirements but adds prescriptive specificity and additional controls. The following gaps exist when moving from a pure NIST+HIPAA-mapped configuration to HITRUST compliance:

### Prescriptive Thresholds HITRUST Adds

| Control Area | NIST/HIPAA Says | HITRUST Prescribes | Flake Impact |
|---|---|---|---|
| Password length | "Appropriate" (NIST); "Reasonable" (HIPAA) | Minimum 15 characters (Level 2) | `minlen = 15` in PAM |
| Password rotation | NIST 800-63B says do NOT rotate | Maximum 365-day age (Level 2) | `PASS_MAX_DAYS 365` in login.defs |
| Account lockout | "Appropriate threshold" | 5 attempts, 30-minute lock (Level 2) | `deny = 5; unlock_time = 1800` in PAM |
| Session timeout | "Appropriate period" | 15 minutes maximum (Level 2) | `TMOUT=900; ClientAliveInterval=300` |
| Vulnerability scan frequency | "Regularly" (NIST); not specified (HIPAA) | Monthly minimum (Level 2); weekly (Level 3) | `OnCalendar = "weekly"` for vulnix |
| Patch remediation | "Timely" (NIST); not specified (HIPAA) | Critical: 30 days (L2) / ASAP for actively-exploited (L3) | Operational procedure with tracked SLAs |
| Log retention | "Defined period" | 1 year minimum (Level 2); 6 years (Level 3) | `MaxRetentionSec=365day` |
| Anti-malware updates | "Regularly" | Daily minimum | `updater.frequency = 12` (ClamAV) |
| Encryption standard | "FIPS-validated" (NIST) | TLS 1.2 minimum; AES-128+ | Explicit cipher suite configuration |
| Access reviews | "Periodically" | Quarterly minimum (Level 2) | Operational procedure with dated records |
| Training | "Appropriate" | Annual minimum; role-based | Training records with completion dates |

### Structural Additions HITRUST Requires Beyond NIST+HIPAA

1. **Maturity scoring**: HITRUST requires evidence across 5 maturity levels (Policy, Procedure, Implemented, Measured, Managed). NIST and HIPAA only require implementation. The flake must support evidence generation for all five levels.

2. **Corrective Action Plans (CAPs)**: HITRUST mandates formal CAPs for any control scoring below 3 (Implemented). The Git-based change management of the flake provides the tracking mechanism.

3. **Third-party inheritance**: HITRUST allows controls to be "inherited" from service providers with their own HITRUST certification. For this LAN-only server, all controls are self-managed (no inheritance), which simplifies assessment but increases the evidence burden.

4. **Cross-framework mapping**: HITRUST explicitly maps to 40+ authoritative sources. The flake's control matrix must reference HITRUST control IDs alongside NIST/HIPAA/ISO/PCI references, not as parallel mappings but as unified HITRUST references that subsume the others.

5. **Prescriptive evidence formats**: HITRUST assessors expect specific evidence types (screenshots, configuration exports, interview notes) per control. The evidence generation automation produces machine-readable artifacts that must be supplemented with assessor-specific documentation.

6. **Alternate controls**: Where prescriptive HITRUST requirements cannot be met (e.g., wireless security for a wired-only host), HITRUST uses the **alternate control** mechanism. This is distinct from PCI DSS "compensating controls." Alternate control requests must be formally submitted through MyCSF with justification documenting why the prescriptive requirement cannot be met and how the alternate control provides equivalent assurance.

7. **Threat-adaptive controls (CSF v11)**: The i1 assessment path uses the HITRUST Threat Catalogue to select controls based on current threat intelligence. The 219 i1 requirement statements may be updated between assessment cycles as the threat landscape evolves.

### Controls HITRUST Adds with No Direct NIST/HIPAA Equivalent

| HITRUST Control | Requirement | This System's Response |
|---|---|---|
| 09.j (malware scanning frequency) | Specific scan schedules per asset type | ClamAV daemon + scheduled full scans |
| 01.r (password management system) | Automated enforcement of all password parameters | PAM pwquality + faillock + pam_pwhistory |
| 09.o (removable media) | Default-deny with explicit exception process | Kernel module blacklist + USBGuard |
| 05.k (third-party agreements) | Formal security requirements in all vendor agreements | Model provenance documentation + SBOM |
| 09.af (clock synchronization) | Specific accuracy and audit requirements | Chrony with maxdistance + auditd time rules |

---

## Maturity Scoring Targets

### Year 1 Assessment Targets (i1)

| Domain | Target Maturity | Justification |
|---|---|---|
| 00. Info Security Mgmt Program | 3 (Implemented) | Flake structure + policies documented and operational |
| 01. Access Control | 3 (Implemented) | PAM, SSH, sudo, sandbox controls deployed and operating |
| 02. Human Resources Security | 2 (Procedure) | Requires operational training program buildout; procedures documented but not yet fully executed |
| 03. Risk Management | 3 (Implemented) | Risk assessment completed; risk register maintained; technical evidence feeding risk process |
| 04. Security Policy | 3 (Implemented) | Policy documented, approved, and distributed |
| 05. Organization of Information Security | 3 (Implemented) | Roles assigned; third-party controls implemented |
| 06. Compliance | 3 (Implemented) | Regulatory inventory documented; technical compliance checking operational |
| 07. Asset Management | 3 (Implemented) | Nix provides automated software inventory; classification scheme documented |
| 08. Physical & Environmental | 3 (Implemented) | Host-level controls deployed; physical measures documented |
| 09. Communications & Operations | 3 (Implemented) | All technical controls deployed: firewall, encryption, logging, NTP, AIDE, ClamAV |
| 10. Systems Acquisition & Maintenance | 3 (Implemented) | vulnix scanning operational; patch management process defined |
| 11. Incident Management | 3 (Implemented) | Detection controls deployed; IR plan documented; evidence collection automated |
| 12. Business Continuity | 3 (Implemented) | BorgBackup operational; NixOS rollback available; RTO/RPO defined |
| 13. Privacy Practices | 3 (Implemented) | Privacy controls documented; data access restrictions enforced |
| Wireless Security (09.m subset) | N/A | Scoped out -- no wireless interfaces; alternate control documented |
| Mobile Device (01.x-01.y subset) | N/A | Scoped out -- LAN-only server; alternate control documented |

### Year 2 Progression Targets (r2 Readiness)

| Domain | Target Maturity | Requirements to Achieve |
|---|---|---|
| 00. Info Security Mgmt Program | 4 (Measured) | Quarterly program effectiveness metrics; management review evidence |
| 01. Access Control | 4 (Measured) | 4 quarters of access review records; access anomaly metrics and trend reports |
| 02. Human Resources Security | 3 (Implemented) | Training program fully operational with completion records |
| 03. Risk Management | 4 (Measured) | Risk register reviewed quarterly with documented changes; risk trend reporting |
| 04. Security Policy | 3 (Implemented) | Maintain current; policy review completed |
| 05. Organization of Information Security | 3 (Implemented) | Maintain current; vendor review cycle completed |
| 06. Compliance | 4 (Measured) | Compliance metrics tracked; quarterly compliance status reports |
| 07. Asset Management | 3 (Implemented) | Maintain current; annual inventory reconciliation completed |
| 08. Physical & Environmental | 3 (Implemented) | Maintain current; physical access review completed |
| 09. Communications & Operations | 4 (Measured) | 4 quarters of operational metrics (uptime, incidents, drift detection); management review |
| 10. Systems Acquisition & Maintenance | 4 (Measured) | Vulnerability remediation timeline metrics; patch SLA compliance reporting |
| 11. Incident Management | 4 (Measured) | Incident metrics (MTTR, volume, categories); post-incident review evidence |
| 12. Business Continuity | 4 (Measured) | Backup success rate metrics; restoration test results; continuity test outcomes |
| 13. Privacy Practices | 3 (Implemented) | Maintain current; PIA completed if processing personal data |

> **Level 5 (Managed)** is not targeted in Year 2. Achieving Level 5 requires evidence of continuous improvement driven by measurement data over multiple review cycles, which realistically requires Year 3 or later for any domain.

---

## Implementation Checklist

### Pre-Assessment (60 Days Before)

- [ ] Complete all NixOS module implementations per this document
- [ ] Ensure `pam_pwhistory` is configured via PAM `.text` override (see Domain 01)
- [ ] Verify nftables configuration (NixOS 24.11 default) or explicitly set `networking.nftables.enable = false`
- [ ] Verify Nginx SSL settings use `appendHttpConfig` (not top-level `sslProtocols`/`sslCiphers`)
- [ ] Run `hitrust-evidence-collector` service and verify all artifacts generate
- [ ] Complete all supplemental policy documents in `/docs/policies/`:
  - [ ] Information Security Policy (Domain 04)
  - [ ] Risk Register and Risk Assessment (Domain 03)
  - [ ] Incident Response Plan (Domain 11)
  - [ ] Business Continuity Plan (Domain 12)
  - [ ] Privacy Policy and PIA (Domain 13)
  - [ ] Physical Security Documentation (Domain 08)
  - [ ] Asset Inventory and Classification (Domain 07)
  - [ ] HR Security Procedures (Domain 02)
- [ ] Conduct internal gap assessment using HITRUST MyCSF tool
- [ ] Map technical controls to MyCSF requirement statement IDs (format: e.g., "19748v2")
- [ ] Review current HITRUST Threat Catalogue for i1 assessment applicability
- [ ] Schedule quarterly access reviews and document first cycle
- [ ] Complete security awareness training for all users with records
- [ ] Submit alternate control requests for N/A domains (wireless, mobile) via MyCSF

### During Assessment

- [ ] Provide assessor with read-only access to Git repository
- [ ] Generate fresh evidence collection (`systemctl start hitrust-evidence-collector`)
- [ ] Prepare network diagram and data flow documentation
- [ ] Make available: sudo logs, audit logs, AIDE reports, vulnix scans
- [ ] Demonstrate `nixos-rebuild` process for configuration management evidence
- [ ] Demonstrate rollback capability via NixOS generations
- [ ] Demonstrate BorgBackup restoration capability
- [ ] Provide MyCSF requirement statement ID mapping for all technical controls

### Post-Assessment

- [ ] Address any Corrective Action Plans (CAPs) through flake updates
- [ ] Track CAP remediation in Git with HITRUST control ID references
- [ ] Schedule 90-day interim evidence collection for CAP closure
- [ ] Begin quarterly metric collection for Year 2 Level 4 targets
- [ ] Plan next assessment cycle (annual for r2 validated)

---

## Appendix A: HITRUST CSF v11 Domain Quick Reference

| Domain | Key Control IDs | Primary NixOS Module |
|---|---|---|
| 00. Info Security Mgmt Program | 0.a | Flake structure |
| 01. Access Control | 01.a-01.y | stig-baseline + agent-sandbox |
| 02. Human Resources Security | 02.a-02.e | stig-baseline (banners) + organizational |
| 03. Risk Management | 03.a-03.d | Organizational + vulnix/AIDE evidence |
| 04. Security Policy | 04.a-04.b | Organizational + Git-tracked policies |
| 05. Organization of Info Security | 05.a, 05.b, 05.i-05.k | Flake inputs + ai-services |
| 06. Compliance | 06.a-06.i | audit-and-aide + organizational |
| 07. Asset Management | 07.a-07.e | Nix store + organizational |
| 08. Physical & Environmental | 08.a-08.l | stig-baseline (USB, encryption) + organizational |
| 09. Communications & Operations | 09.a-09.af | All modules (largest domain) |
| 10. Systems Acquisition & Maintenance | 10.a-10.m | audit-and-aide + Flake |
| 11. Incident Management | 11.a-11.e | audit-and-aide + organizational |
| 12. Business Continuity | 12.a-12.e | BorgBackup + NixOS generations |
| 13. Privacy Practices | 13.a-13.k | agent-sandbox + organizational |
| 14-18. Additional Domains | (varies) | Covered by Domains 00-13 controls |

## Appendix B: Cross-Framework Reference Matrix

| HITRUST Domain | NIST 800-53 Families | HIPAA Sections | PCI DSS v4.0 Requirements | ISO 27001/27002 Clauses |
|---|---|---|---|---|
| 00. Info Security Mgmt Program | PM-1 | 164.308(a)(1) | 12.1 | A.5.1 |
| 01. Access Control | AC-2, AC-3, AC-6, AC-7, AC-11, AC-12, AC-19, IA-5 | 164.312(a)(1), 164.312(d), 164.310(b-c) | 7, 8 | A.9.1-A.9.4, A.6.2 |
| 02. Human Resources Security | AT-1, AT-2, AT-3, PS-1 through PS-8 | 164.308(a)(3), 164.308(a)(5) | 12.6, 12.7 | A.7.1-A.7.3 |
| 03. Risk Management | RA-1, RA-2, RA-3, RA-7 | 164.308(a)(1)(ii)(A-B) | 12.3 | Clause 6.1, A.8.2-A.8.3 |
| 04. Security Policy | PL-1, PM-1 | 164.316(a) | 12.1 | A.5.1, A.5.2 |
| 05. Organization of Info Security | PM-2, SA-9, SR-3, SR-4 | 164.308(a)(2), 164.308(b)(1) | 12.8, 6.3 | A.6.1, A.15.1-A.15.2 |
| 06. Compliance | SA-15, AU-11, SC-13 | 164.316(b)(2), 164.308(a)(8) | 12.4 | A.18.1-A.18.2 |
| 07. Asset Management | CM-8, MP-4, RA-2 | 164.310(d)(1) | 9.4, 12.5 | A.8.1-A.8.3 |
| 08. Physical & Environmental | PE-1 through PE-20 | 164.310(a-d) | 9 | A.11.1-A.11.2 |
| 09. Communications & Operations | CM-2, CM-3, CM-6, CM-7, SI-3, SI-7, SC-7, AC-4, SC-5, AC-18, MP-2, MP-6, MP-7, SC-8, SC-13, AU-2 through AU-9 | 164.312(b), 164.308(a)(5)(ii)(B), 164.312(e)(1), 164.310(d)(1), 164.308(a)(8), 164.308(a)(1)(ii)(D) | 1, 2.1.1, 4, 5, 6.5, 9.4.5, 10, 11.3.1 | A.10.1, A.12.1-A.12.7, A.13.1-A.13.2, A.14.2 |
| 10. Systems Acquisition & Maintenance | RA-5, SI-2, SA-3, SA-11 | 164.308(a)(1)(ii)(B) | 6.2, 6.3, 11.3 | A.14.1-A.14.3 |
| 11. Incident Management | IR-1 through IR-10, AU-6 | 164.308(a)(6), 164.404-164.410 | 12.10 | A.16.1 |
| 12. Business Continuity | CP-1 through CP-13 | 164.308(a)(7), 164.310(a)(2)(i) | 12.10.2 | A.17.1-A.17.2 |
| 13. Privacy Practices | SI-12, PT-1 through PT-8 | 164.520-164.528 | 3, 7 | A.18.1.4, ISO 27701 |
