# Infrastructure Hardening — Stack-Ranked TODOs

This slice owns the NixOS host-level and network hardening modules that anchor the compliance story: `stig-baseline`, `lan-only-network`, `audit-and-aide`, anti-malware (ClamAV + clamonacc), centralized log forwarding, FIM on NixOS-correct paths, TLS/FIPS crypto posture, and the CVSS-driven remediation cadence that PCI/STIG/NIST all demand. Every Nix snippet carried over from the PRDs has been flagged as potentially broken by MASTER-REVIEW, so the first wave of work is a validation-and-rewrite pass against NixOS 24.11+ (nftables default, no `/usr/bin`, no phantom options, sshd 9.x) before any hardening goes live. The list is stack-ranked by blast radius: items that break boot/eval or punch holes in the LAN-only posture lead, then the baseline modules, then defense-in-depth and advanced boot/firmware hardening. All TODOs assume `ARCH-02` (canonical config appendix) lands first so cross-framework value conflicts (log retention, password length, cipher lists) are already resolved before infra code is written.

---

### INFRA-01: Rewrite `lan-only-network` firewall to nftables-only with correct egress semantics
- **Priority:** P0
- **Effort:** M
- **Depends on:** ARCH-02
- **Source:** MASTER-REVIEW.md Systemic #2 (iptables DROP) + NIST Must-fix #1, prd-stig-disa.md §8.4, wiki/nixos-platform/nixos-gotchas.md §3, wiki/compliance-frameworks/canonical-config-values.md (Firewall)

The PRD's firewall block uses `networking.firewall.extraCommands` with `iptables` syntax that silently fails on NixOS 24.11 (nftables default) and contains mutually exclusive DROP clauses that would deny all traffic if they did apply. Deliverable: a `lan-only-network` module that uses `networking.nftables.enable = true` with a single `ruleset`, default-deny inbound, per-interface allowlist (22/443/8443 on the LAN NIC only), per-UID egress via `meta skuid`, loopback + RFC1918 + NTP/DNS egress allowed, and `networking.enableIPv6 = false` unless an IPv6 ruleset is written. Must evaluate under `nix flake check`.

### INFRA-02: Bind all listeners (Ollama, app API, SSH) to loopback / LAN interface explicitly
- **Priority:** P0
- **Effort:** S
- **Depends on:** ARCH-02
- **Source:** MASTER-REVIEW.md STIG Must-fix #4, wiki/compliance-frameworks/canonical-config-values.md (Service Binding), prd-stig-disa.md §4, prd-pci-dss.md Req 1

`OLLAMA_HOST = "0.0.0.0:11434"` in the STIG PRD contradicts the entire LAN-only stance. Deliverable: set `OLLAMA_HOST=127.0.0.1:11434` + `OLLAMA_ORIGINS=http://127.0.0.1:*` via `systemd.services.ollama.environment`, force `services.openssh.listenAddresses` to the LAN IP (never `0.0.0.0`), put the app API on `127.0.0.1:8000` behind Nginx, and add a `nix flake check` assertion that fails if any public-facing service is not bound via the Nginx TLS front.

### INFRA-03: Remove every phantom / deprecated NixOS option flagged in MASTER-REVIEW
- **Priority:** P0
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md Systemic #2, wiki/nixos-platform/nixos-gotchas.md §4 and §8, prd-nist-800-53.md §18, prd-stig-disa.md §4.1 and §11.2

Strip `security.protectKernelImage`, `Protocol 2`, `ChallengeResponseAuthentication`, `pkgs.pam`, and any `environment.etc."login.defs".text` override (conflicts with NixOS shadow package). Replace with verified equivalents (`security.protectKernelImage` has no direct replacement — coverage comes from `boot.kernelParams` lockdown + `kernel.kexec_load_disabled`; `login.defs` goes through `security.loginDefs` structured options only). Deliverable: a lint step (`nix eval .#nixosConfigurations.server.config.system.build.toplevel`) that runs in CI and a changelog entry of every option removed.

### INFRA-04: Fix auditd rules to use NixOS paths (`/run/wrappers/bin/*`, `/run/current-system/sw/bin/*`)
- **Priority:** P1
- **Effort:** M
- **Depends on:** INFRA-03
- **Source:** MASTER-REVIEW.md STIG Must-fix #1, wiki/nixos-platform/nixos-gotchas.md §2, prd-stig-disa.md §6.1, prd-pci-dss.md Req 10

`/usr/bin/sudo` and `/usr/sbin/useradd` do not exist on NixOS; the PRD's audit rules monitor nothing as written. Deliverable: port §6.1 rules into the `audit-and-aide` module using `/run/wrappers/bin/{sudo,su,passwd,chsh,newgrp}` for setuid wrappers, `/run/current-system/sw/bin/chage` for non-setuid tools, watchers on `/etc/passwd|group|shadow|gshadow`, `/nix/var/nix/profiles/system`, and `/run/current-system` to catch `nixos-rebuild` as the identity-change vector. Include the missing syscalls (`personality`, `ptrace`, `open_by_handle_at`, failed `open`/`openat` with EACCES/EPERM) and end with `-e 2` to lock rules.

### INFRA-05: Build the `stig-baseline` module as the single owner of kernel/sysctl/boot params
- **Priority:** P1
- **Effort:** L
- **Depends on:** ARCH-02, INFRA-03
- **Source:** prd-stig-disa.md §8.3, wiki/compliance-frameworks/cross-framework-matrix.md, wiki/compliance-frameworks/canonical-config-values.md (STIG superset)

Consolidate all `boot.kernel.sysctl` + `boot.kernelParams` + `boot.blacklistedKernelModules` into one module so no other module can re-declare them (prevents the attribute-collision problem called out in Systemic #1). Deliverable: a module that owns ASLR, `kernel.yama.ptrace_scope=2`, `kernel.unprivileged_bpf_disabled=1`, `kernel.io_uring_disabled=2`, `net.ipv4.tcp_rfc1337=1`, `kernel.panic_on_oops=1`, SLAB/init_on_alloc/init_on_free, `vsyscall=none`, `kexec_load_disabled=1`, `intel_iommu=on iommu=pt`, and the STIG kernel-module blacklist superset. De-duplicate the PRD's duplicate `kernel.sysrq = 0`.

### INFRA-06: PAM configuration via structured NixOS options (no `.text` overrides)
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-02, INFRA-03
- **Source:** MASTER-REVIEW.md STIG Must-fix #5, prd-stig-disa.md §4.2, wiki/compliance-frameworks/canonical-config-values.md (A.6)

Current PRD mixes `security.pam.services.<name>.text` overrides with structured `rules.*` entries — mutually exclusive. Deliverable: rewrite PAM for `login`, `sshd`, `sudo`, `su` using `security.pam.services.*.rules.auth/account/password` exclusively; wire in `pam_faillock` (5 attempts, 1800s lockout), `pam_pwquality` (minlen=15, minclass=4), `pam_pwhistory` (remember=24), and `pam_tally2`-replacement via `pam_faillock`. SSH MFA keeps `KbdInteractiveAuthentication=true` + `AuthenticationMethods=publickey,keyboard-interactive` so TOTP still works.

### INFRA-07: SSH hardening aligned with canonical config (FIPS-compatible cipher set)
- **Priority:** P1
- **Effort:** S
- **Depends on:** ARCH-02, INFRA-06
- **Source:** wiki/compliance-frameworks/canonical-config-values.md (SSH A.4), prd-stig-disa.md §4.1 and §11.1

Deliverable: single `services.openssh` block — `PasswordAuthentication=false`, AES-GCM + AES-CTR ciphers only (drop ChaCha20 for FIPS), ETM MACs only, `ClientAliveInterval=600`, `ClientAliveCountMax=0`, `PermitRootLogin=no`, `AllowUsers` allowlist, `MaxAuthTries=3`, `LoginGraceTime=30`, host key set is ed25519 + rsa-4096, banner from §10.1. Verify sshd actually starts (no `Protocol 2`, no deprecated kbd aliases).

### INFRA-08: Centralized syslog forwarding over TLS (rsyslog + RELP) or journald remote
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-02 (secrets-mgmt choice), INFRA-01
- **Source:** MASTER-REVIEW.md STIG Must-fix #5, HIPAA Should-fix (TCP without TLS), PCI Must-fix #3, prd-pci-dss.md §10.3.3, prd-stig-disa.md §6.4

Local-only logs fail PCI 10.3.3 and HIPAA §164.312(e). Deliverable: `services.rsyslogd` with `imrelp` forwarding over TLS to a configurable SIEM endpoint, CA + client cert materialized from sops-nix/agenix (pending ARCH secrets choice), audit-dispatcher bridge (`audispd` → rsyslog via `/run/current-system/sw/bin/audispd`), queue spooling on link loss, and a `systemd.timer` health-check that pages if the forwarder stops shipping for >15 min.

### INFRA-09: AIDE with NixOS-correct path set + working alerting
- **Priority:** P1
- **Effort:** M
- **Depends on:** ARCH-02, INFRA-08
- **Source:** MASTER-REVIEW.md PCI Should-fix (FIM paths), HIPAA Must-fix #2 (`$SERVICE_RESULT`), prd-stig-disa.md §7.2, prd-pci-dss.md §11.5, wiki/pci-dss/pci-dss-highlights.md (AIDE paths)

Deliverable: `services.aide` enabled with database on encrypted volume, monitored paths = `/etc`, `/boot`, `/run/current-system`, `/etc/static`, `/etc/shadow`, `/etc/ssh`, `/var/log/audit`, `/etc/pam.d`, `/etc/nftables.conf` (explicitly drop `/usr/bin` and `/usr/sbin` — empty on NixOS). Alerting lives inside the `aide.service` via `ExecStartPost` or `OnFailure=notify-admin@%n.service` using `%i` (not `$1`) and reading status from `journalctl _SYSTEMD_UNIT=aide.service`, not `$SERVICE_RESULT` in a separate unit. Hourly timer per canonical config A.8.

### INFRA-10: ClamAV with `clamonacc` on writable paths; document `/nix/store` exclusion
- **Priority:** P2
- **Effort:** M
- **Depends on:** INFRA-05
- **Source:** MASTER-REVIEW.md PCI Must-fix #1, prd-pci-dss.md §5, wiki/pci-dss/pci-dss-highlights.md (Anti-Malware)

PCI 5.3.2 wants on-access scanning; the PRD only has on-demand. Deliverable: `services.clamav.daemon` + `services.clamav.updater` + a new `clamonacc` systemd unit scanning `/var/lib`, `/tmp`, `/home`, `/var/lib/agent-runner`, with `/nix/store` excluded and the exclusion justified in a `docs/risk-analysis/5.2.3.1-antimalware.md` artifact (required for v4.0 5.2.3.1). Weekly full-scan timer + daily `nix store verify --all` with alerting on any corruption via the INFRA-08 pipeline.

### INFRA-11: Core-dump suppression + `kernel.core_pattern=|/bin/false`
- **Priority:** P2
- **Effort:** S
- **Depends on:** INFRA-05
- **Source:** MASTER-REVIEW.md HIPAA Should-fix (core dumps), prd-stig-disa.md §3A.6

Segfaulting inference processes otherwise dump ePHI/PII/CHD to disk. Deliverable: `systemd.coredump.extraConfig = "Storage=none"`, `security.pam.loginLimits` setting `core` hard/soft to 0 for all users, `fs.suid_dumpable=0` in sysctl, and `kernel.core_pattern` set to `|/bin/false` via INFRA-05. Document in HIPAA risk analysis.

### INFRA-12: Mount hardening — `nosuid`/`nodev`/`noexec` on `/tmp`, `/var/tmp`, `/home`, `/dev/shm`
- **Priority:** P2
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md STIG Must-fix #5, prd-stig-disa.md §3A.3

Deliverable: `fileSystems."/tmp".options`, `/var/tmp`, `/dev/shm`, `/home` all get `nosuid,nodev,noexec` as appropriate; `/boot` gets `nosuid,nodev`. For `/tmp` use a tmpfs mount sized by RAM. Verify that Nix build sandboxes and any agent sandbox writable paths still function (Nix build root is `/nix/var`, not `/tmp`, but verify).

### INFRA-13: Disable Ctrl-Alt-Del, require auth for emergency/rescue targets
- **Priority:** P2
- **Effort:** S
- **Depends on:** none
- **Source:** MASTER-REVIEW.md STIG Must-fix #5, prd-stig-disa.md §3A.4 and §3A.5

Deliverable: `systemd.services."ctrl-alt-del".enable = false` via mask, `systemd.targets.{emergency,rescue}.unitConfig.OnFailure` does not bypass password prompt, root password in `/etc/shadow` is set (empty root = no emergency recovery), and the serial console login still requires auth.

### INFRA-14: TLS cipher selection for Nginx front — no CBC, no RC4, FIPS-compatible list
- **Priority:** P2
- **Effort:** S
- **Depends on:** ARCH-02
- **Source:** MASTER-REVIEW.md HIPAA Should-fix (`HIGH:!aNULL:!MD5:!RC4`), prd-stig-disa.md §11.3, prd-pci-dss.md Req 4

Deliverable: `services.nginx.sslCiphers` set to an explicit allowlist (TLS 1.3 suites + AES-GCM-only TLS 1.2 fallbacks, no CBC). Set `sslProtocols = "TLSv1.2 TLSv1.3"`, `ssl_prefer_server_ciphers on`, OCSP stapling enabled. Nginx reverse-proxies Ollama 11434 and app API 8000 per canonical config.

### INFRA-15: Vulnerability scanning plan — acknowledge vulnix ≠ network scanner, add ADR for OpenVAS/Nessus
- **Priority:** P2
- **Effort:** M
- **Depends on:** ARCH-02, INFRA-08
- **Source:** MASTER-REVIEW.md PCI Must-fix #2, prd-pci-dss.md §11.3.1, wiki/pci-dss/pci-dss-highlights.md (Vulnerability Scanning)

Deliverable: weekly `vulnix` timer for package CVE auditing (output piped to a real JSON artifact — the PRD's `vulnix ... > foo.json` lies, vulnix output is not JSON), monthly `lynis audit system` for CIS benchmarks, plus an ADR (`docs/adr/INFRA-15-network-scanning.md`) selecting OpenVAS vs Nessus vs Qualys for the quarterly authenticated network scan required by 11.3.1.3. Scans either run from a separate host or (if on-host) from a dedicated systemd unit with its own UID.

### INFRA-16: CVSS-driven remediation timelines + `flake.lock` update cadence
- **Priority:** P2
- **Effort:** S
- **Depends on:** INFRA-15
- **Source:** MASTER-REVIEW.md PCI Should-fix (CVSS timelines), wiki/compliance-frameworks/canonical-config-values.md (A.7 Patching), prd-pci-dss.md Req 6.3

Deliverable: a documented patching SLA (Critical 30d, High 90d, Medium 180d, zero-day 72h per canonical config), a weekly `systemd.timer` that runs `nix flake update`, `nixos-rebuild build --dry-run`, and a vulnix diff; outputs go to evidence store and page if Critical/High is past SLA. Addresses NIST RA-5 + PCI 6.3.3.

### INFRA-17: Evidence-collection service with real NixOS metadata
- **Priority:** P2
- **Effort:** M
- **Depends on:** INFRA-04, INFRA-09, INFRA-15
- **Source:** MASTER-REVIEW.md STIG Should-fix (evidence missing `nixos-version`), prd-stig-disa.md §13.1, prd-nist-800-53.md §AU Evidence Artifacts

Deliverable: a `systemd.service` + weekly timer + post-`nixos-rebuild switch` hook that collects `nixos-version --json`, `nix-info -m`, `jq .nodes < flake.lock` (flake lock hash), `auditctl -l`, `aide --check` summary, `nftables list ruleset`, vulnix JSON, sysctl dump, systemd unit sandbox report (`systemd-analyze security`), and TLS cert inventory — into `/var/lib/compliance-evidence/` with retention per canonical config (365d journal, 6y policy docs).

### INFRA-18: UEFI Secure Boot + bootloader password (lanzaboote)
- **Priority:** P3
- **Effort:** L
- **Depends on:** ARCH-02
- **Source:** MASTER-REVIEW.md STIG Must-fix #5 (Secure Boot missing), prd-stig-disa.md §3A.1 and §3A.2

Deliverable: `lanzaboote` flake input enabled, signing keys stored via sops-nix/agenix (pending ARCH), `boot.loader.systemd-boot` replaced by lanzaboote's stub, a GRUB/systemd-boot superuser password for any interactive boot-menu change, and validation via `bootctl status` + `sbctl verify`. Drop in Phase 2 if hardware UEFI is not Secure-Boot-capable; record as risk accepted.

### INFRA-19: OpenSSL FIPS provider loading (or remove FIPS claim)
- **Priority:** P3
- **Effort:** M
- **Depends on:** INFRA-14
- **Source:** MASTER-REVIEW.md Systemic #2 (fips=yes without provider), prd-stig-disa.md §11.2, wiki/compliance-frameworks/canonical-config-values.md (FIPS note)

Setting `fips=yes` in `openssl.cnf` without a FIPS-validated provider loaded breaks TLS outright. Deliverable: either (a) load the FIPS provider via a custom `openssl.cnf` with `providers.fips.activate = 1` and ship the FIPS module alongside, or (b) drop the FIPS claim and document "FIPS-compatible algorithms, not FIPS-validated" per canonical config — recommend (b) for Year 1 given NixOS has no FIPS-validated OpenSSL build.

### INFRA-20: Thunderbolt / USB4 DMA protection via IOMMU + kernel config
- **Priority:** P3
- **Effort:** S
- **Depends on:** INFRA-05
- **Source:** MASTER-REVIEW.md STIG Should-fix (Thunderbolt), prd-stig-disa.md §3A.7

Deliverable: `intel_iommu=on iommu=pt` (already in INFRA-05), `boot.kernel.sysctl."kernel.dma_allow_unsafe_interrupts" = 0`, thunderbolt auth via `services.hardware.bolt.enable = true` with "none" authorization by default, and a documented physical-access assumption in the threat model.

### INFRA-21: USB / removable-media controls (`usbguard`)
- **Priority:** P3
- **Effort:** S
- **Depends on:** INFRA-20
- **Source:** prd-stig-disa.md §9.4

Deliverable: `services.usbguard.enable = true` with a whitelist generated from currently-attached known-good devices at install time, default `ImplicitPolicyTarget = block`, `PresentDevicePolicy = apply-policy`, and an evidence hook that logs policy changes to the audit pipeline. Optional: block USB mass-storage via kernel module blacklist for maximum posture.

### INFRA-22: Minimal package set + kernel module blacklist enforcement
- **Priority:** P3
- **Effort:** S
- **Depends on:** INFRA-05
- **Source:** prd-stig-disa.md §7.3 and §7.4

Deliverable: `environment.systemPackages` kept to the compliance-essential set (auditd tools, aide, clamav, vulnix, lynis, nftables, openssl, jq), kernel modules blacklist consolidated in `stig-baseline` only (firewire, usb-storage conditional, cramfs, freevxfs, jffs2, hfs, hfsplus, squashfs, udf, dccp, sctp, rds, tipc, bluetooth, wifi modules if no wireless), and a test that asserts no other module declares `boot.blacklistedKernelModules`.

---

## Open questions for the architecture agent

- **ARCH secrets-mgmt choice blocks INFRA-08 and INFRA-18**: rsyslog TLS certs and lanzaboote signing keys both need a secrets store. sops-nix vs agenix must be picked in ARCH-0x before these can ship.
- **ARCH-02 canonical config must include**: (a) the exact LAN CIDR and LAN NIC name convention INFRA-01 uses, (b) the SIEM endpoint hostname/port that INFRA-08 targets, (c) whether IPv6 is in scope at all — the PRD flips on this.
- **ARCH threat model**: INFRA-18 (Secure Boot) and INFRA-20 (Thunderbolt DMA) are only worth the effort if physical access is in the threat model — architecture agent owns that call.
- **ARCH evidence-store location**: INFRA-17 writes to `/var/lib/compliance-evidence`; if architecture decides evidence belongs on a separate encrypted volume or shipped to S3-compatible storage, INFRA-17 changes shape.
