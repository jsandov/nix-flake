{ ... }:
{
  # lan-only-network — default-deny firewall, per-UID egress, DNS/NTP
  # restrictions. nftables only (NixOS 24.11 default) — never iptables
  # extraCommands.
  #
  # Control families: NIST AC/SC/CA; HIPAA Transmission Security;
  # PCI Req 1/4; OWASP tool-misuse mitigation.
  #
  # Implementation lives in INFRA-01, INFRA-02 in
  # todos/02-infrastructure-hardening.md.
}
