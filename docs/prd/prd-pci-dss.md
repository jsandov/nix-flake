# PRD Module: PCI DSS v4.0 Control Mapping

## Purpose

This document maps the NixOS AI agentic server configuration to the Payment Card Industry Data Security Standard version 4.0. It is a companion module to the main PRD and provides requirement-by-requirement analysis of which PCI DSS controls are addressable at the host level, which require organizational or third-party controls, and how the existing NixOS flake modules satisfy or partially satisfy each requirement.

PCI DSS v4.0 was published March 2022 with a transition deadline of March 31, 2024 for the base requirements. Several new requirements designated as "future-dated" became mandatory on March 31, 2025. This document flags those newly effective requirements explicitly.

> **Canonical Configuration Values**: All resolved configuration values for this system are defined in `prd.md` Appendix A. When inline Nix snippets in this document specify values that differ from Appendix A, the Appendix A values take precedence. Inline Nix code in this module is illustrative and shows the PCI DSS-specific rationale; the implementation flake uses only the canonical values.

## CDE Scoping Decision

### When This Server Is In Scope

This server enters PCI DSS scope if any of the following conditions are true:

- The server processes, stores, or transmits cardholder data (CHD) or sensitive authentication data (SAD) directly, for example through an AI service that ingests transaction records, card numbers, or tokenized payment data for analysis or inference.
- The server provides security services to the cardholder data environment, such as logging, authentication, or DNS resolution for CDE-connected systems.
- The server shares a network segment with CDE systems without validated segmentation controls.
- An agentic workflow running on the server has access to APIs or databases that contain CHD.

### When This Server Is Out of Scope

The server is out of PCI scope when:

- It is deployed on a network segment that is fully segmented from any CDE, with no connectivity to systems that process CHD.
- No cardholder data, tokenized card data, or sensitive authentication data is ingested, cached, or transmitted by any service on the host.
- No agent workflow has access to payment APIs, payment databases, or card-present device interfaces.

### Scoping Recommendation

For most deployments of this AI server, the recommended posture is to maintain it as a "connected-to" or "out-of-scope" system by enforcing network segmentation from the CDE. If the server must process payment-adjacent data for inference, it should be treated as a CDE system component and all 12 PCI DSS requirements apply at the host level.

Even when formally out of scope, implementing the controls in this document provides defense-in-depth and simplifies future scope changes.

### Connected-to-System Reduced Requirements

When this server is classified as "connected-to" (provides services to or receives services from the CDE but does not itself process, store, or transmit CHD), only a subset of PCI DSS requirements applies. The following requirements are typically in scope for connected-to systems:

- **Requirement 1**: Full applicability. Network security controls must isolate the connected-to system from the CDE with validated segmentation.
- **Requirement 2**: Full applicability. Secure configuration standards apply to all in-scope system components.
- **Requirement 5**: Full applicability. Anti-malware protections must be deployed.
- **Requirement 6**: Full applicability. Vulnerability management and secure development practices apply.
- **Requirement 7** (portions): Access to the connected-to system must be restricted on a need-to-know basis. Specifically 7.1, 7.2.1-7.2.5, and 7.3 apply.
- **Requirement 8** (portions): Unique user IDs, MFA for administrative access, and session management apply. Specifically 8.1-8.4 and 8.6 apply.
- **Requirement 10** (portions): Logging and monitoring of access to the connected-to system is required. Specifically 10.1-10.5 and 10.7 apply.
- **Requirement 11** (portions): Internal vulnerability scanning, FIM, and segmentation validation apply. Specifically 11.3.1, 11.4.5, and 11.5.2 apply.
- **Requirement 12** (portions): Organizational policies, incident response, and security awareness apply.

Requirements 3, 4, and 9 generally do not apply to connected-to systems unless CHD transits or is stored on them. The QSA has final authority on scoping; this list reflects the common interpretation per the PCI SSC scoping guidance.

### GPU VRAM and LLM Context as Potential CHD Residue

When this server runs LLM inference (via Ollama or similar), cardholder data submitted in prompts or retrieved by agentic workflows may exist in the following volatile locations:

- **GPU VRAM**: Model weights, KV cache, and intermediate activations reside in VRAM during inference. If CHD is included in a prompt, fragments may persist in VRAM until overwritten by subsequent inference requests or until the GPU context is released.
- **KV cache**: Ollama and other inference runtimes maintain a key-value cache for the active context window. CHD tokens remain in the KV cache until the session ends or the context is evicted.
- **System RAM**: Depending on model size and offloading configuration, portions of the model context and intermediate state may spill to system RAM.
- **Swap**: If encrypted swap is not configured, VRAM-spilled or RAM-resident CHD could be written to unencrypted disk.

**Recommendations for CHD workloads:**

1. Enable encrypted swap (see Requirement 3 section) to prevent CHD leakage to disk.
2. Configure Ollama to clear model context between sessions when processing CHD: restart the Ollama service or use the API to unload models after CHD-bearing sessions.
3. Treat GPU VRAM as volatile CHD storage for scoping purposes. While VRAM is not persistent and is overwritten rapidly during active inference, a QSA may require documented evidence that CHD is not retained across sessions.
4. For high-sensitivity deployments, consider a systemd service that forces a model unload (and thus VRAM/KV cache clearing) after each CHD-bearing request completes:

```nix
{
  # Session-level VRAM clearing for CHD workloads
  # Invoke after each CHD-bearing inference session
  systemd.services.ollama-clear-session = {
    description = "Clear Ollama model context to purge potential CHD residue from VRAM";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.curl}/bin/curl -s http://127.0.0.1:11434/api/generate -d '{\"model\": \"placeholder\", \"keep_alive\": 0}'";
      # NOTE: The correct Ollama API call to unload a model is POST /api/generate
      # with {"model": "<name>", "keep_alive": 0}, not DELETE /api/generate.
    };
  };
}
```

5. Document the VRAM residue risk in the targeted risk analysis required by 5.2.3.1, noting that VRAM is volatile, not directly addressable by external processes, and overwritten on the next inference load.

---

## Network Segmentation

PCI DSS v4.0 does not require network segmentation, but without it the entire network is in scope. For a LAN-only AI server, segmentation is the primary mechanism for limiting PCI scope.

### Segmentation Architecture

```nix
{
  # NOTE: This block uses networking.nftables for segmentation rules.
  # Do NOT also use networking.firewall.extraCommands with iptables syntax.
  # NixOS 24.11 defaults to nftables. See prd.md Appendix A.2.
  # The networking.firewall options below generate nftables rules internally.

  # Bind all services exclusively to the non-CDE LAN interface
  # NOTE: Canonical firewall port allowlists are in prd.md Appendix A.2.
  # The ports below are illustrative for PCI DSS segmentation rationale.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];  # Default deny on all interfaces

    # LAN-facing interface only
    interfaces.enp3s0 = {
      allowedTCPPorts = [ 22 11434 8000 ];
    };
  };

  # If the host has a second interface toward the CDE, block it entirely
  networking.firewall.interfaces.enp4s0 = {
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Egress controls: block all outbound to CDE subnets
  # NOTE: Canonical firewall and nftables values are in prd.md Appendix A.2.
  # The rules below are illustrative for PCI DSS segmentation rationale.
  networking.nftables = {
    enable = true;
    ruleset = ''
      table inet pci_segmentation {
        chain output {
          type filter hook output priority 0; policy accept;
          # Block outbound to CDE VLAN
          ip daddr 10.10.20.0/24 drop;
          ip daddr 10.10.21.0/24 drop;
        }
        chain input {
          type filter hook input priority 0; policy drop;
          # Allow established/related
          ct state established,related accept;
          # Allow loopback
          iifname "lo" accept;
          # Allow LAN interface only
          iifname "enp3s0" tcp dport { 22, 11434, 8000 } accept;
        }
      }
    '';
  };

  # Bind services to specific addresses, not 0.0.0.0
  services.openssh.listenAddresses = [
    { addr = "192.168.1.50"; port = 22; }
  ];
}
```

### Segmentation Validation

PCI DSS 11.4.5 requires segmentation controls to be confirmed at least every six months (every twelve months for service providers with the updated v4.0 cadence). Create a systemd timer that performs automated segmentation testing:

```nix
{
  systemd.services.pci-segmentation-test = {
    description = "PCI DSS segmentation validation";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "seg-test" ''
        # CDE ranges — MUST be configured per deployment.
        # Replace these with the actual CDE subnet(s) and host addresses.
        # At minimum, enumerate all hosts in the CDE VLAN(s).
        # For dynamic environments, pull CDE ranges from a configuration file:
        #   CDE_HOSTS=$(cat /etc/pci/cde-hosts.conf)
        CDE_HOSTS="10.10.20.1 10.10.20.2 10.10.21.1"

        FAILED=0
        for host in $CDE_HOSTS; do
          # Test all TCP ports (full port range scan)
          OPEN_TCP=$(${pkgs.nmap}/bin/nmap -Pn -sT -p- "$host" 2>/dev/null | grep -c "open" || true)
          if [ "$OPEN_TCP" -gt 0 ]; then
            echo "FAIL: TCP segmentation breach to $host ($OPEN_TCP open ports)" | systemd-cat -p crit
            FAILED=1
          fi

          # Test common UDP ports (DNS, SNMP, NTP, syslog, TFTP, NetBIOS)
          OPEN_UDP=$(${pkgs.nmap}/bin/nmap -Pn -sU -p 53,69,123,137,138,161,162,514 "$host" 2>/dev/null | grep -c "open" || true)
          if [ "$OPEN_UDP" -gt 0 ]; then
            echo "FAIL: UDP segmentation breach to $host ($OPEN_UDP open ports)" | systemd-cat -p crit
            FAILED=1
          fi
        done

        if [ "$FAILED" -eq 1 ]; then
          exit 1
        fi
        echo "PASS: segmentation validated for all CDE hosts (TCP full-range + UDP common ports)" | systemd-cat -p info
      '';
    };
  };

  systemd.timers.pci-segmentation-test = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "monthly";
    timerConfig.Persistent = true;
  };
}
```

Note: The CDE host list and subnet ranges shown above are examples. Each deployment MUST configure the actual CDE IP ranges. For environments with dynamic CDE addressing, maintain a `/etc/pci/cde-hosts.conf` file managed through the Nix configuration and read by the segmentation test script. The full TCP port range scan (`-p-`) ensures that no unexpected services are reachable, not just common database or web ports. UDP scanning covers protocols commonly exploited for lateral movement (DNS, SNMP, NetBIOS).

---

## Requirement 1: Install and Maintain Network Security Controls

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 1.1.1 | Security policies and procedures defined and known | Organizational + host | Flake repo documents firewall policy as code |
| 1.1.2 | Roles and responsibilities assigned | Organizational | Out of scope for host config |
| 1.2.1 | Configuration standards for NSCs defined and implemented | Host | `networking.firewall` and `networking.nftables` module |
| 1.2.2 | Changes to network connections reviewed and approved | Process | Git-based change control on flake repo |
| 1.2.3 | Network diagram maintained showing all connections | Process + documentation | See network diagram requirement below |
| 1.2.5 | All services, protocols, and ports allowed are identified and approved | Host | Explicit `allowedTCPPorts` per interface |
| 1.2.6 | Security features defined for insecure services | Host | No insecure services exposed; SSH key-only |
| 1.2.7 | NSCs reviewed at least every six months | Process + host | Timer-based segmentation test above |
| 1.2.8 | Configuration files for NSCs secured from unauthorized access | Host | Nix store is read-only; firewall config immutable post-build |
| 1.3.1 | Inbound traffic restricted to what is necessary | Host | Default-deny firewall with per-interface allowlist |
| 1.3.2 | Outbound traffic restricted to what is necessary | Host | nftables egress rules blocking CDE subnets |
| 1.4.1 | NSCs between trusted and untrusted networks | Host | LAN-only; no public interface |
| 1.4.2 | Inbound traffic from untrusted to trusted restricted | Host | Default deny; no public ingress |
| 1.4.4 | **[NEW v4.0, effective March 2025]** Restrict inbound connections to authorized sources | Host | Interface-bound firewall rules |
| 1.4.5 | PAN disclosure restricted on internal networks | Process + application | Not applicable unless CHD is processed |
| 1.5.1 | NSCs on mobile/employee-owned devices | N/A | Server is a fixed host, not a mobile device |

### Requirement 1.2.3 -- Network Diagram

PCI DSS Requirement 1.2.3 mandates maintaining an accurate network diagram that shows all connections between the CDE and other networks, including wireless networks. This is a documentation deliverable, not a host-level control, but the NixOS configuration can generate supporting data.

The network diagram must include:

- All network segments and VLANs, with clear labeling of CDE, connected-to, and out-of-scope zones
- All connections between this server and other systems (SSH management, API endpoints, Ollama inference, log forwarding)
- All services and their listening ports, per interface
- Data flow direction for each connection (e.g., "AI server -> SIEM: syslog/RELP on port 2514, TLS")
- Firewall/NSC placement and rule summary
- Any wireless access points (N/A for this server)

The diagram should be reviewed and updated at least annually, after any significant network change, and as part of the semi-annual scope validation (12.5.2.1). Store the diagram in the flake repository alongside this document and treat updates as change-controlled commits.

Supporting data can be extracted from the running system:

```bash
# List all listening services and their bound addresses
ss -tlnp

# List all firewall rules
nft list ruleset

# List all active network interfaces and their addresses
ip addr show

# List all established connections
ss -tnp
```

### NixOS Implementation

The `lan-only-network` flake module directly addresses requirements 1.2.1, 1.2.5, 1.3.1, 1.3.2, 1.4.1, and 1.4.2. The declarative firewall configuration in the Nix store provides an immutable, version-controlled network security control that satisfies the configuration file protection requirement of 1.2.8.

The Git-managed flake repository provides a natural change-control mechanism for 1.2.2 (reviewing changes to network connections), although a formal approval workflow (pull request reviews, signed commits) should be layered on top.

---

## Requirement 2: Apply Secure Configurations to All System Components

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 2.1.1 | Security policies and procedures defined | Organizational + host | PRD and flake serve as policy artifacts |
| 2.2.1 | Configuration standards developed and implemented | Host | `stig-baseline` flake module |
| 2.2.2 | Vendor default accounts removed or disabled | Host | NixOS has no vendor default accounts; root login disabled via SSH |
| 2.2.3 | Primary functions requiring different security levels managed separately | Host | Separate systemd services with distinct users |
| 2.2.4 | Only necessary services, protocols, daemons enabled | Host | Minimal NixOS profile; only declared services run |
| 2.2.5 | Insecure services secured with additional features if present | Host | No insecure services; SSH hardened |
| 2.2.6 | System security parameters configured to prevent misuse | Host | systemd hardening directives on all services |
| 2.2.7 | All non-console admin access encrypted | Host | SSH key-only; no telnet/HTTP admin |
| 2.3.1 | **[NEW v4.0, effective March 2025]** Wireless environments not applicable or secured | Host | No wireless interfaces on server |
| 2.3.2 | **[NEW v4.0, effective March 2025]** Wireless vendor defaults changed | N/A | No wireless |

### NixOS Implementation

```nix
{
  # Minimal system — only declared packages and services
  environment.systemPackages = with pkgs; [
    aide
    nmap      # For segmentation testing
    lynis     # For CIS/security benchmarking
  ];

  # No vendor default accounts — NixOS creates only declared users
  users.mutableUsers = false;
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
  };

  # Disable all unnecessary services explicitly
  services.xserver.enable = false;
  services.printing.enable = false;
  services.avahi.enable = false;
  hardware.bluetooth.enable = false;

  # Remove SUID/SGID bits from unnecessary binaries
  security.wrappers = { };
}
```

NixOS is inherently strong for Requirement 2 because the declarative model means only explicitly enabled services run. The immutable Nix store prevents runtime drift of binaries and configuration files, directly supporting 2.2.6 (preventing misuse via configuration parameters).

---

## Requirement 3: Protect Stored Account Data

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 3.1.1 | Security policies defined for stored account data | Organizational | Only applies if CHD is stored |
| 3.2.1 | Data retention and disposal policies defined | Process + host | Retention policies for logs; CHD purge automation if applicable |
| 3.3.1 | PAN not stored after authorization unless business justification | Application | Out of scope for OS unless app stores CHD on disk |
| 3.3.2 | SAD not stored after authorization | Application | Out of scope for OS |
| 3.4.1 | PAN masked when displayed | Application | Out of scope for OS |
| 3.5.1 | PAN rendered unreadable anywhere it is stored | Host + application | Full-disk encryption (LUKS); application-layer tokenization |
| 3.5.1.1 | Hashes of PAN use keyed cryptographic hashes | Application | Out of scope for OS |
| 3.5.1.2 | If disk-level encryption used, additional controls required | Host | LUKS with separate key management |
| 3.6.1 | Cryptographic key management procedures defined | Process + host | sops-nix for key management |
| 3.7.1 | **[NEW v4.0, effective March 2025]** Key management documented formally | Process | Key lifecycle documentation required |

### CDE-Scoping Note

Most of Requirement 3 is out of scope for this server unless it stores cardholder data. However, 3.5.1.2 is significant: PCI DSS v4.0 explicitly states that full-disk or partition-level encryption alone does not satisfy 3.5.1 for removable media or for any storage accessible to the operating system's logical access controls. If PAN is stored on this host, application-layer encryption or tokenization is required in addition to LUKS.

### NixOS Implementation for Disk Encryption

```nix
{
  # LUKS full-disk encryption (configured at install time)
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/XXXX-XXXX";
    preLVM = true;
    allowDiscards = true;
  };

  # NOTE: swapDevices.*.encrypted was removed in NixOS 23.11+.
  # Use LUKS-based encrypted swap per prd.md Appendix A.9:
  #   Option 1: Configure swap on a LUKS volume via boot.initrd.luks.devices
  #   Option 2: Use swapDevices pointing to an already-opened LUKS device
  # For random-key encrypted swap (non-persistent, suitable for this use case):
  swapDevices = [{
    device = "/dev/disk/by-uuid/XXXX";  # Point to partition, NOT a LUKS device
    randomEncryption = {
      enable = true;
      cipher = "aes-xts-plain64";
      source = "/dev/urandom";
    };
  }];
}
```

For key management, secrets should be handled through sops-nix:

```nix
{
  sops = {
    defaultSopsFile = ./secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
    secrets = {
      "db-password" = { };
      "api-key" = { };
    };
  };
}
```

---

## Requirement 4: Protect Cardholder Data with Strong Cryptography During Transmission

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 4.1.1 | Security policies for CHD transmission defined | Organizational | Policy artifact |
| 4.2.1 | Strong cryptography used for CHD transmission over open/public networks | Host + application | TLS for all service endpoints |
| 4.2.1.1 | Trusted certificates used | Host | System CA bundle; optionally mTLS |
| 4.2.1.2 | **[NEW v4.0, effective March 2025]** Inventory of trusted keys and certificates maintained | Process + host | Certificate inventory documentation; see below |
| 4.2.2 | PAN secured if sent via end-user messaging | N/A | Server does not perform end-user messaging |

### Requirement 4.2.1.2 -- TLS Certificate Inventory

PCI DSS v4.0 Requirement 4.2.1.2 (effective March 2025) requires an inventory of all trusted keys and certificates used to protect PAN during transmission. For this server, the certificate inventory must include:

| Certificate | Purpose | Location | Expiry | Renewal Process |
|-------------|---------|----------|--------|-----------------|
| Nginx TLS cert (`ai-internal.lan`) | HTTPS for AI API and Ollama reverse proxy | `/run/secrets/tls-cert` (via sops-nix) | Per deployment | Manual renewal or ACME; update sops secret and rebuild |
| Nginx TLS key | Private key for Nginx TLS | `/run/secrets/tls-key` (via sops-nix) | Same as cert | Rotated with certificate |
| SSH host key (Ed25519) | SSH server authentication | `/etc/ssh/ssh_host_ed25519_key` | Does not expire | Regenerated on reinstall; fingerprint distributed to clients |
| Syslog CA cert | Validates SIEM server for RELP/TLS log forwarding | `/var/lib/secrets/syslog-ca.pem` | Per CA policy | Replaced when CA rotates; update sops secret and rebuild |
| sops-nix age key | Decrypts deployment secrets at build time | `/var/lib/sops-nix/key.txt` | Does not expire | Manual rotation with re-encryption of secrets.yaml |

This inventory must be:

- Reviewed at least annually as part of the scope validation (12.5.2.1)
- Updated whenever a certificate is added, removed, or renewed
- Stored alongside this document in the flake repository
- Extended per deployment to include any additional certificates (mTLS client certs, API gateway certs, etc.)

Automated certificate expiry monitoring is recommended:

```bash
# Check all PEM certificates for upcoming expiry
for cert in /run/secrets/tls-cert /var/lib/secrets/syslog-ca.pem; do
  EXPIRY=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
  echo "$cert expires: $EXPIRY"
done
```

### NixOS Implementation

Even on a LAN-only server, PCI DSS requires encryption in transit for cardholder data. Internal network traffic does not exempt the requirement.

```nix
{
  # TLS reverse proxy for Ollama and application APIs
  services.nginx = {
    enable = true;
    virtualHosts."ai-internal.lan" = {
      forceSSL = true;
      sslCertificate = "/run/secrets/tls-cert";
      sslCertificateKey = "/run/secrets/tls-key";

      # Strong TLS configuration per PCI DSS 4.2.1
      extraConfig = ''
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305;
        ssl_prefer_server_ciphers on;
        ssl_session_timeout 1d;
        ssl_session_cache shared:SSL:10m;
        ssl_session_tickets off;
      '';

      locations."/" = {
        proxyPass = "http://127.0.0.1:8000";
      };
      locations."/ollama/" = {
        proxyPass = "http://127.0.0.1:11434";
      };
    };
  };

  # SSH already provides encrypted management channel
  # NOTE: Canonical SSH cipher/KexAlgorithms/Macs values are in prd.md Appendix A.4.
  # The values below are illustrative for PCI DSS rationale; the implementation flake
  # uses the Appendix A.4 canonical values.
  services.openssh.settings = {
    Ciphers = [ "aes256-gcm@openssh.com" "chacha20-poly1305@openssh.com" ];
    KexAlgorithms = [ "curve25519-sha256" "curve25519-sha256@libssh.org" ];
    Macs = [ "hmac-sha2-512-etm@openssh.com" "hmac-sha2-256-etm@openssh.com" ];
  };
}
```

---

## Requirement 5: Protect All Systems and Networks from Malicious Software

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 5.1.1 | Security policies for malware protection defined | Organizational + host | Policy artifact; NixOS immutability as compensating control |
| 5.2.1 | Anti-malware deployed on all systems | Host | See analysis below |
| 5.2.2 | Anti-malware performs periodic and real-time scans | Host | ClamAV on-access scanning for writable paths + periodic full scan |
| 5.2.3 | Systems not commonly affected assessed for malware risk | Host | NixOS risk assessment below |
| 5.2.3.1 | **[NEW v4.0, effective March 2025]** Frequency of periodic evaluations for systems not using anti-malware defined in targeted risk analysis | Host + process | Annual risk assessment document |
| 5.3.1 | Anti-malware solution kept current | Host | ClamAV signature updates (4x daily) |
| 5.3.2 | Anti-malware performs periodic and real-time scans | Host | clamonacc on-access + weekly full scan |
| 5.3.2.1 | **[NEW v4.0, effective March 2025]** Periodic malware scan frequency defined in targeted risk analysis | Process | Risk analysis documentation |
| 5.3.3 | Anti-malware for removable media | Host | Removable media disabled |
| 5.3.4 | Audit logs for anti-malware enabled and retained | Host | ClamAV logs to journald + syslog forwarding |
| 5.3.5 | Anti-malware cannot be disabled by users | Host | Immutable Nix store; systemd service protection |
| 5.4.1 | **[NEW v4.0, effective March 2025]** Anti-phishing mechanisms to detect and protect against phishing | N/A for server | No email client on server |

### Anti-Malware and the NixOS Immutable Store

NixOS provides unique properties relevant to Requirement 5:

1. **Immutable Nix store**: All binaries and libraries in `/nix/store` are read-only and content-addressed. Runtime modification of executables is not possible through conventional malware techniques.
2. **Declarative package set**: Only explicitly declared packages are present. No package manager installs software outside the declared configuration.
3. **Atomic rollback**: If compromise is detected, the system can roll back to a known-good generation in seconds.
4. **Content-addressed integrity verification**: `nix store verify --all` cryptographically validates every path in the store against its expected hash. This is strictly stronger than signature-based AV for detecting tampering, because it detects ANY modification (not just known malware signatures). A daily verification timer with failure alerting (see below) provides continuous integrity assurance equivalent to or better than traditional AV for the immutable store.

However, PCI DSS assessors will generally still require anti-malware deployment. The recommended approach is to deploy ClamAV with on-access scanning for writable paths and periodic full scans, while documenting the NixOS immutability model as a compensating control in the targeted risk analysis required by 5.2.3.1.

The `/nix/store` exclusion from ClamAV scanning is justified because:
- The store is mounted read-only and cannot be modified by running processes
- Content-addressed hashing detects any corruption (bitrot, supply-chain, or adversarial)
- Scanning the store with signature-based AV adds no detection capability beyond what `nix store verify` already provides
- The store can contain hundreds of thousands of files; scanning it wastes resources without security benefit

### NixOS Implementation

```nix
{
  # ClamAV anti-malware with on-access scanning for writable paths
  services.clamav = {
    daemon = {
      enable = true;
      settings = {
        # On-access (real-time) scanning for all writable paths
        OnAccessIncludePath = [ "/var/lib" "/tmp" "/home" "/var/log" ];
        OnAccessExcludeUname = "clamav";
        OnAccessPrevention = true;
        VirusEvent = "/run/current-system/sw/bin/logger -t clamav 'VIRUS DETECTED: %v in %f'";
      };
    };
    updater = {
      enable = true;
      frequency = 4; # 4x daily signature updates
    };
  };

  # Periodic full-system scan (writable paths only; Nix store excluded)
  systemd.services.clamav-fullscan = {
    description = "ClamAV full system scan for PCI DSS Req 5";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.clamav}/bin/clamscan -r --infected --log=/var/log/clamav/scan.log /var/lib /home /tmp";
    };
  };

  systemd.timers.clamav-fullscan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };

  # Nix store integrity verification — compensating control for AV exclusion
  # This is STRONGER than AV for the Nix store: it detects ANY modification,
  # not just known malware signatures, because every path is verified against
  # its cryptographic content hash.
  systemd.services.nix-store-verify = {
    description = "Nix store integrity verification (PCI DSS Req 5 compensating control)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nix-verify" ''
        RESULT=$(nix store verify --all 2>&1)
        CORRUPT=$(echo "$RESULT" | grep -c "corrupted" || true)
        if [ "$CORRUPT" -gt 0 ]; then
          echo "CRITICAL: Nix store corruption detected — $CORRUPT corrupted paths" | systemd-cat -p crit
          echo "$RESULT" | systemd-cat -p crit
          # Alert via syslog (forwarded to SIEM by rsyslog)
          logger -p local6.crit -t nix-store-verify "CRITICAL: $CORRUPT corrupted paths in Nix store"
          exit 1
        fi
        echo "PASS: Nix store integrity verified — all paths valid" | systemd-cat -p info
      '';
    };
  };

  systemd.timers.nix-store-verify = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  # Disable removable media auto-mount
  services.udisks2.enable = false;
  boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 0;
}
```

---

## Requirement 6: Develop and Maintain Secure Systems and Software

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 6.1.1 | Security policies for secure development defined | Organizational | Policy artifact |
| 6.2.1 | Bespoke/custom software developed securely | Application | Applies to AI service code, agent code |
| 6.2.2 | Software development personnel trained in secure coding | Organizational | Out of scope for host config |
| 6.2.3 | Bespoke software reviewed before release | Process | Code review on flake changes |
| 6.2.3.1 | **[NEW v4.0, effective March 2025]** Manual or automated code review for bespoke software | Process | Nix flake review process |
| 6.2.4 | Software engineering techniques prevent common vulnerabilities | Application | Sandboxed agent runtime |
| 6.3.1 | Security vulnerabilities identified and managed | Host | Package CVE audit via vulnix; host hardening assessment via Lynis; see scanning section below |
| 6.3.2 | Inventory of bespoke and custom software | Host + process | `nix flake metadata`, `nix-store --query --requisites` |
| 6.3.3 | Software components protected from vulnerabilities via patching | Host | NixOS channel updates; `nixos-rebuild` |
| 6.4.1 | Public-facing web applications protected from attacks | N/A | No public-facing web applications (LAN-only) |
| 6.4.2 | Public-facing web applications have automated technical solution for attacks | N/A | LAN-only |
| 6.5.1 | Changes to systems managed through change control | Host + process | Git-managed flake; PRs for changes |
| 6.5.2 | Significant changes deployed only after testing | Process | `nixos-rebuild build` then `nixos-rebuild switch` |
| 6.5.3 | Pre-production environments separated from production | Process | NixOS VMs for testing |
| 6.5.4 | Roles and functions separated between production and development | Host | Separate user accounts |
| 6.5.5 | Live PANs not used in test environments | Process | Not applicable unless CHD is present |
| 6.5.6 | Test data and accounts removed before production | Process | Declarative config ensures clean state |

### NixOS Implementation

```nix
{
  # Vulnerability scanning for installed packages
  # Run: nix run nixpkgs#vulnix -- --system
  # This checks all packages against the NVD database

  # Software inventory generation
  # Run: nix-store --query --requisites /run/current-system | sort
  # Produces a complete bill of materials

  # Change control through flake lock
  # flake.lock pins exact dependency versions
  # nix flake update creates auditable lock file changes
}
```

The declarative nature of NixOS provides strong support for 6.5.1 (change control) because every system change is a Git commit to the flake repository. The `flake.lock` file provides a cryptographic record of all dependency versions, directly supporting 6.3.2 (software inventory).

---

## Requirement 7: Restrict Access to System Components and Cardholder Data by Business Need-to-Know

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 7.1.1 | Security policies for access control defined | Organizational + host | Policy artifact |
| 7.1.2 | Access control model defined | Host | Role-based: admin, agent, service accounts |
| 7.2.1 | Access control model implemented | Host | NixOS user/group declarations; systemd service isolation |
| 7.2.2 | Access assigned based on job classification and function | Host + process | Separate user accounts per role |
| 7.2.3 | Required privileges approved by authorized personnel | Process | PR-based approval for user changes |
| 7.2.4 | User accounts and access privileges reviewed periodically | Process | Semi-annual review |
| 7.2.5 | All application and system accounts assigned and managed | Host | `users.mutableUsers = false` ensures declarative-only accounts |
| 7.2.5.1 | **[NEW v4.0, effective March 2025]** Access by application and system accounts managed and assigned based on least privilege | Host | systemd `DynamicUser`, `PrivateTmp`, etc. |
| 7.2.6 | **[NEW v4.0, effective March 2025]** All user access to query repositories of stored CHD restricted | Application | N/A unless CHD is stored |
| 7.3.1 | Access control system in place | Host | Linux DAC + systemd sandboxing |
| 7.3.2 | Access control system configured for need-to-know | Host | Per-service file permissions; `ReadWritePaths` |
| 7.3.3 | Access control system set to deny all by default | Host | `ProtectSystem = "strict"` on services |

### NixOS Implementation

```nix
{
  # Declarative users — no ad-hoc account creation
  users.mutableUsers = false;

  users.users = {
    admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
    };
    # Ollama service account — no login shell
    ollama = {
      isSystemUser = true;
      group = "ollama";
      home = "/var/lib/ollama";
      shell = pkgs.shadow + "/bin/nologin";
    };
    # Agent service account — no login shell
    agent = {
      isSystemUser = true;
      group = "agent";
      home = "/var/lib/agent-runner";
      shell = pkgs.shadow + "/bin/nologin";
    };
  };

  users.groups = {
    ollama = { };
    agent = { };
  };

  # Least-privilege service isolation (see also Requirement 2)
  systemd.services.ollama = {
    serviceConfig = {
      User = "ollama";
      Group = "ollama";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ "/var/lib/ollama" ];
      PrivateTmp = true;
    };
  };
}
```

The `users.mutableUsers = false` setting is critical for PCI DSS compliance: it ensures that all user accounts are declared in the Nix configuration and that no accounts can be created at runtime through `useradd` or similar tools. Combined with the Git-managed flake, this provides a full audit trail of account provisioning (7.2.3) and makes periodic access reviews (7.2.4) straightforward.

---

## Requirement 8: Identify Users and Authenticate Access to System Components

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 8.1.1 | Security policies for identification and authentication defined | Organizational | Policy artifact |
| 8.2.1 | All users assigned unique ID | Host | Named user accounts in Nix config |
| 8.2.2 | Group/shared/generic accounts not used except by exception | Host | Each role has dedicated account |
| 8.2.3 | Additional requirements for service provider shared auth | N/A | Not a service provider |
| 8.2.4 | Addition/deletion/modification of user IDs managed | Host | `users.mutableUsers = false`; Git PR workflow |
| 8.2.5 | Access for terminated users immediately revoked | Process + host | Remove from Nix config; rebuild |
| 8.2.6 | Inactive user accounts removed/disabled within 90 days | Process | Monitoring automation |
| 8.2.7 | Accounts used by third parties managed specifically | Process | N/A for single-operator deployment |
| 8.2.8 | Idle sessions time out within 15 minutes | Host | SSH ClientAliveInterval; tmux lock |
| 8.3.1 | All user access authenticated | Host | SSH key-based auth; no anonymous access |
| 8.3.2 | Strong cryptography for authentication | Host | Ed25519 SSH keys |
| 8.3.4 | Invalid authentication attempts limited | Host | `pam_faillock` configuration |
| 8.3.5 | Passwords meet complexity requirements if used | Host | Password auth disabled; key-only |
| 8.3.6 | Passwords meet minimum length if used | Host | N/A -- key-only auth |
| 8.3.9 | Passwords changed at least every 90 days if used | Host | N/A -- key-only auth |
| 8.3.10 | **[NEW v4.0, effective March 2025]** Password used as only factor meets minimum of 12 characters | Host | N/A -- key-only auth |
| 8.3.10.1 | **[NEW v4.0, effective March 2025]** Password minimum 15 characters if system does not meet 8.3.6 | Host | N/A -- key-only auth |
| 8.4.1 | MFA implemented for non-console admin access into CDE | Host | See MFA section below |
| 8.4.2 | MFA for all access into the CDE | Host | See MFA section below |
| 8.4.3 | **[NEW v4.0, effective March 2025]** MFA for all non-console administrative access | Host | See MFA section below |
| 8.5.1 | MFA implemented correctly (not susceptible to replay) | Host | TOTP or FIDO2 |
| 8.6.1 | Interactive login for system/application accounts managed | Host | `nologin` shell on service accounts |
| 8.6.2 | Passwords/passphrases for system accounts not hardcoded | Host | sops-nix; no plaintext secrets |
| 8.6.3 | **[NEW v4.0, effective March 2025]** Passwords for application/system accounts managed per defined policies | Host + process | sops-nix rotation |

### MFA Requirements

PCI DSS v4.0 significantly expanded MFA requirements. Requirement 8.4.2 now requires MFA for all access into the CDE, not just remote administrative access. Requirement 8.4.3 (effective March 2025) extends MFA to all non-console administrative access even outside the CDE.

For this NixOS server, MFA is implemented at the SSH layer:

```nix
{
  # MFA via TOTP (Google Authenticator PAM module)
  security.pam.services.sshd = {
    googleAuthenticator.enable = true;
  };

  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = true;     # Required for PAM TOTP prompt
    AuthenticationMethods = "publickey,keyboard-interactive";  # Require both key + TOTP
    ChallengeResponseAuthentication = true;  # DEPRECATED: Alias for KbdInteractiveAuthentication in OpenSSH 8.7+. See prd.md Appendix A.4. Remove once KbdInteractiveAuthentication is set above.
    UsePAM = true;
  };

  # Alternative: FIDO2/U2F hardware token via pam-u2f
  # security.pam.services.sshd.u2fAuth = true;

  environment.systemPackages = [ pkgs.google-authenticator ];

  # Protect TOTP seed file — restrict to owner read-only
  # The ~/.google_authenticator file contains the TOTP secret seed.
  # If this file is readable by other users, the second factor is compromised.
  systemd.tmpfiles.rules = [
    "z /home/admin/.google_authenticator 0400 admin admin -"
  ];
}
```

The `AuthenticationMethods = "publickey,keyboard-interactive"` line is critical: it requires both the SSH key and the TOTP code, satisfying the two-factor requirement. This satisfies 8.4.1, 8.4.2 (if the server is in the CDE), and 8.4.3.

The TOTP seed file (`~/.google_authenticator`) is restricted to mode `0400` (owner read-only) via systemd-tmpfiles. This prevents other users on the system from reading the TOTP secret, which would allow them to generate valid second-factor codes. The tmpfiles rule is enforced on every boot and can be triggered manually with `systemd-tmpfiles --create`.

### Session Timeout

```nix
{
  services.openssh.settings = {
    ClientAliveInterval = 300;     # 5-minute keepalive check
    ClientAliveCountMax = 3;       # Disconnect after 15 min idle
  };

  # Lock screen timeout for console access
  programs.bash.interactiveShellInit = ''
    TMOUT=900  # 15-minute shell timeout
    readonly TMOUT
    export TMOUT
  '';
}
```

### Account Lockout

```nix
{
  security.pam.services.sshd.rules.auth = {
    faillock_preauth = {
      order = 1010;
      control = "required";
      modulePath = "pam_faillock.so";
      args = [ "preauth" "silent" "deny=6" "unlock_time=1800" "fail_interval=900" ];
    };
    faillock_authfail = {
      order = 2010;
      control = "[default=die]";
      modulePath = "pam_faillock.so";
      args = [ "authfail" "deny=6" "unlock_time=1800" "fail_interval=900" ];
    };
  };
}
```

This locks accounts after 6 failed attempts for 30 minutes, satisfying 8.3.4.

---

## Requirement 9: Restrict Physical Access to Cardholder Data

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 9.1.1 | Security policies for physical access defined | Organizational | Policy artifact |
| 9.2.1-9.2.4 | Facility entry controls | Organizational/physical | Out of scope for host config |
| 9.3.1-9.3.4 | Authorization for physical access | Organizational/physical | Out of scope for host config |
| 9.4.1-9.4.7 | Media handling | Process | Encrypted disk; removable media controls |
| 9.5.1 | POI devices protected | N/A | No point-of-interaction devices |

### Scope Note

Requirement 9 is primarily a physical security and facility management requirement. Host-level controls are limited to:

- Full-disk encryption (protects data if the physical server is stolen)
- Disabled USB auto-mount (`services.udisks2.enable = false`)
- BIOS/UEFI password (out of NixOS scope but should be documented)
- Boot password for GRUB if physical console access is a risk

```nix
{
  # Disable USB storage kernel modules
  boot.blacklistedKernelModules = [ "usb-storage" "uas" ];

  # Disable udisks to prevent auto-mounting
  services.udisks2.enable = false;

  # Require LUKS passphrase at boot (physical presence required)
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/XXXX-XXXX";
    preLVM = true;
  };
}
```

---

## Requirement 10: Log and Monitor All Access to System Components and Cardholder Data

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 10.1.1 | Security policies for logging and monitoring defined | Organizational + host | Policy artifact; `audit-and-aide` module |
| 10.2.1 | Audit logs enabled and active | Host | auditd + journald |
| 10.2.1.1 | Audit logs capture all individual user access to CHD | Host | auditd rules for CHD paths |
| 10.2.1.2 | All actions by individuals with admin access logged | Host | auditd rules for root/wheel |
| 10.2.1.3 | Access to all audit logs logged | Host | auditd watch on /var/log |
| 10.2.1.4 | Invalid logical access attempts logged | Host | PAM faillock + SSH auth logs |
| 10.2.1.5 | Changes to identification/authentication credentials logged | Host | auditd watch on /etc/shadow, /etc/passwd |
| 10.2.1.6 | Audit logs capture stopping/pausing of audit logs | Host | auditd immutable mode |
| 10.2.1.7 | Creation/deletion of system-level objects logged | Host | auditd syscall rules |
| 10.2.2 | Audit log entries contain required fields | Host | auditd provides all required fields; see 10.2.x field mapping below |
| 10.3.1 | Audit log read access limited to those with need | Host | File permissions on /var/log/audit |
| 10.3.2 | Audit log files protected from modification | Host | auditd immutable flag; append-only |
| 10.3.3 | Audit log files promptly backed up to external system | Host | rsyslog RELP/TLS forwarding to central SIEM |
| 10.3.4 | File integrity monitoring on audit logs | Host | AIDE monitors audit log directory |
| 10.4.1 | Audit logs reviewed at least daily | Process | Automated log analysis |
| 10.4.1.1 | **[NEW v4.0, effective March 2025]** Automated mechanisms to perform audit log reviews | Host | Multi-rule anomaly detection; see implementation below |
| 10.4.2 | All other audit log events reviewed periodically | Process | Semi-annual review |
| 10.4.2.1 | **[NEW v4.0, effective March 2025]** Frequency of periodic log reviews defined in targeted risk analysis | Process | Risk analysis document |
| 10.4.3 | Exceptions and anomalies addressed | Process | Alerting pipeline |
| 10.5.1 | Audit log history retained for 12 months, 3 months immediately available | Host + process | Log retention configuration; see 10.5.1 clarification below |
| 10.6.1 | **[NEW v4.0, effective March 2025]** NTP synchronization | Host | See NTP section below |
| 10.6.2 | **[NEW v4.0, effective March 2025]** Systems receive time from designated time sources | Host | Chrony configuration |
| 10.6.3 | **[NEW v4.0, effective March 2025]** Time settings received from industry-accepted sources | Host | NTP pool or internal stratum |
| 10.7.1 | **[NEW v4.0, effective March 2025]** Failures of critical security controls detected and reported | Host | systemd watchdog on auditd |
| 10.7.2 | **[NEW v4.0, effective March 2025]** Failures of critical security controls detected and responded to promptly | Process + host | Alerting on auditd failure |

### Requirement 10.2.x -- Audit Log Field Enumeration

PCI DSS Requirement 10.2.2 mandates that audit log entries contain the following six fields. The table below maps each required field to its auditd implementation:

| PCI Required Field | Description | auditd Field | Example |
|--------------------|-------------|--------------|---------|
| User identification | Who performed the action | `uid`, `auid` (audit UID), `acct` | `auid=1000` (maps to `admin` user); `auid` persists the original login UID even after `su`/`sudo` |
| Type of event | What category of action occurred | `type` field (e.g., `USER_AUTH`, `SYSCALL`, `USER_CMD`, `EXECVE`) | `type=USER_AUTH` for authentication attempt |
| Date and time | When the action occurred | `msg=audit(EPOCH:SERIAL)` timestamp | `msg=audit(1713800000.123:456)` -- epoch seconds with millisecond precision |
| Success or failure | Whether the action succeeded | `res=` or `success=` field | `res=failed` for failed login; `success=yes` for successful syscall |
| Origination of event | Where the action originated from | `addr`, `hostname`, `terminal`, `tty` | `addr=192.168.1.100 terminal=ssh` for remote SSH session |
| Identity or name of affected data, system component, resource, or service | What was acted upon | `name`, `key`, `exe`, `comm`, `obj` | `name="/etc/shadow" exe="/usr/bin/passwd"` for a password change |

All six fields are captured natively by the Linux audit subsystem when configured with the rules in this document. No additional configuration is needed beyond enabling auditd and defining the watch/syscall rules. The `auid` (audit UID) field is particularly important: it preserves the original login identity even when a user escalates privileges via `sudo`, ensuring traceability back to the individual (Req 10.2.1.2).

To verify field capture, inspect a sample audit event:

```bash
ausearch -m USER_AUTH -ts recent --format text
```

### Requirement 10.3.3 -- Centralized Log Forwarding

PCI DSS Requirement 10.3.3 requires that audit log files are promptly backed up to a centralized log server or media that is difficult to alter. Local-only logs on a single server create a single point of failure for audit evidence: if the host is compromised, the attacker can tamper with or destroy local logs before they are reviewed.

```nix
{
  # Centralized log forwarding via rsyslog with RELP/TLS
  # RELP (Reliable Event Logging Protocol) provides guaranteed delivery,
  # unlike plain UDP syslog which can silently drop messages.
  services.rsyslogd = {
    enable = true;
    extraConfig = ''
      module(load="omrelp")
      # Forward all auth and audit logs to central SIEM
      auth,authpriv.*   action(type="omrelp" target="siem.internal" port="2514"
                               tls="on" tls.caCert="/var/lib/secrets/syslog-ca.pem")
      local6.*          action(type="omrelp" target="siem.internal" port="2514"
                               tls="on" tls.caCert="/var/lib/secrets/syslog-ca.pem")
    '';
  };
}
```

The `siem.internal` target and port `2514` must be configured per deployment. The TLS CA certificate at `/var/lib/secrets/syslog-ca.pem` should be managed via sops-nix (see Requirement 3). The `local6` facility is used by custom PCI services (nix-store-verify, ClamAV alerting) to ensure their alerts reach the SIEM.

This satisfies Requirement 10.3.3 by ensuring that logs are forwarded in near-real-time to an external system where they are protected from modification by a host-level attacker.

### Requirement 10.5.1 -- Log Retention and Availability Clarification

PCI DSS 10.5.1 requires that audit log history is retained for at least 12 months, with at least the most recent 3 months "immediately available for analysis." "Immediately available" means the logs must be searchable and queryable on demand -- not merely stored on disk in compressed archives that require manual extraction.

For a single-server deployment, this requirement is satisfied by:

- **Recent 3 months**: Logs accessible via `journalctl` (systemd journal) and `ausearch`/`aureport` (audit logs) provide immediate search and query capability. These tools support time-range filtering, field-based search, and output formatting.
- **Older 3-12 months**: Rotated and compressed log files on local disk, queryable via `zgrep` or by decompressing and searching.

For production CDE deployments, a dedicated SIEM or log aggregation platform (Elasticsearch/OpenSearch, Splunk, Grafana Loki) is strongly recommended to provide:

- Full-text search across the entire 12-month retention window
- Correlation across multiple hosts
- Dashboard and alerting capabilities
- Tamper-evident storage independent of the source host

The centralized log forwarding configured under Requirement 10.3.3 ensures that a SIEM receives all relevant logs in real-time, satisfying both the backup and the availability requirements.

### NTP Synchronization

PCI DSS v4.0 requirements 10.6.1 through 10.6.3 mandate accurate time synchronization for audit log correlation. This was previously implicit but is now explicit and enforceable as of March 2025.

```nix
{
  # Chrony NTP client — PCI DSS 10.6.x
  services.chrony = {
    enable = true;
    servers = [
      "0.pool.ntp.org"
      "1.pool.ntp.org"
      "2.pool.ntp.org"
      "3.pool.ntp.org"
    ];
    extraConfig = ''
      # Restrict NTP modifications
      cmdallow 127.0.0.1
      cmddeny all

      # Log significant clock adjustments
      logchange 0.5

      # Maximum allowed drift before alerting
      maxchange 1000 1 2

      # Use RTC as backup
      rtcsync
    '';
  };

  # Disable other time services to avoid conflicts
  services.timesyncd.enable = false;
}
```

### Audit Configuration

```nix
{
  security.auditd.enable = true;
  security.audit = {
    enable = true;
    rules = [
      # PCI 10.2.1.2 — Log all commands by admin users
      "-a always,exit -F arch=b64 -F euid=0 -S execve -k admin_cmds"

      # PCI 10.2.1.3 — Log access to audit trail
      "-w /var/log/audit/ -p rwa -k audit_trail_access"

      # PCI 10.2.1.5 — Log credential changes
      "-w /etc/passwd -p wa -k identity_changes"
      "-w /etc/shadow -p wa -k identity_changes"
      "-w /etc/group -p wa -k identity_changes"
      "-w /etc/gshadow -p wa -k identity_changes"

      # PCI 10.2.1.6 — Log audit subsystem changes
      "-w /etc/audit/ -p wa -k audit_config"
      "-w /etc/audit/auditd.conf -p wa -k audit_config"

      # PCI 10.2.1.7 — Log file deletions and permission changes
      "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -k file_deletion"
      "-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -k permission_changes"

      # PCI 10.2.1.1 — Log access to CHD storage paths (customize per deployment)
      # "-w /var/lib/chd-data/ -p rwxa -k chd_access"

      # Lock audit config — PCI 10.2.1.6 (no changes without reboot)
      "-e 2"
    ];
  };

  # Audit log retention — PCI 10.5.1 (12 months, 3 months online)
  services.logrotate.settings."/var/log/audit/audit.log" = {
    frequency = "monthly";
    rotate = 12;
    compress = true;
    delaycompress = true;
    missingok = true;
    notifempty = true;
    postrotate = "systemctl reload auditd";
  };

  # Automated log review — PCI 10.4.1.1 (effective March 2025)
  #
  # NOTE: This is a MINIMUM implementation providing basic anomaly detection.
  # Production CDE deployments should supplement this with SIEM-based correlation
  # (e.g., Splunk, Elastic SIEM, Wazuh) that can perform cross-host correlation,
  # behavioral baselining, and ML-based anomaly detection. This script provides
  # local detection as a baseline; the centralized SIEM (see 10.3.3) should be
  # the primary detection and alerting platform.
  systemd.services.pci-log-review = {
    description = "Automated PCI audit log review — multi-rule anomaly detection";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "log-review" ''
        ALERT_FILE="/var/log/pci-alerts.log"
        ALERT_COUNT=0
        TIMESTAMP=$(date -Iseconds)

        alert() {
          local severity="$1"
          local message="$2"
          echo "$TIMESTAMP [$severity] $message" >> "$ALERT_FILE"
          echo "$message" | systemd-cat -p "$severity"
          # Forward to SIEM via syslog
          logger -p "local6.$severity" -t pci-log-review "$message"
          ALERT_COUNT=$((ALERT_COUNT + 1))
        }

        # --- Baseline thresholds ---
        # These MUST be tuned per deployment based on observed normal activity.
        # Review and adjust quarterly as part of the 10.4.2.1 risk analysis.
        BASELINE_AUTH_FAILURES=15      # Normal daily auth failure count
        BASELINE_MULTIPLIER=3          # Alert at 3x baseline
        AUTH_FAILURE_THRESHOLD=$((BASELINE_AUTH_FAILURES * BASELINE_MULTIPLIER))
        BUSINESS_HOURS_START=7         # 07:00 local time
        BUSINESS_HOURS_END=20          # 20:00 local time

        # --- Rule 1: Authentication failures exceeding 3x baseline ---
        AUTH_FAILURES=$(ausearch -m USER_AUTH --success no -ts today 2>/dev/null | grep -c "^type" || true)
        if [ "$AUTH_FAILURES" -gt "$AUTH_FAILURE_THRESHOLD" ]; then
          alert "crit" "AUTH_ANOMALY: $AUTH_FAILURES authentication failures today (threshold: $AUTH_FAILURE_THRESHOLD, baseline: $BASELINE_AUTH_FAILURES)"
        fi

        # --- Rule 2: Privilege escalation attempts ---
        # Detect su/sudo to root by non-admin users, and any setuid/setgid calls
        PRIV_ESC=$(ausearch -m USER_CMD -ts today 2>/dev/null | grep -c "^type" || true)
        SETUID_CALLS=$(ausearch -m SYSCALL -k admin_cmds -ts today 2>/dev/null | grep -v "auid=1000" | grep -c "^type" || true)
        if [ "$PRIV_ESC" -gt 0 ] || [ "$SETUID_CALLS" -gt 5 ]; then
          alert "crit" "PRIV_ESCALATION: $PRIV_ESC sudo/su events, $SETUID_CALLS root exec events from non-primary-admin today"
        fi

        # --- Rule 3: After-hours administrative access ---
        CURRENT_HOUR=$(date +%H)
        if [ "$CURRENT_HOUR" -lt "$BUSINESS_HOURS_START" ] || [ "$CURRENT_HOUR" -ge "$BUSINESS_HOURS_END" ]; then
          AFTER_HOURS_ADMIN=$(ausearch -m USER_LOGIN --success yes -ts today 2>/dev/null | grep -c "^type" || true)
          if [ "$AFTER_HOURS_ADMIN" -gt 0 ]; then
            alert "warning" "AFTER_HOURS_ACCESS: $AFTER_HOURS_ADMIN successful admin login(s) outside business hours ($BUSINESS_HOURS_START:00-$BUSINESS_HOURS_END:00)"
          fi
        fi

        # --- Rule 4: New service/system account creation ---
        NEW_ACCOUNTS=$(ausearch -k identity_changes -ts today 2>/dev/null | grep "useradd\|newusers\|adduser" | grep -c "^type" || true)
        if [ "$NEW_ACCOUNTS" -gt 0 ]; then
          alert "warning" "NEW_ACCOUNT: $NEW_ACCOUNTS new account creation event(s) detected today — verify against change control"
        fi

        # --- Rule 5: Audit subsystem modification attempts ---
        AUDIT_MODS=$(ausearch -k audit_config -ts today 2>/dev/null | grep -c "^type" || true)
        if [ "$AUDIT_MODS" -gt 0 ]; then
          alert "crit" "AUDIT_TAMPER: $AUDIT_MODS audit configuration modification attempt(s) detected — investigate immediately"
        fi

        # --- Rule 6: Critical file integrity changes ---
        CRED_CHANGES=$(ausearch -k identity_changes -ts today 2>/dev/null | grep -c "^type" || true)
        if [ "$CRED_CHANGES" -gt 0 ]; then
          alert "warning" "CREDENTIAL_CHANGE: $CRED_CHANGES identity/credential file modification(s) today — verify against change control"
        fi

        # --- Summary ---
        if [ "$ALERT_COUNT" -eq 0 ]; then
          echo "$TIMESTAMP [info] Daily log review complete — no anomalies detected" >> "$ALERT_FILE"
          echo "Daily PCI log review complete — no anomalies" | systemd-cat -p info
        else
          alert "warning" "REVIEW_SUMMARY: $ALERT_COUNT alert(s) generated — manual review required"
        fi
      '';
    };
  };

  systemd.timers.pci-log-review = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
    timerConfig.Persistent = true;
  };
}
```

---

## Requirement 11: Test Security of Systems and Networks Regularly

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 11.1.1 | Security policies for testing defined | Organizational | Policy artifact |
| 11.2.1 | Authorized and unauthorized wireless access points managed | N/A | No wireless on server |
| 11.3.1 | Internal vulnerability scans performed at least quarterly | Host | See vulnerability scanning section below |
| 11.3.1.1 | All other non-high/critical vulnerabilities managed | Process | CVSS-based remediation timelines |
| 11.3.1.2 | Internal scans performed after significant changes | Process + host | Post-rebuild scan |
| 11.3.1.3 | **[NEW v4.0, effective March 2025]** Internal scans performed via authenticated scanning | Host | Authenticated local scan; see note below |
| 11.3.2 | External vulnerability scans performed quarterly by ASV | Process | ASV engagement (out of scope for LAN-only unless in CDE) |
| 11.4.1 | Penetration testing performed at least annually | Process | External engagement |
| 11.4.3 | Internal penetration testing performed | Process | Annual pen test |
| 11.4.5 | Network segmentation controls tested at least every six months | Host | Automated segmentation test (see above) |
| 11.4.7 | **[NEW v4.0, effective March 2025]** Multi-tenant service providers test segmentation at least every six months | N/A | Not a multi-tenant provider |
| 11.5.1 | Intrusion-detection/prevention on network | Host | Not typically host-level; network IDS/IPS |
| 11.5.1.1 | **[NEW v4.0, effective March 2025]** IDS/IPS techniques detect, alert, and address covert malware communication | Network | Network-level control |
| 11.5.2 | Change-detection mechanism (FIM) deployed | Host | See FIM section below |

### Vulnerability Scanning

PCI DSS Requirement 11.3.1 requires quarterly internal vulnerability scans. This involves multiple scanning layers, each serving a distinct purpose:

**Layer 1: Package CVE Audit (vulnix)**

`vulnix` checks all installed Nix packages against the National Vulnerability Database (NVD). This is a package-level CVE audit, not a network vulnerability scanner. It identifies known vulnerabilities in the software bill of materials.

```bash
# Run package vulnerability audit
nix run nixpkgs#vulnix -- --system 2>&1 | tee /var/log/pci-vulnix.log
```

**Layer 2: Host Security Hardening Assessment (Lynis)**

`lynis` performs a host-level security audit covering CIS benchmarks, kernel hardening, service configuration, file permissions, and authentication settings. This is a host hardening assessment, not a network vulnerability scanner.

```bash
# Run host security audit
lynis audit system --no-colors 2>&1 | tee /var/log/pci-lynis.log
```

**Layer 3: Network Vulnerability Scanning (Required for 11.3.1 Compliance)**

Neither vulnix nor Lynis satisfies the PCI DSS 11.3.1 requirement for network-layer vulnerability scanning. A QSA expects authenticated network scanning that discovers vulnerabilities from the network perspective (open ports, service fingerprinting, protocol-level flaws, misconfigurations). One of the following must be deployed or engaged:

- **OpenVAS/Greenbone Community Edition**: Open-source network vulnerability scanner. Can be deployed on a separate host to scan this server. Provides authenticated and unauthenticated scanning.
- **Nessus Professional**: Commercial vulnerability scanner widely accepted by QSAs.
- **Qualys**: Cloud-based scanner commonly used for PCI ASV and internal scans.

For a LAN-only deployment, the recommended approach is to deploy OpenVAS on a separate management host and configure it to perform quarterly authenticated scans of this server.

**Requirement 11.3.1.3 -- Authenticated Scanning (Effective March 2025)**

PCI DSS v4.0 Requirement 11.3.1.3 (effective March 2025) requires that internal vulnerability scans be performed via authenticated scanning. This means the scanner must log into the target system (via SSH, local agent, or credential-based scan) to assess vulnerabilities that are not visible from an unauthenticated network perspective. For this NixOS server:

- Configure the network vulnerability scanner (OpenVAS/Nessus/Qualys) with SSH credentials (key-based) for authenticated local assessment
- The vulnix package audit inherently runs authenticated (it inspects the local Nix store)
- The Lynis host audit inherently runs authenticated (it runs locally with root access)

**CVSS-Based Remediation Timelines**

All discovered vulnerabilities must be remediated according to CVSS severity:

| CVSS Score | Severity | Remediation Timeline | Process |
|------------|----------|----------------------|---------|
| 9.0 - 10.0 | Critical | 30 calendar days | Immediate triage; emergency `nixos-rebuild` with patched inputs |
| 7.0 - 8.9 | High | 90 calendar days | Prioritized in next maintenance window; `nix flake update` + rebuild |
| 4.0 - 6.9 | Medium | 180 calendar days | Scheduled for next quarterly update cycle |
| 0.1 - 3.9 | Low | Next scheduled update | Addressed in routine `nix flake update` cycle |

Vulnerabilities that cannot be remediated within the timeline must have a documented compensating control and risk acceptance signed by the information security officer.

```nix
{
  environment.systemPackages = with pkgs; [
    lynis       # Host security hardening assessment
    nmap        # Network scanning for segmentation validation
  ];

  # Quarterly internal vulnerability scan — PCI 11.3.1
  systemd.services.pci-vuln-scan = {
    description = "PCI DSS quarterly internal vulnerability scan (package audit + host hardening)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "vuln-scan" ''
        echo "=== Layer 1: Nix Package CVE Audit (vulnix) ==="
        echo "Purpose: Identifies known CVEs in installed Nix packages via NVD lookup"
        ${pkgs.vulnix}/bin/vulnix --system 2>&1 | tee /var/log/pci-vulnix.log

        echo ""
        echo "=== Layer 2: Host Security Hardening Assessment (Lynis) ==="
        echo "Purpose: CIS benchmark compliance, kernel hardening, service configuration audit"
        ${pkgs.lynis}/bin/lynis audit system --no-colors 2>&1 | tee /var/log/pci-lynis.log

        echo ""
        echo "=== Layer 3: Local Port Verification ==="
        echo "Purpose: Verify only expected ports are listening (does NOT replace network vuln scanner)"
        ${pkgs.nmap}/bin/nmap -sT -p- 127.0.0.1 2>&1 | tee /var/log/pci-portscan.log

        echo ""
        echo "=== IMPORTANT ==="
        echo "This scan covers package CVEs and host hardening only."
        echo "PCI DSS 11.3.1 also requires a network vulnerability scanner (OpenVAS, Nessus, or Qualys)."
        echo "Ensure the quarterly network vulnerability scan is scheduled separately."
      '';
    };
  };

  systemd.timers.pci-vuln-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "quarterly";
      Persistent = true;
    };
  };
}
```

### File Integrity Monitoring

PCI DSS Requirement 11.5.2 requires a change-detection mechanism (typically FIM) on critical system files, configuration files, and content files. This goes beyond basic AIDE in several specific ways:

1. **Scope**: FIM must cover critical system files, configuration files, AND content files. For a CDE system, this includes any files that could contain or protect CHD.
2. **Alerting**: FIM must alert personnel on unauthorized modification (not just detect on next scan).
3. **Frequency**: Critical file comparisons must occur at least weekly (or continuously with alerting).
4. **Baseline**: A known-good baseline must be established and maintained.

```nix
{
  # AIDE for file integrity monitoring — PCI 11.5.2
  environment.systemPackages = [ pkgs.aide ];

  # AIDE configuration covering PCI-required paths
  # NOTE: On NixOS, /usr/bin and /usr/sbin are largely empty because all
  # binaries live in /nix/store. The paths below are NixOS-specific.
  environment.etc."aide.conf".text = ''
    # PCI DSS 11.5.2 — Critical system files (NixOS-specific)
    /etc p+i+n+u+g+s+b+m+c+sha256
    /boot p+i+n+u+g+s+b+m+c+sha256

    # NixOS-specific: active system closure symlink
    # Changes here indicate a nixos-rebuild switch occurred
    /run/current-system p+i+n+u+g+s+b+m+c+sha256

    # NixOS-specific: generated static configuration
    /etc/static p+i+n+u+g+s+b+m+c+sha256

    # Authentication and credential files
    /etc/shadow p+i+n+u+g+s+b+m+c+sha256
    /etc/passwd p+i+n+u+g+s+b+m+c+sha256
    /etc/ssh p+i+n+u+g+s+b+m+c+sha256

    # PCI DSS — Audit configuration and logs
    /var/log/audit p+i+n+u+g+s+b+m+c+sha256
    /etc/audit p+i+n+u+g+s+b+m+c+sha256

    # PCI DSS — Authentication configuration
    /etc/pam.d p+i+n+u+g+s+b+m+c+sha256

    # PCI DSS — Network security controls
    /etc/nftables.conf p+i+n+u+g+s+b+m+c+sha256

    # Service configuration
    /etc/systemd p+i+n+u+g+s+b+m+c+sha256

    # Service state directories (detect unauthorized data writes)
    /var/lib/ollama p+i+n+u+g+s+b+m+c+sha256
    /var/lib/agent-runner p+i+n+u+g+s+b+m+c+sha256

    # Exclusions
    !/var/log/audit/audit.log
    !/var/log/journal
    !/proc
    !/sys
    !/run
    !/nix/store
    !/var/lib/ollama/models
  '';

  # Initialize AIDE database
  systemd.services.aide-init = {
    description = "AIDE database initialization";
    wantedBy = [ ];  # Run manually: systemctl start aide-init
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.aide}/bin/aide --config=/etc/aide.conf --init";
      ExecStartPost = "cp /var/lib/aide/aide.db.new /var/lib/aide/aide.db";
    };
  };

  # Periodic AIDE check with alerting — PCI 11.5.2
  systemd.services.aide-check = {
    description = "AIDE integrity check for PCI DSS 11.5.2";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "aide-check-alert" ''
        RESULT=$(${pkgs.aide}/bin/aide --config=/etc/aide.conf --check 2>&1)
        EXIT_CODE=$?

        if [ $EXIT_CODE -ne 0 ]; then
          echo "CRITICAL: AIDE detected file integrity changes" | systemd-cat -p crit
          echo "$RESULT" | systemd-cat -p crit
          # Forward alert to SIEM
          logger -p local6.crit -t aide-check "CRITICAL: File integrity changes detected"
          # Send alert (configure per environment)
          # curl -X POST https://monitoring.internal/webhook -d "$RESULT"
        else
          echo "AIDE check passed — no changes detected" | systemd-cat -p info
        fi
      '';
    };
  };

  systemd.timers.aide-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";    # At minimum weekly per PCI; daily recommended
      Persistent = true;
    };
  };

  # NixOS-specific integrity verification
  # The Nix store provides content-addressed integrity for all managed files.
  # This is covered by the nix-store-verify timer in the Requirement 5 section.
}
```

The `/nix/store` exclusion in AIDE is deliberate. The Nix store has its own integrity mechanism (content-addressable hashing) that is stronger than AIDE's file-attribute monitoring. The separate `nix-store-verify` service (see Requirement 5) validates this integrity daily with alerting on failure.

Note on `/usr/bin` and `/usr/sbin`: On NixOS, these directories are largely empty because all binaries are managed in `/nix/store` and exposed via `PATH` through Nix profiles. Monitoring them provides no security value. Instead, monitor `/run/current-system` (the symlink to the active system closure) and `/etc/static` (NixOS-generated configuration files), which are the NixOS equivalents of traditional system binary and configuration paths.

---

## Requirement 12: Support Information Security with Organizational Policies and Programs

### In-Scope Sub-Requirements

| Sub-Req | Description | Host-Level Applicability | Implementation |
|---------|-------------|--------------------------|----------------|
| 12.1.1 | Overall information security policy established | Organizational | Policy document |
| 12.1.2 | Information security policy reviewed annually | Organizational | Annual review process |
| 12.1.3 | Security policy defines roles and responsibilities | Organizational | Out of scope for host config |
| 12.2.1 | Acceptable use policies for end-user technologies | Organizational | Policy document |
| 12.3.1 | **[NEW v4.0, effective March 2025]** Targeted risk analysis for each requirement with flexibility | Process | Risk analysis documents |
| 12.3.2 | **[NEW v4.0, effective March 2025]** Targeted risk analysis performed for customized approach | Process | If using customized approach |
| 12.3.3 | Cryptographic cipher suites and protocols documented | Host + process | TLS config documented in Nix; SSH cipher config |
| 12.3.4 | Hardware and software technologies reviewed annually | Process | NixOS channel/package review |
| 12.4.1 | Service provider responsibility matrix (for service providers) | N/A | Not a service provider |
| 12.5.1 | Inventory of system components in scope | Host | `nix-store --query --requisites /run/current-system` |
| 12.5.2 | PCI DSS scope confirmed at least annually | Process | Annual scope review |
| 12.5.2.1 | **[NEW v4.0, effective March 2025]** Scope documented and confirmed by entity at least every six months | Process | Semi-annual scope validation |
| 12.5.3 | **[NEW v4.0, effective March 2025]** Significant organizational changes trigger scope review | Process | Change management |
| 12.6.1 | Security awareness program implemented | Organizational | Training program |
| 12.6.2 | Security awareness program reviewed annually | Organizational | Annual review |
| 12.6.3 | Personnel receive security awareness training annually | Organizational | Training records |
| 12.6.3.1 | **[NEW v4.0, effective March 2025]** Security awareness training includes awareness of threats and vulnerabilities | Organizational | Training content |
| 12.6.3.2 | **[NEW v4.0, effective March 2025]** Security awareness training includes acceptable use of end-user technologies | Organizational | Training content |
| 12.8.1-12.8.5 | Third-party service provider management | Process | TPSP agreements |
| 12.9.1-12.9.2 | TPSPs acknowledge responsibility (for TPSPs) | N/A | Not a TPSP |
| 12.10.1 | Incident response plan exists | Organizational | IR plan document |
| 12.10.2 | Incident response plan reviewed and tested annually | Organizational | Annual IR drill |
| 12.10.4.1 | **[NEW v4.0, effective March 2025]** Frequency of periodic IR training defined in targeted risk analysis | Process | Risk analysis |
| 12.10.5 | Incident response plan includes response to alerts from security monitoring | Host + process | Alerting integration |
| 12.10.7 | **[NEW v4.0, effective March 2025]** Incident response procedures in place for detection of stored PAN anywhere it is not expected | Process + host | PAN scanning |

### Host-Level Contributions

While Requirement 12 is primarily organizational, the NixOS flake provides several artifacts that support compliance:

```nix
{
  # System inventory generation (PCI 12.5.1)
  # nix-store --query --requisites /run/current-system | wc -l
  # Produces exact package count and full dependency tree

  # Cryptographic inventory (PCI 12.3.3)
  # Documented in Nix config:
  #   - SSH: chacha20-poly1305, aes256-gcm (see Req 8 config)
  #   - TLS: TLSv1.2, TLSv1.3, ECDHE suites (see Req 4 config)
  #   - Disk: LUKS2 with AES-256-XTS (boot config)

  # PAN scanning for unexpected CHD storage (PCI 12.10.7, effective March 2025)
  systemd.services.pci-pan-scan = {
    description = "Scan for unexpected PAN storage";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "pan-scan" ''
        # Simple regex scan for potential card numbers in data directories
        # This is a basic check — production deployments should use a validated PAN scanner
        find /var/lib /tmp /home -type f -name "*.log" -o -name "*.txt" -o -name "*.csv" -o -name "*.json" 2>/dev/null | \
        xargs grep -lP '\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13}|6(?:011|5[0-9]{2})[0-9]{12})\b' 2>/dev/null | \
        while read -r file; do
          echo "ALERT: Potential PAN found in $file" | systemd-cat -p crit
        done
      '';
    };
  };

  systemd.timers.pci-pan-scan = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
```

---

## Summary of PCI DSS v4.0 New Requirements (Effective March 2025)

The following requirements became mandatory on March 31, 2025 and are addressed in this document:

| Requirement | Sub-Req | Description | Host Coverage |
|-------------|---------|-------------|---------------|
| 1 | 1.4.4 | Restrict inbound to authorized sources | Firewall rules |
| 2 | 2.3.1, 2.3.2 | Wireless security | N/A (no wireless) |
| 3 | 3.7.1 | Formal key management documentation | Process |
| 5 | 5.2.3.1 | Risk analysis for systems without AV | NixOS immutability risk analysis |
| 5 | 5.3.2.1 | Periodic scan frequency risk analysis | Process |
| 5 | 5.4.1 | Anti-phishing mechanisms | N/A (server) |
| 6 | 6.2.3.1 | Manual/automated code review | Nix config review |
| 7 | 7.2.5.1 | Least privilege for application/system accounts | systemd hardening |
| 8 | 8.3.10, 8.3.10.1 | Password length requirements | N/A (key-only auth) |
| 8 | 8.4.3 | MFA for all non-console admin access | SSH MFA config |
| 8 | 8.6.3 | Application/system account password management | sops-nix |
| 10 | 10.4.1.1 | Automated audit log reviews | Multi-rule anomaly detection |
| 10 | 10.6.1-10.6.3 | NTP synchronization | Chrony |
| 10 | 10.7.1, 10.7.2 | Critical security control failure detection | systemd watchdog |
| 11 | 11.3.1.3 | Authenticated internal scanning | Local authenticated scan + network scanner |
| 11 | 11.5.1.1 | Covert malware communication detection | Network-level |
| 12 | 12.3.1, 12.3.2 | Targeted risk analysis | Process |
| 12 | 12.5.2.1 | Semi-annual scope confirmation | Process |
| 12 | 12.5.3 | Scope review on significant changes | Process |
| 12 | 12.6.3.1, 12.6.3.2 | Enhanced security awareness training | Organizational |
| 12 | 12.10.4.1 | IR training frequency risk analysis | Process |
| 12 | 12.10.7 | Detect unexpected PAN storage | PAN scanning automation |

---

## Control Coverage Matrix

| PCI Requirement | Host Controls (NixOS) | Process Controls | Organizational Controls | Coverage Level |
|-----------------|----------------------|------------------|------------------------|----------------|
| 1 - Network Security | Firewall, nftables, interface binding, network diagram data | Change control via Git | Network security policy | Strong |
| 2 - Secure Configuration | Minimal profile, immutable store, hardened services | Configuration standards doc | Security standards policy | Strong |
| 3 - Stored Data Protection | LUKS encryption, sops-nix, encrypted swap | Retention/disposal procedures | Data protection policy | Moderate (depends on CHD presence) |
| 4 - Transmission Encryption | TLS 1.2/1.3, SSH hardened ciphers, certificate inventory | Certificate management | Encryption policy | Strong |
| 5 - Anti-Malware | ClamAV on-access + periodic scan, Nix store verify (daily), immutable store, USB disabled | Risk analysis for NixOS model | AV policy | Strong |
| 6 - Secure Development | vulnix (package CVE), Lynis (host hardening), flake.lock, declarative config | Code review, change control, network vuln scanner | SDLC policy | Moderate |
| 7 - Access Control | Declarative users, systemd isolation, no mutable users | Access reviews | Access control policy | Strong |
| 8 - Authentication | SSH key+TOTP MFA, faillock, session timeout, TOTP seed protection | Account lifecycle mgmt | Authentication policy | Strong |
| 9 - Physical Access | LUKS, USB disabled, blacklisted modules | Facility controls | Physical security policy | Weak (mostly organizational) |
| 10 - Logging/Monitoring | auditd, AIDE, chrony, multi-rule log review, centralized syslog forwarding | Log review procedures | Logging policy | Strong |
| 11 - Security Testing | vulnix, Lynis, AIDE, segmentation tests (full-range TCP+UDP), Nix store verify | Pen testing, ASV scans, network vuln scanner | Testing policy | Moderate |
| 12 - Policies/Programs | System inventory, PAN scanning, crypto inventory | IR plan, scope reviews, training | All governance policies | Weak (mostly organizational) |

---

## Assessor Guidance

When presenting this system to a PCI QSA, emphasize the following differentiators of the NixOS platform:

1. **Immutable infrastructure**: The Nix store is read-only and content-addressed. Binaries cannot be modified at runtime. This is a stronger integrity guarantee than traditional FIM on mutable filesystems. Daily `nix store verify --all` with alerting provides cryptographic proof of store integrity.

2. **Declarative-only configuration**: `users.mutableUsers = false` combined with the flake model means the system state is entirely defined in version-controlled code. There are no undocumented manual changes.

3. **Atomic rollback**: `nixos-rebuild switch --rollback` returns the entire system to a previous known-good state. This supports incident response (Req 12.10) and change management (Req 6.5).

4. **Complete bill of materials**: `nix-store --query --requisites /run/current-system` provides a complete, cryptographically verifiable software inventory at any point in time. This exceeds the software inventory requirements of Req 6.3.2.

5. **Reproducible builds**: A QSA can verify that the declared configuration produces the expected system state by rebuilding from the flake on a test host.

For the customized approach (new in PCI DSS v4.0), these properties can be used to demonstrate that the security objective of each requirement is met through NixOS-native mechanisms, even where the specific prescribed testing procedure assumes a traditional mutable Linux distribution.

---

## Risks and Gaps

1. **Requirement 9 (Physical Access)**: Host-level controls provide minimal coverage. Physical security controls for the server location must be documented and implemented separately.

2. **Requirement 5 (Anti-Malware)**: QSAs may not accept the NixOS immutability argument without a formal targeted risk analysis (5.2.3.1). ClamAV on-access scanning for writable paths plus daily Nix store verification provides a strong defense-in-depth posture, but the risk analysis document is still required.

3. **External vulnerability scanning (11.3.2)**: If this server is in the CDE, quarterly ASV scans are required. For a LAN-only server, the ASV must be able to reach the host, which may require temporary network configuration or an internal scan proxy.

4. **Network vulnerability scanning (11.3.1)**: The host-level tools (vulnix, Lynis) cover package CVEs and host hardening but do not satisfy the network-layer vulnerability scanning requirement. A dedicated network vulnerability scanner (OpenVAS, Nessus, or Qualys) must be deployed or engaged for quarterly scans. This is a gap that must be closed before QSA assessment.

5. **Log forwarding**: Centralized log forwarding via rsyslog/RELP/TLS is configured (see Requirement 10.3.3 section). The SIEM target (`siem.internal:2514`) and CA certificate must be configured per deployment. Without a functioning SIEM receiver, logs remain local-only, which fails 10.3.3.

6. **Incident response**: The NixOS configuration provides detection and evidence, but the incident response plan, escalation procedures, and communication protocols are organizational deliverables that must be created separately.

7. **Penetration testing (11.4.x)**: Must be performed by qualified personnel and cannot be fully automated through NixOS configuration. Annual engagement with a qualified pen tester is required.

8. **MFA token management**: The Google Authenticator TOTP seed must be provisioned per-user and the backup/recovery process documented. Lost token recovery is an operational concern. The TOTP seed file is protected via systemd-tmpfiles (mode 0400), but provisioning and recovery procedures are organizational deliverables.

9. **GPU VRAM CHD residue**: If the server processes CHD through LLM inference, VRAM and KV cache may contain CHD fragments. See the scoping section for mitigation recommendations. This is a novel scoping consideration that QSAs may not have established precedent for; document the analysis proactively.
