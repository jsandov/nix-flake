# PRD Module: NIST SP 800-53 Rev 5 Control Mapping

## Overview

This document is a compliance-specific module of the main PRD for the Control-Mapped NixOS AI Agentic Server. It provides a comprehensive mapping of the system design to all 20 control families defined in NIST SP 800-53 Revision 5.

The purpose of this module is to:

1. Establish which NIST 800-53 controls are directly addressable through the NixOS flake configuration and host-level enforcement.
2. Identify which controls require organizational process, policy documentation, or governance activity outside the technical build.
3. Define concrete NixOS implementation requirements for each applicable control.
4. Specify evidence artifacts that each control requires for audit readiness.

This mapping targets a **Moderate** baseline unless otherwise noted. The system operates as a LAN-only, single-host GPU inference server with sandboxed agent workloads. It is not a multi-tenant cloud service or an Internet-facing application. Control applicability is scoped accordingly.

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the framework-specific rationale; the implementation flake uses only the canonical values.

### Relationship to Main PRD

The main PRD defines functional requirements, acceptance criteria, and a cross-framework control matrix (STIG, HIPAA, OWASP). This module extends that work with full NIST 800-53 Rev 5 coverage, providing the control-by-control technical specification that the flake modules (`stig-baseline`, `gpu-node`, `lan-only-network`, `audit-and-aide`, `agent-sandbox`, `ai-services`) must satisfy.

### System Scope Summary

| Component | Ports / Interfaces | Flake Module |
|---|---|---|
| SSH (administration) | TCP 22, LAN interface only | `stig-baseline`, `lan-only-network` |
| Ollama (inference API) | TCP 11434, LAN interface only | `ai-services`, `lan-only-network` |
| Application APIs | TCP 8000, LAN interface only | `ai-services`, `lan-only-network` |
| Agent runners | No listening ports; outbound restricted | `agent-sandbox` |
| AIDE / audit subsystem | No listening ports | `audit-and-aide` |
| GPU runtime (NVIDIA/CUDA) | No listening ports | `gpu-node` |

---

## Control Family Mapping

### 1. AC -- Access Control

**Applicability**: Host/OS/runtime layer (primary) + organizational process (supporting).

#### Applicable Controls

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| AC-2 | Account Management | Host + Org | Declare all user accounts in Nix config (`users.users.*`). No interactive account creation outside config. Service accounts (`agent`, `ollama`, `ai-api`) declared with `isSystemUser = true`, `shell = pkgs.shadow/nologin`. Organizational process required for account review cadence. |
| AC-3 | Access Enforcement | Host | File permissions enforced via NixOS declarative state. Systemd service units use `User`, `Group`, `ReadWritePaths`, `ProtectSystem = "strict"`, `ProtectHome = true`. SELinux or AppArmor profiles optional but not primary enforcement mechanism on NixOS. |
| AC-4 | Information Flow Enforcement | Host + Org | `networking.firewall.enable = true`. Default deny on all interfaces. Only `interfaces.<lan>.allowedTCPPorts = [ 22 11434 8000 ]`. Agent sandbox services use `RestrictAddressFamilies` and `IPAddressDeny` to block unauthorized egress. |
| AC-5 | Separation of Duties | Org (primary) | Separate `admin` account from service accounts in `users.users`. No shared credentials. Organizational process defines who can run `nixos-rebuild` vs. who can access agent outputs. |
| AC-6 | Least Privilege | Host | All services run as dedicated unprivileged users. `NoNewPrivileges = true` on all agent and AI service units. `security.sudo.extraRules` restricts sudo to named admin users only. `security.polkit` rules restrict privileged D-Bus operations. |
| AC-6(1) | Least Privilege: Authorize Access to Security Functions | Host | Only `admin` user in `wheel` group. `security.sudo.wheelNeedsPassword = true`. |
| AC-6(9) | Least Privilege: Log Use of Privileged Functions | Host | `security.auditd.enable = true` with audit rules for `execve` by uid 0, `sudo` invocations, and `su` attempts. |
| AC-6(10) | Least Privilege: Prohibit Non-Privileged Users from Executing Privileged Functions | Host | Enforced via sudo config and systemd sandboxing. No SUID binaries outside base system (`security.wrappers` audited). |
| AC-7 | Unsuccessful Logon Attempts | Host | `security.pam.services.sshd.failDelay.delay = 4000000`. `services.fail2ban.enable = true` with jail for sshd. |
| AC-8 | System Use Notification | Host | `services.openssh.banner` set to approved notice text. `/etc/issue` and `/etc/motd` set via `environment.etc` with legal/consent banner. |
| AC-10 | Concurrent Session Control | Host | `services.openssh.settings.MaxSessions = 3`. PAM `pam_limits` configuration via `security.pam.loginLimits`. |
| AC-11 | Device Lock | Host | `programs.tmux.enable = true` with lock-after-idle. `services.logind.extraConfig` sets `IdleAction=lock` and `IdleActionSec=900`. |
| AC-12 | Session Termination | Host | `services.openssh.settings.ClientAliveInterval = 300` and `ClientAliveCountMax = 3`. Systemd service timeouts on agent runners via `TimeoutStopSec`. |
| AC-14 | Permitted Actions Without Identification or Authentication | Host + Org | No actions are permitted without identification and authentication. All SSH access requires public key + MFA (IA-2, IA-2(1)). All API services are accessible only from the authenticated LAN segment (SC-7). No anonymous or unauthenticated endpoints are exposed. This is documented as a system design decision. |
| AC-17 | Remote Access | Host + Org | SSH is the sole remote access method. `services.openssh.settings.PasswordAuthentication = false`, `KbdInteractiveAuthentication = true` (for TOTP MFA), `PermitRootLogin = "no"`, `AllowUsers = [ "admin" ]`. MFA enforced via `AuthenticationMethods = "publickey,keyboard-interactive"` with google-authenticator PAM (see IA-2(1)). |
| AC-18 | Wireless Access | Host | Not applicable if host has no wireless interface. If present: `networking.wireless.enable = false` and interface disabled via `networking.interfaces.wlan0.useDHCP = false`. |
| AC-19 | Access Control for Mobile Devices | Org | Not applicable to a stationary server. Organizational policy documents this scoping decision. |
| AC-20 | Use of External Information Systems | Org | Agent sandbox `IPAddressDeny = "any"` or allowlisted egress only. Organizational policy governs what external data sources agents may query. |

#### Gaps Requiring Organizational Process

- AC-2: Periodic account review schedule and evidence of review.
- AC-5: Documented separation of duties matrix.
- AC-19, AC-20: Policy documentation for scoping and external system use.

---

### 2. AT -- Awareness and Training

**Applicability**: Organizational process only. No host-level technical controls.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| AT-1 | Policy and Procedures | Org | Documented security awareness and training policy. |
| AT-2 | Literacy Training and Awareness | Org | Operator must complete security training covering AI-specific risks (prompt injection, tool misuse, data exfiltration via agent). |
| AT-3 | Role-Based Training | Org | Training records for admin role on NixOS rebuild procedures, incident response, and agent monitoring. |
| AT-4 | Training Records | Org | Retained training documentation. |

**NixOS Implementation**: None. Entirely organizational.

---

### 3. AU -- Audit and Accountability

**Applicability**: Host/OS/runtime layer (primary).

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| AU-2 | Event Logging | Host | `security.auditd.enable = true`. Audit rules must capture: successful/failed logins, privilege escalation, file access to sensitive paths (`/etc/shadow`, `/var/lib/agent-runner`, `/var/lib/ollama`), process execution by service accounts, systemd unit start/stop/fail events. |
| AU-3 | Content of Audit Records | Host | Audit rules configured via `security.audit.rules` to include: event type, timestamp, source address, user identity, outcome. Systemd journal captures structured metadata by default. |
| AU-3(1) | Additional Audit Information | Host | Agent sandbox logs must include: tool name invoked, approval decision, input hash (not raw input if sensitive), execution duration, exit code. Implemented in `ai-services` module logging config. |
| AU-4 | Audit Log Storage Capacity | Host | `services.journald.extraConfig` sets `SystemMaxUse=2G`, `SystemKeepFree=1G`. Separate partition or volume for `/var/log` recommended. AIDE database stored on read-only path. |
| AU-5 | Response to Audit Logging Process Failures | Host + Org | `systemd.services.auditd` configured with `Restart=always`. Alerting on audit subsystem failure via `OnFailure=notify-admin@.service`. Organizational process defines escalation. |
| AU-6 | Audit Record Review, Analysis, and Reporting | Org (primary) + Host | Organizational process defines review cadence. Host provides `journalctl` queries and AIDE reports as evidence artifacts. Automated log forwarding to syslog collector if available. |
| AU-7 | Audit Record Reduction and Report Generation | Host | `journalctl` filtering by unit, priority, time range. Custom systemd timer for weekly audit summary generation script. |
| AU-8 | Time Stamps | Host | `services.timesyncd.enable = true` or `services.chrony.enable = true`. `networking.timeServers` pointed to LAN NTP or trusted upstream. Audit records use system clock. |
| AU-9 | Protection of Audit Information | Host | `/var/log/audit` owned by root with mode 0700. `security.audit.rules` includes rules to detect tampering with audit logs. Agent sandbox has no write access to `/var/log`. |
| AU-10 | Non-Repudiation | Host | Each agent runner executes under a dedicated system UID (`agent`), and all actions are logged to the systemd journal with `SyslogIdentifier` tagging (AU-2). Audit rules capture `execve` calls with UID attribution, ensuring all agent actions are attributable to a specific service identity. Combined with protected audit logs (AU-9) and timestamps (AU-8), this provides non-repudiation for agent-initiated actions. |
| AU-11 | Audit Record Retention | Host + Org | `services.journald.extraConfig` sets `MaxRetentionSec=90day`. Organizational policy defines retention period. Backup of audit logs to external storage per organizational procedure. |
| AU-12 | Audit Record Generation | Host | Enabled via `security.auditd.enable = true` with rules covering all AU-2 events. Each flake module must not disable or suppress audit subsystem. |

#### Evidence Artifacts

- `/var/log/audit/audit.log` -- raw kernel audit trail.
- `journalctl --output=json` exports -- structured systemd journal.
- AIDE database and diff reports -- integrity change evidence.
- Agent-specific logs in `/var/log/agent-runner/` -- tool invocation records.

---

### 4. CA -- Assessment, Authorization, and Monitoring

**Applicability**: Organizational process (primary) + host-level monitoring support.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| CA-1 | Policy and Procedures | Org | Documented assessment and authorization policy. |
| CA-2 | Control Assessments | Org | Periodic assessment against this control mapping. NixOS config diff (`nixos-rebuild dry-build`) provides technical evidence. |
| CA-3 | Information Exchange | Org + Host | LAN-only scope limits information exchange paths. Firewall rules provide technical enforcement. Organizational agreements (ISAs/MOUs) required for any external data flows. |
| CA-5 | Plan of Action and Milestones | Org | POA&M tracking for identified gaps in this document. |
| CA-7 | Continuous Monitoring | Host + Org | AIDE hourly integrity checks (`systemd.timers.aide-check`). `systemd.services.aide-check` with `OnFailure` notification. Drift detection compares running config to declared flake state. |
| CA-8 | Penetration Testing | Org | Organizational process. Host supports testing via standard tooling. |
| CA-9 | Internal System Connections | Host + Org | All internal connections documented in flake config (port bindings, service dependencies). Organizational process reviews and approves. |

---

### 5. CM -- Configuration Management

**Applicability**: Host/OS/runtime layer (primary). This is where NixOS provides the strongest native alignment.

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| CM-1 | Policy and Procedures | Org | Documented CM policy referencing the flake repository as the authoritative configuration source. |
| CM-2 | Baseline Configuration | Host | The `flake.nix` and all imported modules constitute the baseline. `nixos-rebuild switch` applies the declared state. Previous generations retained for rollback. Git history of the flake repository provides full baseline change history. |
| CM-2(1) | Baseline Configuration: Reviews and Updates | Org + Host | Organizational cadence for baseline review. Git tags or branches mark approved baselines. `nix flake metadata` and `nix flake lock --update-input` track input versions. |
| CM-3 | Configuration Change Control | Host + Org | All changes go through flake repo commits. CI/CD or manual review before `nixos-rebuild switch`. `git log` provides change records. Organizational process defines approval gates. |
| CM-4 | Impact Analysis | Org + Host | `nixos-rebuild dry-build` and `nix build` detect build failures before apply. `nixos-rebuild test` applies without making the generation default. Organizational review of changes for security impact. |
| CM-5 | Access Restrictions for Change | Host + Org | Only `admin` user (in `wheel` group) can run `nixos-rebuild`. Flake repo access controlled via Git hosting permissions. |
| CM-6 | Configuration Settings | Host | Each module enforces specific settings: `stig-baseline` sets SSH hardening, PAM config, audit rules, banner text. `lan-only-network` sets firewall rules. `agent-sandbox` sets systemd sandboxing directives. Settings are declarative and auditable. |
| CM-7 | Least Functionality | Host | `environment.systemPackages` lists only required packages. `services.*.enable = false` for all non-required services. `boot.kernel.sysctl` disables unnecessary kernel features (e.g., `net.ipv4.ip_forward = false`). No GUI, no desktop environment. |
| CM-7(1) | Least Functionality: Periodic Review | Org + Host | `nix-store --query --requisites /run/current-system` lists all installed packages for review. Organizational process defines review cadence. |
| CM-8 | System Component Inventory | Host | `nixos-generate-config` and `nix flake show` provide complete component inventory. `nix-store --query --tree /run/current-system` shows full dependency graph. |
| CM-9 | Configuration Management Plan | Org | Documented plan referencing flake-based workflow, Git repository, rebuild procedures. |
| CM-10 | Software Usage Restrictions | Host + Org | Nix store is read-only; users cannot install packages outside the declared config. `nix.settings.allowed-users = [ "admin" ]` restricts who can use the Nix CLI. |
| CM-11 | User-Installed Software | Host | Blocked by design. The Nix store is immutable. Non-admin users cannot run `nix-env` or `nix profile install`. `nix.settings.allowed-users = [ "admin" ]`. |

#### Evidence Artifacts

- Git history of flake repository -- full change log with diffs.
- `nixos-rebuild list-generations` output -- generation timeline.
- `nix flake metadata` -- input source pins and lock file state.
- `nix-store --query --requisites /run/current-system` -- package inventory.
- AIDE reports -- drift detection evidence.

---

### 6. CP -- Contingency Planning

**Applicability**: Organizational process (primary) + host-level recovery support.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| CP-1 | Policy and Procedures | Org | Documented contingency planning policy. |
| CP-2 | Contingency Plan | Org + Host | Documented plan. NixOS provides: `nixos-rebuild switch --rollback` for instant rollback to previous generation. Flake repo in Git enables full rebuild from scratch on replacement hardware. |
| CP-4 | Contingency Plan Testing | Org | Periodic rebuild-from-scratch testing on clean hardware or VM. |
| CP-6 | Alternate Storage Site | Org | Off-host backup of flake repo (Git remote), audit logs, and AIDE databases. |
| CP-7 | Alternate Processing Site | Org | Not applicable for single-host LAN server unless organizational policy requires. |
| CP-9 | System Backup | Host + Org | Flake repo in Git constitutes full system configuration backup. Model artifacts, agent data, and audit logs backed up per organizational schedule. `systemd.services.backup-*` timers for automated backup jobs if needed. |
| CP-10 | System Recovery and Reconstitution | Host | `nixos-rebuild switch` from flake restores full system state. `boot.loader.systemd-boot.configurationLimit` retains N previous generations for rollback. LUKS key escrow per organizational process. |

#### NixOS-Specific Recovery Procedure

```nix
{
  # Retain last 10 generations for rollback
  boot.loader.systemd-boot.configurationLimit = 10;

  # Ensure flake registry is pinned for reproducible rebuilds
  nix.settings.flake-registry = "";
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
}
```

---

### 7. IA -- Identification and Authentication

**Applicability**: Host/OS/runtime layer (primary).

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| IA-1 | Policy and Procedures | Org | Documented I&A policy. |
| IA-2 | Identification and Authentication (Organizational Users) | Host | All human users authenticate via SSH public key. `services.openssh.settings.PasswordAuthentication = false`. Each admin has a unique named account (`users.users.admin`). |
| IA-2(1) | Multi-Factor Authentication to Privileged Accounts | Host + Org | MFA required for all privileged (admin) SSH access. Implemented via TOTP with google-authenticator PAM module. SSH configured to require both public key and keyboard-interactive (TOTP) authentication. See IA-2(1) implementation below. |
| IA-2(2) | Multi-Factor Authentication to Non-Privileged Accounts | Host | If non-privileged interactive users exist, same PAM MFA config applies. For this system, the only interactive account is `admin`. |
| IA-3 | Device Identification and Authentication | Org + Host | SSH host keys serve as device authentication. `services.openssh.hostKeys` declared in config. Client-side `known_hosts` verification. |
| IA-4 | Identifier Management | Host + Org | User identifiers (usernames, UIDs) declared in `users.users.*` and `users.groups.*`. No shared accounts. Service accounts use system UIDs. |
| IA-5 | Authenticator Management | Host + Org | SSH keys managed outside Nix store. `sops-nix` for encrypted secrets (project decision; agenix not supported). `users.users.admin.openssh.authorizedKeys.keys` declares authorized public keys in config. Private keys never in repo. |
| IA-5(1) | Authenticator Management: Password-Based Authentication | Host | Password auth disabled for SSH. If local console access uses passwords: `security.pam.services.login` with password complexity via `security.pam.services.login.rules.password` using `pam_pwquality`. |
| IA-6 | Authentication Feedback | Host | Default PAM behavior obscures passwords. SSH key auth does not display authenticator. |
| IA-8 | Identification and Authentication (Non-Organizational Users) | N/A | No non-organizational users. LAN-only, single-operator system. |
| IA-11 | Re-Authentication | Host | `sudo` timestamp timeout via `security.sudo.extraConfig = "Defaults timestamp_timeout=5"` forces re-authentication for privilege escalation. Note: `ClientAliveInterval` is a session keepalive/termination mechanism (see AC-12, SC-10), not a re-authentication control. |

#### NixOS Implementation: IA-2(1) Multi-Factor Authentication

```nix
{
  # IA-2(1): MFA for privileged SSH access via TOTP (google-authenticator)
  security.pam.services.sshd = {
    googleAuthenticator.enable = true;
  };

  services.openssh.settings = {
    # Require both public key AND keyboard-interactive (TOTP) for MFA
    AuthenticationMethods = "publickey,keyboard-interactive";
    KbdInteractiveAuthentication = true;
  };

  environment.systemPackages = [ pkgs.google-authenticator ];
}
```

Each admin user must run `google-authenticator` on first login to generate their TOTP secret. The resulting `~/.google_authenticator` file stores the secret and scratch codes. Backup of TOTP secrets is an organizational process responsibility.

---

### 8. IR -- Incident Response

**Applicability**: Organizational process (primary) + host-level forensic support.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| IR-1 | Policy and Procedures | Org | Documented incident response policy. |
| IR-2 | Incident Response Training | Org | Operator training on NixOS-specific incident procedures (generation rollback, audit log review, agent shutdown). |
| IR-3 | Incident Response Testing | Org | Periodic tabletop exercises. |
| IR-4 | Incident Handling | Org + Host | Host provides: `systemctl stop agent-runner` to halt agents immediately. `nixos-rebuild switch --rollback` to revert to last known good state. `journalctl` and audit logs for forensic timeline. AIDE reports for integrity analysis. |
| IR-5 | Incident Monitoring | Host + Org | Audit subsystem and AIDE provide detection. `systemd.services.aide-check` with `OnFailure` triggers notification. Agent log monitoring for anomalous tool invocations. |
| IR-6 | Incident Reporting | Org | Organizational reporting procedures. Host logs provide evidence. |
| IR-7 | Incident Response Assistance | Org | Organizational contacts and escalation paths. |
| IR-8 | Incident Response Plan | Org | Documented plan including NixOS-specific procedures. |

#### NixOS Incident Response Capabilities

```nix
{
  # Emergency agent shutdown service
  systemd.services.emergency-agent-halt = {
    description = "Emergency halt of all agent services";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl stop agent-runner.service";
    };
  };

  # Forensic snapshot timer (optional)
  systemd.services.forensic-snapshot = {
    description = "Capture system state snapshot for incident analysis";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "forensic-snapshot" ''
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        OUTDIR="/var/lib/forensics/$TIMESTAMP"
        mkdir -p "$OUTDIR"
        ${pkgs.systemd}/bin/journalctl --since "24 hours ago" --output=json > "$OUTDIR/journal.json"
        ${pkgs.iproute2}/bin/ss -tulnp > "$OUTDIR/network-connections.txt"
        ${pkgs.procps}/bin/ps auxf > "$OUTDIR/process-tree.txt"
        ${pkgs.aide}/bin/aide --check > "$OUTDIR/aide-report.txt" 2>&1 || true
        ${pkgs.coreutils}/bin/sha256sum "$OUTDIR"/* > "$OUTDIR/manifest.sha256"
      '';
    };
  };
}
```

---

### 9. MA -- Maintenance

**Applicability**: Organizational process (primary) + host-level update support.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| MA-1 | Policy and Procedures | Org | Documented maintenance policy. |
| MA-2 | Controlled Maintenance | Org + Host | System updates via `nix flake update` and `nixos-rebuild switch`. All changes tracked in Git. Maintenance windows defined by organizational process. |
| MA-3 | Maintenance Tools | Host + Org | Only tools in `environment.systemPackages` available. No ad-hoc tool installation. Nix store immutability prevents unauthorized tool deployment. |
| MA-4 | Nonlocal Maintenance | Host | SSH is the only remote maintenance channel. Hardened per AC-17 and IA-2 controls. All sessions logged per AU-2. |
| MA-5 | Maintenance Personnel | Org | Organizational process for personnel authorization. Host enforces via `AllowUsers` in SSH config. |
| MA-6 | Timely Maintenance | Org + Host | `nix flake update` pulls security patches. `nixos-rebuild switch` applies them atomically. Organizational process defines patching cadence and SLAs. |

---

### 10. MP -- Media Protection

**Applicability**: Host/OS layer (encryption) + organizational process (physical media).

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| MP-1 | Policy and Procedures | Org | Documented media protection policy. |
| MP-2 | Media Access | Host + Org | Full-disk encryption via LUKS (`boot.initrd.luks.devices`). Physical access to server controlled by organizational process. |
| MP-3 | Media Marking | Org | Organizational process for labeling media containing model artifacts or sensitive data. |
| MP-4 | Media Storage | Host + Org | LUKS encryption protects data at rest. `boot.initrd.luks.devices."root".device` configured for root partition. Organizational process for secure physical storage. |
| MP-5 | Media Transport | Org | Organizational process. Relevant for backup media, model transport. |
| MP-6 | Media Sanitization | Org + Host | `nix-collect-garbage -d` removes old generations and unused store paths. Physical media sanitization (NIST 800-88) is organizational process. |
| MP-7 | Media Use | Host | USB storage can be blocked via `services.udev.extraRules` denying mass storage devices. `boot.kernel.sysctl."kernel.modules_disabled" = 1` after boot prevents loading USB storage modules. |

#### NixOS Implementation

```nix
{
  # Full-disk encryption
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/<UUID>";
    preLVM = true;
    allowDiscards = true;  # For SSD TRIM; evaluate security tradeoff
  };

  # Block USB mass storage (if policy requires)
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEMS=="usb", DRIVERS=="usb-storage", ATTR{authorized}="0"
  '';
}
```

---

### 11. PE -- Physical and Environmental Protection

**Applicability**: Organizational process only. NixOS configuration cannot enforce physical controls.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| PE-1 | Policy and Procedures | Org | Documented physical security policy. |
| PE-2 | Physical Access Authorizations | Org | List of authorized personnel with physical access to the server room/location. |
| PE-3 | Physical Access Control | Org | Physical locks, access badges, or other physical access controls for server location. |
| PE-4 | Access Control for Transmission | Org | Physical protection of network cabling. LAN-only network design limits exposure. |
| PE-5 | Access Control for Output Devices | Org | Physical access to server console controlled. |
| PE-6 | Monitoring Physical Access | Org | Physical access logs, cameras, or similar monitoring at server location. |
| PE-8 | Visitor Access Records | Org | Visitor log for server location. |
| PE-9 | Power Equipment and Cabling | Org | UPS and power protection for the workstation. |
| PE-10 | Emergency Shutoff | Org | Physical emergency power cutoff accessible. |
| PE-11 | Emergency Power | Org | UPS sizing for graceful shutdown. |
| PE-12 | Emergency Lighting | Org | Applicable if server is in a dedicated room. |
| PE-13 | Fire Protection | Org | Fire detection and suppression at server location. |
| PE-14 | Environmental Controls | Org | Temperature and humidity monitoring appropriate for GPU workstation. |
| PE-15 | Water Damage Protection | Org | Server location not in flood-prone area. |
| PE-16 | Delivery and Removal | Org | Process for tracking hardware delivery and removal. |
| PE-17 | Alternate Work Site | Org | Not applicable for fixed server. |
| PE-18 | Location of System Components | Org | Server placement minimizes unauthorized physical access. |

**NixOS Implementation**: None. The only technical contribution is full-disk encryption (MP-4), which provides defense-in-depth against physical theft.

---

### 12. PL -- Planning

**Applicability**: Organizational process only.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| PL-1 | Policy and Procedures | Org | Documented planning policy. |
| PL-2 | System Security and Privacy Plans | Org | System Security Plan (SSP) document referencing this PRD and control mapping. |
| PL-4 | Rules of Behavior | Org | Acceptable use policy for operators and any users with access to agent outputs or inference APIs. |
| PL-8 | Security and Privacy Architectures | Org + Host | Architecture documented in PRD. Flake module structure reflects security architecture (each module maps to a security domain). |
| PL-10 | Baseline Selection | Org | Selection of NIST Moderate baseline documented. Tailoring decisions documented in this module. |
| PL-11 | Baseline Tailoring | Org | Control-by-control tailoring rationale in this document. |

---

### 13. PM -- Program Management

**Applicability**: Organizational process only. These are enterprise-level program controls.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| PM-1 | Information Security Program Plan | Org | Enterprise security program documentation. |
| PM-2 | Information Security Program Leadership Role | Org | Designated security officer or responsible party. |
| PM-3 | Information Security and Privacy Resources | Org | Budget and resources for security operations. |
| PM-4 | Plan of Action and Milestones Process | Org | POA&M tracking process for gaps identified in this document. |
| PM-5 | System Inventory | Org + Host | This server registered in organizational system inventory. `nix flake metadata` provides technical inventory data. |
| PM-6 | Measures of Performance | Org | Security metrics defined (e.g., time to patch, AIDE alert response time). |
| PM-9 | Risk Management Strategy | Org | Enterprise risk management strategy. |
| PM-10 | Authorization Process | Org | Formal authorization to operate (ATO) process. |
| PM-11 | Mission and Business Process Definition | Org | System categorization and mission definition. |
| PM-14 | Testing, Training, and Monitoring | Org | Combined testing/training/monitoring strategy. |

**NixOS Implementation**: None directly. The flake-based configuration supports PM-5 by providing a machine-readable system description.

---

### 14. PS -- Personnel Security

**Applicability**: Organizational process only.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| PS-1 | Policy and Procedures | Org | Documented personnel security policy. |
| PS-2 | Position Risk Designation | Org | Risk designation for operator/admin role. |
| PS-3 | Personnel Screening | Org | Background screening for personnel with admin access. |
| PS-4 | Personnel Termination | Org + Host | Organizational process triggers removal of SSH key from `users.users.admin.openssh.authorizedKeys.keys` and `nixos-rebuild switch`. |
| PS-5 | Personnel Transfer | Org + Host | Same as PS-4 for access modification. |
| PS-6 | Access Agreements | Org | Signed access agreements for admin users. |
| PS-7 | External Personnel Security | Org | Applicable if external contractors have access. |
| PS-8 | Personnel Sanctions | Org | Disciplinary process for security violations. |
| PS-9 | Position Descriptions | Org | Security responsibilities in job descriptions. |

---

### 15. PT -- Personally Identifiable Information Processing and Transparency

**Applicability**: Organizational process (primary). Limited host-level relevance.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| PT-1 | Policy and Procedures | Org | Privacy policy documented if system processes PII. |
| PT-2 | Authority to Process Personally Identifiable Information | Org | Legal authority documented if PII is processed by inference APIs or agents. |
| PT-3 | Personally Identifiable Information Processing Purposes | Org | Purpose specification for any PII in prompts, model inputs, or agent data. |
| PT-4 | Consent | Org | Consent mechanisms if applicable. |
| PT-5 | Privacy Notice | Org | Privacy notice for any users whose data enters the inference pipeline. |
| PT-6 | System of Records Notice | Org | Required if system constitutes a system of records under Privacy Act. |
| PT-7 | Specific Categories of Personally Identifiable Information | Org + Host | If sensitive PII is processed: agent logs must not capture raw PII (logging config in `ai-services` module must redact or hash sensitive fields). |
| PT-8 | Computer Matching Requirements | Org | Applicable only if computer matching agreements exist. |

**NixOS Implementation**: The `ai-services` module should implement log sanitization to avoid capturing PII in audit trails. Agent sandbox isolation (AC-3, AC-4) limits PII exposure surface.

---

### 16. RA -- Risk Assessment

**Applicability**: Organizational process (primary) + host-level vulnerability support.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| RA-1 | Policy and Procedures | Org | Documented risk assessment policy. |
| RA-2 | Security Categorization | Org | FIPS 199 categorization of the system. Expected: Moderate for confidentiality, integrity, availability given local AI workloads. |
| RA-3 | Risk Assessment | Org | Documented risk assessment. This PRD module and the main PRD's risk section provide input. AI-specific risks (prompt injection, model poisoning, agent goal hijack) must be included. |
| RA-5 | Vulnerability Monitoring and Scanning | Host + Org | `nix flake update` pulls latest nixpkgs with security patches. `vulnix` scans the closure for known CVEs: add `pkgs.vulnix` to `environment.systemPackages`. Note: `vulnix --system` produces plaintext output (not JSON); scan results stored as `.txt` files. Organizational process defines scan cadence. Priority: High -- must run before production deployment. |
| RA-7 | Risk Response | Org | Risk response strategy documented. |
| RA-9 | Criticality Analysis | Org | Criticality of AI inference services and agent workloads documented. |

#### NixOS Vulnerability Scanning

```nix
{
  # Vulnerability scanning tool
  environment.systemPackages = [ pkgs.vulnix ];

  # Automated weekly vulnerability scan
  systemd.services.vulnix-scan = {
    description = "NixOS closure vulnerability scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "vulnix-scan" ''
        ${pkgs.vulnix}/bin/vulnix --system > /var/log/vulnix/scan-$(date +%Y%m%d).txt 2>&1
      '';
    };
  };
  systemd.timers.vulnix-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "weekly";
  };
}
```

---

### 17. SA -- System and Services Acquisition

**Applicability**: Organizational process (primary) + host-level supply chain controls.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| SA-1 | Policy and Procedures | Org | Documented acquisition policy. |
| SA-2 | Allocation of Resources | Org | Budget for hardware (GPU workstation), NixOS operations, security tooling. |
| SA-3 | System Development Life Cycle | Org + Host | Flake-based development lifecycle: develop in branch, test with `nixos-rebuild test`, merge, apply with `nixos-rebuild switch`. |
| SA-4 | Acquisition Process | Org | Security requirements in procurement (e.g., NVIDIA driver licensing, model licensing). |
| SA-5 | System Documentation | Org + Host | This PRD module and main PRD. Flake module comments. NixOS `man configuration.nix` for option documentation. |
| SA-8 | Security and Privacy Engineering Principles | Host | Defense in depth implemented through layered modules. Least privilege in systemd sandboxing. Fail-secure defaults (firewall default deny). |
| SA-9 | External System Services | Org + Host | Nixpkgs is the primary external dependency. `nix flake lock` pins all inputs to specific commits. `nix.settings.trusted-substituters` controls binary cache sources. Agent external API access restricted per AC-4. |
| SA-10 | Developer Configuration Management | Host | Flake repo under Git version control. `nix flake lock` ensures reproducible builds from pinned inputs. |
| SA-11 | Developer Testing and Evaluation | Org + Host | `nixos-rebuild dry-build` for syntax/build validation. `nixos-rebuild test` for integration testing in a temporary generation. NixOS test framework (`nixosTest`) for automated integration tests. |
| SA-12 | Supply Chain Protection | Host + Org | `nix.settings.require-sigs = true` (default) ensures all binary substitutions are signed. `nix.settings.trusted-substituters = [ "https://cache.nixos.org" ]` limits binary cache sources. Model provenance tracking is organizational process. |

#### NixOS Supply Chain Controls

```nix
{
  nix.settings = {
    # Only trust the official NixOS binary cache
    trusted-substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    # Require signatures on all substituted paths
    require-sigs = true;
  };

  # Pin flake registry to prevent uncontrolled input resolution
  nix.settings.flake-registry = "";
}
```

---

### 18. SC -- System and Communications Protection

**Applicability**: Host/OS/runtime layer (primary).

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| SC-1 | Policy and Procedures | Org | Documented system and communications protection policy. |
| SC-2 | Separation of User Functionality from System Management Functionality | Host | Admin functions (SSH, `nixos-rebuild`) separated from service functions (Ollama, app APIs). Different user accounts, different systemd units. |
| SC-3 | Security Function Isolation | Host | Audit subsystem runs as root-owned service. Agent sandbox uses separate user/group with systemd isolation directives. Each AI service runs in its own systemd unit with independent sandboxing. |
| SC-4 | Information in Shared Resources | Host | `PrivateTmp = true` on all service units prevents `/tmp` data leakage between services. `ProtectHome = true` prevents services from reading user home directories. Agent runners use dedicated `ReadWritePaths`. |
| SC-5 | Denial-of-Service Protection | Host | `networking.firewall` default deny limits exposure. `services.openssh.settings.MaxStartups = "10:30:60"` rate-limits SSH connections. Systemd resource controls: `MemoryMax`, `CPUQuota`, `TasksMax` on agent and AI service units. |
| SC-7 | Boundary Protection | Host | `networking.firewall.enable = true` with default deny. Only LAN interface exposes services: `networking.firewall.interfaces.<lan>.allowedTCPPorts = [ 22 11434 8000 ]`. No default route to Internet if air-gapped, or strict egress filtering via `networking.firewall.extraCommands` with iptables rules. |
| SC-7(3) | Boundary Protection: Access Points | Host | Single LAN interface as sole access point. All other interfaces firewalled with no allowed ports. |
| SC-7(4) | Boundary Protection: External Telecommunications Services | N/A | Not applicable. LAN-only system. |
| SC-7(5) | Boundary Protection: Deny by Default / Allow by Exception | Host | `networking.firewall.enable = true` implements default deny. Explicit allowlists per interface. |
| SC-8 | Transmission Confidentiality and Integrity | Host + Org | SSH provides encrypted management channel. Ollama and app APIs must use TLS on LAN via Nginx reverse proxy with TLS termination. See SC-8 implementation below. |
| SC-10 | Network Disconnect | Host | `services.openssh.settings.ClientAliveInterval = 300` and `ClientAliveCountMax = 3` terminate idle SSH sessions. |
| SC-12 | Cryptographic Key Establishment and Management | Host + Org | SSH host keys managed via `services.openssh.hostKeys`. User SSH keys managed outside config. TLS certificates for SC-8 managed via `sops-nix` (manual rotation) or internal ACME CA (`step-ca`); see SC-12 implementation above. Certificates must be rotated at least every 90 days. LUKS keys escrowed per organizational process. |
| SC-13 | Cryptographic Protection | Host | LUKS (AES-256) for data at rest. SSH (ChaCha20/AES-GCM) for data in transit. TLS 1.2+ for service APIs. `services.openssh.settings.Ciphers` and `KexAlgorithms` hardened to FIPS-approved or strong algorithms. |
| SC-15 | Collaborative Computing Devices and Applications | N/A | No collaborative computing devices (cameras, microphones) on a headless server. |
| SC-17 | Public Key Infrastructure Certificates | Host + Org | SSH host key fingerprints published to admin. TLS certificates for LAN services from internal CA or self-signed with pinning. |
| SC-18 | Mobile Code | Host | No mobile code execution (no web browser on server). Agent sandbox restricts code execution to allowlisted tools. |
| SC-20 | Secure Name/Address Resolution Service (Authoritative Source) | N/A | Server is not a DNS authority. |
| SC-21 | Secure Name/Address Resolution Service (Recursive or Caching Resolver) | Host | `networking.nameservers` points to trusted LAN DNS. DNSSEC validation if resolver supports it. |
| SC-22 | Architecture and Provisioning for Name/Address Resolution Service | N/A | Not a DNS service. |
| SC-23 | Session Authenticity | Host | SSH provides session authenticity via host key verification. TLS on API services provides session authenticity via certificates. |
| SC-28 | Protection of Information at Rest | Host | LUKS full-disk encryption. Model artifacts, agent data, logs, and secrets encrypted at rest. `boot.initrd.luks.devices` configured per MP-4. |
| SC-39 | Process Isolation | Host | Systemd namespacing: `PrivateNetwork`, `PrivateUsers`, `PrivateTmp`, `ProtectSystem`, `ProtectKernelTunables`, `ProtectControlGroups`, `ProtectKernelModules`, `ProtectKernelLogs`. Separate mount namespaces per service. |

#### NixOS Implementation: Hardened SSH Ciphers

```nix
{
  services.openssh.settings = {
    # Canonical SSH crypto values per prd.md Appendix A.4
    Ciphers = [
      "chacha20-poly1305@openssh.com"
      "aes256-gcm@openssh.com"
      "aes128-gcm@openssh.com"
    ];
    KexAlgorithms = [
      "curve25519-sha256"
      "curve25519-sha256@libssh.org"
    ];
    Macs = [
      "hmac-sha2-512-etm@openssh.com"
      "hmac-sha2-256-etm@openssh.com"
    ];
  };
}
```

#### NixOS Implementation: Agent Resource Limits

```nix
{
  systemd.services.agent-runner = {
    serviceConfig = {
      # SC-5: DoS protection via resource limits
      MemoryMax = "4G";
      CPUQuota = "200%";  # 2 CPU cores max
      TasksMax = 64;

      # SC-4: Information in shared resources
      PrivateTmp = true;
      ProtectHome = true;

      # SC-39: Process isolation
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" ];
      SystemCallArchitectures = "native";
    };
  };
}
```

#### NixOS Implementation: SC-8 TLS Termination for LAN Services

```nix
{
  # SC-8: Nginx reverse proxy with TLS for Ollama and application APIs
  services.nginx = {
    enable = true;
    virtualHosts."ai-internal" = {
      listenAddresses = [ "192.168.1.100" ];
      forceSSL = true;
      sslCertificate = "/var/lib/secrets/tls/server.crt";
      sslCertificateKey = "/var/lib/secrets/tls/server.key";
      locations."/ollama/" = {
        proxyPass = "http://127.0.0.1:11434/";
      };
      locations."/api/" = {
        proxyPass = "http://127.0.0.1:8000/";
      };
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers on;
      '';
    };
  };
}
```

#### NixOS Implementation: SC-12 TLS Certificate Lifecycle

TLS certificates used for SC-8 must be generated, distributed, and rotated on a defined schedule. For LAN-only servers without public DNS, use either manual certificate management with `sops-nix` for encrypted secret storage, or an internal ACME CA (e.g., `step-ca`).

```nix
{
  # Option A: Manual certificate management with sops-nix
  # Certificates generated offline and encrypted in the repo.
  # Rotation: generate new cert, update sops file, nixos-rebuild switch.
  sops.secrets."tls/server.crt" = {
    sopsFile = ./secrets/tls.yaml;
    path = "/var/lib/secrets/tls/server.crt";
    owner = "nginx";
  };
  sops.secrets."tls/server.key" = {
    sopsFile = ./secrets/tls.yaml;
    path = "/var/lib/secrets/tls/server.key";
    owner = "nginx";
  };

  # Option B: Internal ACME CA (if step-ca is available on LAN)
  # security.acme = {
  #   acceptTerms = true;
  #   defaults.server = "https://ca.internal:8443/acme/acme/directory";
  #   certs."ai-internal" = {
  #     domain = "ai-internal.lan";
  #     group = "nginx";
  #   };
  # };
}
```

Certificate rotation schedule: regenerate certificates at least every 90 days, or immediately upon suspected compromise. Track certificate expiry dates in the organizational POA&M.

---

### 19. SI -- System and Information Integrity

**Applicability**: Host/OS/runtime layer (primary) + organizational process.

| Control ID | Title | Layer | NixOS Implementation Requirement |
|---|---|---|---|
| SI-1 | Policy and Procedures | Org | Documented system integrity policy. |
| SI-2 | Flaw Remediation | Host + Org | `nix flake update` pulls security patches from nixpkgs. `nixos-rebuild switch` applies atomically. `vulnix --system` identifies known CVEs in the closure. Organizational process defines patching SLA. |
| SI-2(2) | Flaw Remediation: Automated Flaw Remediation Status | Host | Automated `vulnix` scan results stored in `/var/log/vulnix/`. |
| SI-3 | Malicious Code Protection | Host | NixOS store is read-only and content-addressed (paths derived from hashes). `nix.settings.require-sigs = true` validates binary cache signatures. Agent sandbox prevents arbitrary code execution outside allowlisted tools. No traditional AV needed given immutable store and sandboxed execution model; document this tailoring decision. |
| SI-4 | System Monitoring | Host + Org | `security.auditd.enable = true` for kernel-level monitoring. AIDE for filesystem integrity. `journalctl` for service monitoring. Agent-specific monitoring for anomalous tool invocations, excessive API calls, or unexpected network activity. |
| SI-4(4) | System Monitoring: Inbound and Outbound Communications Traffic | Host | Firewall logging via `networking.firewall.logRefusedConnections = true`. `networking.firewall.logRefusedPackets = true`. |
| SI-4(5) | System Monitoring: System-Generated Alerts | Host | `systemd.services.aide-check` with `OnFailure=notify-admin@.service`. Custom monitoring for agent anomalies. |
| SI-5 | Security Alerts, Advisories, and Directives | Org | Subscribe to NixOS security advisories (nixos-security-announce mailing list). Monitor nixpkgs security tracker. |
| SI-6 | Security and Privacy Function Verification | Host | AIDE verifies integrity of security-relevant files. `nixos-rebuild dry-build` verifies config consistency. Boot-time verification via systemd-boot. |
| SI-7 | Software, Firmware, and Information Integrity | Host | Nix store content addressing provides inherent integrity verification. AIDE monitors non-Nix-managed paths. `nix-store --verify --check-contents` validates store integrity. |
| SI-7(1) | Software, Firmware, and Information Integrity: Integrity Checks | Host | AIDE configured for hourly checks. `nix-store --verify` for on-demand store verification. |
| SI-10 | Information Input Validation | Host + App | Agent sandbox enforces input validation at the OS layer (restricted file paths, network access). Application-layer input validation for inference APIs is the responsibility of the `ai-services` module code, not the OS config. |
| SI-11 | Error Handling | Host | Systemd service units configured with `StandardError=journal` to capture errors without exposing sensitive data. Agent services must not leak model prompts, API keys, or PII in error messages. |
| SI-12 | Information Management and Retention | Org + Host | Journal retention configured per AU-11. Model artifacts and agent data retention per organizational policy. |
| SI-16 | Memory Protection | Host | Kernel hardening: `boot.kernel.sysctl."kernel.randomize_va_space" = 2` (ASLR), `kernel.kptr_restrict = 2` (hide kernel pointers), `kernel.dmesg_restrict = 1` (restrict dmesg). NixOS enables stack protection and other hardening by default. Secure Boot should be enabled as an out-of-band requirement to protect the kernel image at boot time. |

#### NixOS Implementation: Integrity Monitoring

```nix
{
  # SI-4(4): Firewall logging
  networking.firewall.logRefusedConnections = true;

  # SI-7(1): Nix store integrity verification
  systemd.services.nix-store-verify = {
    description = "Verify Nix store integrity";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix}/bin/nix-store --verify --check-contents";
    };
  };
  systemd.timers.nix-store-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
  };

  # SI-16: Memory protection
  boot.kernel.sysctl = {
    "kernel.randomize_va_space" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.yama.ptrace_scope" = 2;
    "net.core.bpf_jit_harden" = 2;
  };
}
```

---

### 20. SR -- Supply Chain Risk Management

**Applicability**: Host/OS layer (Nix-specific) + organizational process.

| Control ID | Title | Layer | Requirement |
|---|---|---|---|
| SR-1 | Policy and Procedures | Org | Documented supply chain risk management policy covering nixpkgs, binary caches, AI models, and NVIDIA drivers. |
| SR-2 | Supply Chain Risk Management Plan | Org | Plan addressing: nixpkgs input pinning strategy, binary cache trust model, model provenance, hardware supply chain. |
| SR-3 | Supply Chain Controls and Processes | Host + Org | `nix flake lock` pins all inputs. `nix.settings.require-sigs = true`. `nix.settings.trusted-substituters` allowlist. Model files verified by hash before deployment. |
| SR-4 | Provenance | Host + Org | `nix flake metadata` shows input provenance. `nix-store --query --deriver` traces any store path to its build recipe. Model provenance documented per organizational process (source, hash, version, license). |
| SR-5 | Acquisition Strategies, Tools, and Methods | Org | Acquisition through nixpkgs (open source, community-reviewed). NVIDIA drivers from official channels. Models from documented sources. |
| SR-6 | Supplier Assessments and Reviews | Org | Periodic review of nixpkgs security practices, binary cache operator (NixOS Foundation), model provider security posture. |
| SR-8 | Notification Agreements | Org | Monitor nixpkgs security advisories and NVIDIA security bulletins. |
| SR-9 | Tamper Resistance and Detection | Host | Nix store content addressing detects tampering. AIDE monitors non-store paths. LUKS prevents offline tampering. |
| SR-10 | Inspection of Systems or Components | Org + Host | `nix-store --query --tree /run/current-system` inspects full dependency tree. `nix path-info --closure-size /run/current-system` for closure analysis. |
| SR-11 | Component Authenticity | Host | `nix.settings.require-sigs = true` verifies binary cache authenticity. Nix content-addressing (store path = hash of all inputs) provides inherent authenticity for source-built packages. |
| SR-12 | Component Disposal | Org | `nix-collect-garbage -d` removes unused store paths. Hardware disposal per organizational process and NIST 800-88. |

---

## Priority Matrix

### Critical -- Implement Before Production Use

| Control Family | Key Controls | Flake Module | Rationale |
|---|---|---|---|
| AC | AC-2, AC-3, AC-6, AC-7, AC-17 | `stig-baseline` | Foundational access control. System is insecure without these. |
| SC | SC-7, SC-8, SC-13, SC-28, SC-39 | `lan-only-network`, `stig-baseline`, `agent-sandbox` | Boundary protection, transmission encryption, and data-at-rest encryption are the primary defense layers for a LAN server. SC-8 is critical because unencrypted LAN traffic exposes prompts and model responses to any network observer. |
| AU | AU-2, AU-3, AU-8, AU-9, AU-12 | `audit-and-aide` | Audit trail required for all other controls to be verifiable. |
| SI | SI-2, SI-3, SI-4, SI-7 | `stig-baseline`, `audit-and-aide` | Integrity of the system is a prerequisite for trusting any other control. |
| IA | IA-2, IA-5 | `stig-baseline` | Authentication is a gateway control; failure here defeats AC entirely. |
| CM | CM-2, CM-6, CM-7 | All modules | NixOS declarative config is the mechanism for all other controls. |

### High -- Implement in First Iteration

| Control Family | Key Controls | Flake Module | Rationale |
|---|---|---|---|
| MP | MP-2, MP-4, MP-7 | `stig-baseline` | Full-disk encryption and media access control. |
| IA | IA-2(1), IA-3, IA-11 | `stig-baseline` | MFA and re-authentication. |
| SC | SC-2, SC-4, SC-5, SC-10 | `agent-sandbox`, `ai-services` | Defense in depth for service isolation and session management. |
| AU | AU-4, AU-5, AU-6, AU-11 | `audit-and-aide` | Log management and retention. |
| CM | CM-3, CM-5, CM-8, CM-10, CM-11 | All modules | Change control and least functionality. |
| SR | SR-3, SR-4, SR-9, SR-11 | Flake config | Supply chain integrity is especially important for AI model provenance. |
| SI | SI-4(4), SI-4(5), SI-6, SI-16 | `stig-baseline`, `audit-and-aide` | Monitoring and alerting. |
| RA | RA-5 | `stig-baseline` (vulnix) | Vulnerability scanning must happen before production to avoid deploying known CVEs. |

### Medium -- Implement in Second Iteration

| Control Family | Key Controls | Flake Module | Rationale |
|---|---|---|---|
| IR | IR-4, IR-5 | `audit-and-aide` (tooling support) | Incident handling tooling and monitoring. |
| CP | CP-2, CP-9, CP-10 | Flake config | Contingency planning leveraging NixOS rollback. |
| RA | RA-3 | `stig-baseline` | Risk assessment documentation. |
| SA | SA-9, SA-10, SA-11, SA-12 | Flake config | Development lifecycle and supply chain depth. |
| MA | MA-2, MA-4, MA-6 | `stig-baseline` | Maintenance controls. |
| AC | AC-8, AC-10, AC-11, AC-12 | `stig-baseline` | Session controls and banners. |
| PT | PT-7 | `ai-services` | Log sanitization for PII. |

### Low -- Organizational Process / Documentation

| Control Family | Key Controls | Dependency | Rationale |
|---|---|---|---|
| AT | AT-1 through AT-4 | Org only | Training is purely organizational. |
| PE | PE-1 through PE-18 | Org only | Physical security is outside host config. |
| PL | PL-1 through PL-11 | Org only | Planning documentation. |
| PM | PM-1 through PM-14 | Org only | Program management. |
| PS | PS-1 through PS-9 | Org only | Personnel security. |
| CA | CA-1, CA-2, CA-5, CA-8 | Org only | Assessment and authorization. |
| PT | PT-1 through PT-6, PT-8 | Org only | Privacy processing (unless PII is in scope). |

---

## Implementation Requirements by Flake Module

### `stig-baseline` Module

This module must implement the following NixOS configuration:

```nix
{ config, lib, pkgs, ... }:
{
  # --- AC-2: Account Management ---
  users.mutableUsers = false;  # All accounts declared in config only
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ /* declared keys */ ];
  };

  # --- AC-6: Least Privilege ---
  security.sudo.wheelNeedsPassword = true;
  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=5
    Defaults logfile="/var/log/sudo.log"
  '';
  nix.settings.allowed-users = [ "admin" ];

  # --- AC-7: Unsuccessful Logon Attempts ---
  services.fail2ban = {
    enable = true;
    jails.sshd = {
      settings = {
        enabled = true;
        maxretry = 5;
        bantime = "1h";
        findtime = "10m";
      };
    };
  };

  # --- AC-8: System Use Notification ---
  services.openssh.banner = "/etc/issue.net";
  environment.etc."issue.net".text = ''
    Authorized use only. All activity is monitored and logged.
    Unauthorized access is prohibited and subject to prosecution.
  '';
  environment.etc."issue".text = ''
    Authorized use only. All activity is monitored and logged.
  '';

  # --- IA-2(1): Multi-Factor Authentication (TOTP via google-authenticator) ---
  security.pam.services.sshd = {
    googleAuthenticator.enable = true;
  };
  environment.systemPackages = [ pkgs.google-authenticator ];

  # --- IA-2, AC-17: Identification and Authentication / Remote Access ---
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = true;  # Required for TOTP MFA (IA-2(1))
      AuthenticationMethods = "publickey,keyboard-interactive";  # MFA: key + TOTP
      PermitRootLogin = "no";
      X11Forwarding = false;
      AllowUsers = [ "admin" ];
      MaxSessions = 3;
      MaxStartups = "10:30:60";
      ClientAliveInterval = 300;
      ClientAliveCountMax = 3;
      # Canonical SSH crypto values per prd.md Appendix A.4
      Ciphers = [
        "chacha20-poly1305@openssh.com"
        "aes256-gcm@openssh.com"
        "aes128-gcm@openssh.com"
      ];
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];
      Macs = [
        "hmac-sha2-512-etm@openssh.com"
        "hmac-sha2-256-etm@openssh.com"
      ];
    };
  };

  # --- SI-16: Memory Protection ---
  boot.kernel.sysctl = {
    "kernel.randomize_va_space" = 2;
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "kernel.perf_event_paranoid" = 3;
    "kernel.yama.ptrace_scope" = 2;
    "net.core.bpf_jit_harden" = 2;
    "net.ipv4.ip_forward" = false;           # CM-7
    "net.ipv4.conf.all.accept_redirects" = false;
    "net.ipv4.conf.default.accept_redirects" = false;
    "net.ipv6.conf.all.accept_redirects" = false;
    "net.ipv4.conf.all.send_redirects" = false;
    "net.ipv4.conf.all.accept_source_route" = false;
    "net.ipv6.conf.all.accept_source_route" = false;
  };

  # --- CM-7: Least Functionality ---
  services.xserver.enable = false;
  documentation.nixos.enable = false;  # Reduce attack surface

  # --- MP-4, SC-28: Full-Disk Encryption (declared, hardware-specific UUID required) ---
  # boot.initrd.luks.devices."cryptroot" = {
  #   device = "/dev/disk/by-uuid/<UUID>";
  #   preLVM = true;
  # };

  # --- SR-11, SA-12: Supply Chain ---
  nix.settings = {
    require-sigs = true;
    trusted-substituters = [ "https://cache.nixos.org" ];
    flake-registry = "";
  };
}
```

### `lan-only-network` Module

```nix
{ config, lib, ... }:
let
  lanInterface = "enp3s0";  # Parameterize per hardware
in
{
  # --- SC-7: Boundary Protection (default deny, allow by exception) ---
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];   # Global default: nothing
    allowedUDPPorts = [ ];
    interfaces.${lanInterface}.allowedTCPPorts = [ 22 11434 8000 ];
    logRefusedConnections = true;   # SI-4(4)
    logRefusedPackets = true;
  };

  # --- AC-4: Information Flow Enforcement (block non-LAN traffic) ---
  # NOTE: These iptables rules are illustrative. The implementation flake
  # uses nftables exclusively per prd.md Appendix A.2. Convert these rules
  # to nftables syntax in the implementation.
  networking.firewall.extraCommands = ''
    # Allow only RFC1918 LAN sources on the LAN interface
    iptables -A INPUT -i ${lanInterface} -s 192.168.0.0/16 -j ACCEPT
    iptables -A INPUT -i ${lanInterface} -s 10.0.0.0/8 -j ACCEPT
    iptables -A INPUT -i ${lanInterface} -s 172.16.0.0/12 -j ACCEPT
    iptables -A INPUT -i ${lanInterface} -j DROP
  '';

  # --- SC-21: DNS ---
  networking.nameservers = [ "192.168.1.1" ];  # LAN DNS; parameterize

  # Disable wireless if hardware present (AC-18)
  networking.wireless.enable = false;
}
```

### `audit-and-aide` Module

```nix
{ config, lib, pkgs, ... }:
{
  # --- AU-2, AU-3, AU-12: Audit Event Logging ---
  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    # Login/logout events
    "-w /var/log/lastlog -p wa -k logins"
    "-w /var/log/faillog -p wa -k logins"

    # Privilege escalation
    "-w /etc/sudoers -p wa -k privilege-escalation"
    "-w /etc/sudoers.d/ -p wa -k privilege-escalation"
    "-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=4294967295 -k privileged-command"

    # File access to sensitive paths
    "-w /etc/shadow -p rwxa -k shadow-access"
    "-w /etc/passwd -p wa -k passwd-changes"
    "-w /etc/group -p wa -k group-changes"

    # Agent and AI service data directories
    "-w /var/lib/agent-runner/ -p rwxa -k agent-data"
    "-w /var/lib/ollama/ -p wa -k model-data"

    # System configuration changes
    "-w /etc/nixos/ -p wa -k nix-config"

    # Audit log tampering detection (AU-9)
    "-w /var/log/audit/ -p wa -k audit-log-tamper"

    # Module loading (SI-3, SI-7)
    "-w /sbin/insmod -p x -k module-load"
    "-w /sbin/modprobe -p x -k module-load"
    "-a always,exit -F arch=b64 -S init_module -S finit_module -k module-load"
  ];

  # --- AU-4, AU-11: Log Storage and Retention ---
  services.journald.extraConfig = ''
    SystemMaxUse=2G
    SystemKeepFree=1G
    MaxRetentionSec=7776000
    ForwardToSyslog=yes
  '';

  # --- AU-8: Time Stamps ---
  services.chrony = {
    enable = true;
    servers = [ "pool.ntp.org" ];  # Replace with LAN NTP if available
  };

  # --- SI-7(1), CA-7: AIDE Integrity Monitoring ---
  environment.systemPackages = [ pkgs.aide pkgs.vulnix ];

  systemd.services.aide-init = {
    description = "Initialize AIDE database";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --init";
      RemainAfterExit = true;
    };
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!/var/lib/aide/aide.db";
  };

  systemd.services.aide-check = {
    description = "AIDE integrity check";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --check";
    };
    onFailure = [ "notify-admin@aide-check.service" ];
  };

  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
  };

  # --- AU-5, SI-4(5): Alert on audit/monitoring failure ---
  systemd.services."notify-admin@" = {
    description = "Send admin notification for %i failure";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "notify-admin" ''
        MONITOR_UNIT="%i"
        echo "[ALERT] Service $MONITOR_UNIT failed at $(date)" >> /var/log/admin-alerts.log
        # Extend with email, webhook, or other notification mechanism
      '';
    };
  };

  # --- RA-5: Vulnerability Scanning ---
  systemd.services.vulnix-scan = {
    description = "NixOS closure vulnerability scan";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "vulnix-scan" ''
        mkdir -p /var/log/vulnix
        ${pkgs.vulnix}/bin/vulnix --system > /var/log/vulnix/scan-$(date +%Y%m%d).txt 2>&1
      '';
    };
  };
  systemd.timers.vulnix-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  # --- SI-7: Nix Store Integrity Verification ---
  systemd.services.nix-store-verify = {
    description = "Verify Nix store integrity";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.nix}/bin/nix-store --verify --check-contents";
    };
  };
  systemd.timers.nix-store-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
```

### `agent-sandbox` Module

```nix
{ config, lib, pkgs, ... }:
{
  # --- AC-2: Service Account ---
  users.users.agent = {
    isSystemUser = true;
    group = "agent";
    home = "/var/lib/agent-runner";
    shell = "${pkgs.shadow}/bin/nologin";
  };
  users.groups.agent = {};

  # --- AC-3, AC-6, SC-39: Sandboxed Agent Execution ---
  systemd.services.agent-runner = {
    description = "Sandboxed AI agent runner";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      User = "agent";
      Group = "agent";

      # AC-6: Least privilege
      NoNewPrivileges = true;
      AmbientCapabilities = "";
      CapabilityBoundingSet = "";

      # SC-4: Shared resource isolation
      PrivateTmp = true;
      ProtectHome = true;

      # SC-39: Process isolation
      ProtectSystem = "strict";
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectHostname = true;
      ProtectClock = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictNamespaces = true;
      LockPersonality = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      MemoryDenyWriteExecute = true;

      # SC-39: Syscall filtering
      SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" "~@mount" "~@clock" "~@debug" "~@reboot" "~@swap" "~@raw-io" "~@module" ];
      SystemCallArchitectures = "native";

      # AC-4, SC-7: Network restriction
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      IPAddressAllow = [ "127.0.0.0/8" "192.168.0.0/16" "10.0.0.0/8" ];
      IPAddressDeny = "any";

      # SC-4: Filesystem isolation
      ReadWritePaths = [ "/var/lib/agent-runner" ];
      ReadOnlyPaths = [ "/etc" "/run" ];
      InaccessiblePaths = [ "/var/log/audit" "/root" "/home" ];

      # SC-5: Resource limits
      MemoryMax = "4G";
      CPUQuota = "200%";
      TasksMax = 64;
      LimitNOFILE = 1024;

      # AU-2: Logging
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "agent-runner";

      ExecStart = "/run/current-system/sw/bin/agent-runner";
      Restart = "on-failure";
      RestartSec = 10;
      TimeoutStopSec = 30;
    };
  };
}
```

### `ai-services` Module

```nix
{ config, lib, pkgs, ... }:
{
  # --- AC-2: Service Accounts ---
  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    home = "/var/lib/ollama";
    shell = "${pkgs.shadow}/bin/nologin";
  };
  users.groups.ollama = {};

  users.users.ai-api = {
    isSystemUser = true;
    group = "ai-api";
    home = "/var/lib/ai-api";
    shell = "${pkgs.shadow}/bin/nologin";
  };
  users.groups.ai-api = {};

  # --- Ollama Service (port 11434) ---
  systemd.services.ollama = {
    description = "Ollama local inference server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "ollama";
      Group = "ollama";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";  # Canonical value per prd.md Appendix A.3; GPU access via ReadWritePaths/DeviceAllow
      ReadWritePaths = [ "/var/lib/ollama" ];
      MemoryMax = "32G";  # Adjust for GPU VRAM + system RAM needs
      TasksMax = 128;
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "ollama";
      # Note: GPU access requires device access; ProtectSystem = "strict"
      # may need relaxation for /dev/nvidia* and /dev/dri/*
      SupplementaryGroups = [ "video" "render" ];
    };
    environment = {
      OLLAMA_HOST = "127.0.0.1:11434";  # Bound to localhost; LAN access via Nginx TLS proxy (see prd.md Appendix A.1)
      OLLAMA_MODELS = "/var/lib/ollama/models";
    };
  };

  # --- Application API Service (port 8000) ---
  systemd.services.ai-api = {
    description = "AI application API server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "ollama.service" ];
    serviceConfig = {
      User = "ai-api";
      Group = "ai-api";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/var/lib/ai-api" ];
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      MemoryMax = "2G";
      TasksMax = 64;
      StandardOutput = "journal";
      StandardError = "journal";
      SyslogIdentifier = "ai-api";
    };
  };
}
```

### `gpu-node` Module

```nix
{ config, lib, pkgs, ... }:
{
  # --- CM-6, CM-7: GPU Configuration (least functionality) ---
  # Enable GPU graphics support for headless compute (no desktop/display server)
  hardware.graphics.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;  # Proprietary driver required for CUDA inference
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # Still needed for driver selection even on headless systems
  services.xserver.videoDrivers = [ "nvidia" ];

  # GPU users group for device access
  users.groups.render = {};
  users.groups.video = {};

  # CUDA and AI runtime packages (CM-8: inventory)
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    # Add only required packages; review quarterly per CM-7(1)
  ];

  # Note: NVIDIA driver is a supply chain risk (SR-1, SR-2).
  # Driver version must be tracked and updated per SI-2 patching cadence.
  # NVIDIA security bulletins monitored per SI-5.
  # Note: services.xserver.enable is NOT set to true; the xserver option
  # is used only for driver selection. This is a headless GPU compute server.
}
```

---

## Evidence Generation Requirements

Each control area requires specific artifacts for audit. The following table maps controls to the evidence that the NixOS configuration must be capable of producing.

| Control Area | Evidence Artifact | Generation Method | Storage Location |
|---|---|---|---|
| AC-2 (Account Management) | User account listing | `nix eval .#nixosConfigurations.server.config.users.users --json` | Flake repo + runtime `/etc/passwd` |
| AC-3, AC-6 (Access/Privilege) | Systemd unit configs showing sandboxing | `systemctl show agent-runner.service` | Runtime, exportable via `systemctl show --output=json` |
| AC-4, SC-7 (Network/Boundary) | Firewall rules dump | `iptables -L -n -v` | On-demand export to `/var/log/evidence/` |
| AU-2, AU-12 (Audit Logging) | Audit log samples | `ausearch -ts today` or `journalctl --since today` | `/var/log/audit/audit.log`, systemd journal |
| AU-8 (Time Stamps) | NTP sync status | `chronyc tracking` | On-demand |
| CA-7, SI-7 (Integrity) | AIDE integrity report | `aide --check` output | `/var/log/aide/` (per timer) |
| CM-2 (Baseline) | Full system config | `nixos-rebuild dry-build 2>&1`, `nix flake show`, `nix flake metadata` | Flake repo, on-demand |
| CM-8 (Inventory) | Package closure | `nix-store --query --requisites /run/current-system` | On-demand export |
| IA-2 (Authentication) | SSH config dump | `sshd -T` (test mode) | On-demand |
| MP-4, SC-28 (Encryption) | LUKS status | `cryptsetup luksDump /dev/<device>` | On-demand |
| RA-5 (Vulnerabilities) | CVE scan results | `vulnix --system` | `/var/log/vulnix/` (per timer) |
| SC-13 (Crypto) | SSH cipher negotiation | `ssh -vv` connection log, `sshd -T \| grep ciphers` | On-demand |
| SI-4 (Monitoring) | Firewall deny log samples | `journalctl -k \| grep DENIED` | systemd journal |
| SI-7 (Store Integrity) | Nix store verification | `nix-store --verify --check-contents` | On-demand / daily timer |
| SR-4 (Provenance) | Flake input metadata | `nix flake metadata`, `nix flake lock --output-lock-file /dev/stdout` | Flake repo `flake.lock` |

### Automated Evidence Collection Service

```nix
{
  systemd.services.compliance-evidence-snapshot = {
    description = "Generate compliance evidence snapshot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "compliance-evidence" ''
        OUTDIR="/var/lib/compliance-evidence/$(date +%Y%m%d)"
        mkdir -p "$OUTDIR"

        # AC: Account inventory
        getent passwd > "$OUTDIR/passwd.txt"
        getent group > "$OUTDIR/group.txt"

        # AC/SC: Firewall rules
        iptables -L -n -v > "$OUTDIR/iptables.txt" 2>&1

        # AU: Audit rules
        auditctl -l > "$OUTDIR/audit-rules.txt" 2>&1

        # CM: Package inventory
        nix-store --query --requisites /run/current-system > "$OUTDIR/package-inventory.txt"

        # CM: Generation list
        nixos-rebuild list-generations > "$OUTDIR/generations.txt" 2>&1

        # IA: SSH effective config
        sshd -T > "$OUTDIR/sshd-config.txt" 2>&1

        # SC: LUKS status
        for dev in /dev/mapper/crypt*; do
          [ -e "$dev" ] && cryptsetup status "$dev" >> "$OUTDIR/luks-status.txt" 2>&1
        done

        # SI: Nix store verification (quick check)
        nix-store --verify 2>&1 | tail -5 > "$OUTDIR/store-verify-summary.txt"

        # SR: Flake metadata
        nix flake metadata --json > "$OUTDIR/flake-metadata.json" 2>&1 || true

        # Manifest
        sha256sum "$OUTDIR"/* > "$OUTDIR/manifest.sha256"

        echo "Evidence snapshot completed: $OUTDIR"
      '';
    };
  };

  systemd.timers.compliance-evidence-snapshot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  # Also trigger evidence collection on every nixos-rebuild switch
  # by adding a system activation script:
  system.activationScripts.compliance-evidence = ''
    /run/current-system/sw/bin/systemctl start compliance-evidence-snapshot.service --no-block || true
  '';
}
```

---

## Gaps Requiring Organizational Process

The following controls cannot be satisfied by NixOS host configuration alone. Each requires documented organizational policy, procedures, or external tooling.

### Fully Organizational (No Host Component)

| Family | Controls | Required Organizational Artifact |
|---|---|---|
| AT | AT-1 through AT-4 | Security awareness training program, training records, role-based training for NixOS admin. |
| PE | PE-1 through PE-18 | Physical security policy, access logs, environmental controls for server location. |
| PL | PL-1, PL-2, PL-4, PL-10, PL-11 | System Security Plan (SSP), rules of behavior, baseline selection rationale. |
| PM | PM-1 through PM-14 | Information security program plan, POA&M process, risk management strategy, ATO process. |
| PS | PS-1 through PS-9 | Personnel security policy, screening procedures, access agreements, termination procedures. |

### Partially Organizational (Host Supports but Cannot Fully Satisfy)

| Family | Controls | Host Contribution | Organizational Gap |
|---|---|---|---|
| AC | AC-2, AC-5, AC-19, AC-20 | Account declaration, SSH restrictions | Account review cadence, separation of duties matrix, external system use policy. |
| AU | AU-5, AU-6, AU-11 | Alerting on failure, journal retention | Escalation procedures, review cadence, long-term log archival. |
| CA | CA-1, CA-2, CA-5, CA-8 | Config diffing, AIDE monitoring | Assessment policy, POA&M tracking, penetration testing program. |
| CM | CM-1, CM-3, CM-9 | Git-tracked config, dry-build testing | CM policy document, change approval process, CM plan. |
| CP | CP-1, CP-2, CP-4, CP-6 | NixOS rollback, flake Git backup | Contingency plan document, test schedule, off-site storage arrangement. |
| IA | IA-4, IA-5 | Config-declared identifiers, encrypted secrets | Identifier lifecycle management, authenticator distribution process. |
| IR | IR-1 through IR-8 | Forensic snapshot tooling, agent halt capability | Incident response plan, training, reporting procedures, contacts. |
| MA | MA-1, MA-5, MA-6 | SSH-only remote access, atomic updates | Maintenance policy, personnel authorization, patching SLA. |
| MP | MP-3, MP-5, MP-6 | LUKS encryption, garbage collection | Media marking, transport procedures, physical sanitization. |
| PT | PT-1 through PT-6 | Log sanitization in ai-services | Privacy policy, consent mechanisms, PII handling procedures. |
| RA | RA-1, RA-2, RA-3, RA-7, RA-9 | vulnix scanning | Risk assessment document, FIPS 199 categorization, risk response strategy. |
| SA | SA-1, SA-2, SA-4 | Flake lifecycle, supply chain pinning | Acquisition policy, budget, procurement requirements. |
| SI | SI-5 | Automated patching | Subscription to security advisory feeds, response procedures. |
| SR | SR-1, SR-2, SR-5, SR-6, SR-8, SR-12 | Content-addressing, signed substitutions | Supply chain policy, supplier assessments, model provenance documentation, hardware disposal. |

---

## Appendix A: Control-to-Module Traceability Matrix

| Control ID | `stig-baseline` | `gpu-node` | `lan-only-network` | `audit-and-aide` | `agent-sandbox` | `ai-services` | Org Process |
|---|---|---|---|---|---|---|---|
| AC-2 | X | | | | X | X | X |
| AC-3 | X | | | | X | X | |
| AC-4 | | | X | | X | | |
| AC-6 | X | | | | X | X | |
| AC-7 | X | | | | | | |
| AC-8 | X | | | | | | |
| AC-17 | X | | | | | | X |
| AU-2 | | | | X | | | |
| AU-3 | | | | X | | X | |
| AU-8 | | | | X | | | |
| AU-9 | | | | X | | | |
| AU-12 | | | | X | | | |
| CA-7 | | | | X | | | X |
| CM-2 | X | X | X | X | X | X | X |
| CM-6 | X | X | X | X | X | X | |
| CM-7 | X | X | | | | | |
| CM-8 | X | X | X | X | X | X | |
| CM-11 | X | | | | | | |
| IA-2 | X | | | | | | |
| IA-5 | X | | | | | | X |
| MP-4 | X | | | | | | |
| SC-7 | | | X | | | | |
| SC-13 | X | | | | | | |
| SC-28 | X | | | | | | |
| SC-39 | | | | | X | X | |
| SI-2 | X | | | X | | | X |
| SI-4 | | | X | X | | | |
| SI-7 | | | | X | | | |
| SI-16 | X | | | | | | |
| SR-3 | X | | | | | | X |
| SR-11 | X | | | | | | |

---

## Appendix B: NixOS-Specific Compliance Advantages

NixOS provides several properties that are uniquely beneficial for NIST 800-53 compliance:

1. **Declarative state (CM-2, CM-6)**: The entire system configuration is defined in code. There is no configuration drift from imperative changes because the system state is derived from the flake on each rebuild.

2. **Immutable store (SI-3, SI-7, SR-9, SR-11)**: The Nix store (`/nix/store`) is read-only and content-addressed. Every path is derived from the cryptographic hash of its inputs. This provides built-in tamper detection and authenticity verification that traditional Linux distributions require additional tooling to achieve.

3. **Atomic upgrades and rollback (CP-10, SI-2, CM-3)**: System updates are atomic. A failed update does not leave the system in a partially-updated state. Previous generations are retained and selectable at boot, providing instant rollback capability.

4. **Reproducible builds (CM-2, SA-10)**: Given the same flake inputs (pinned via `flake.lock`), the system can be rebuilt identically on different hardware. This supports disaster recovery and evidence consistency.

5. **No user-installed software (CM-11, CM-7)**: The Nix package manager is restricted to authorized users. System packages are declared in configuration. There is no `apt install` equivalent that non-admin users can run to introduce unauthorized software.

6. **Garbage collection (MP-6, SR-12)**: `nix-collect-garbage` deterministically removes all store paths not referenced by any system generation or user profile, supporting secure decommissioning of old software versions.

These properties mean that several NIST controls that are traditionally difficult to implement on mutable Linux distributions (particularly CM-2, CM-6, CM-7, CM-11, SI-3, SI-7) are structurally enforced by the operating system design rather than by add-on tooling.
