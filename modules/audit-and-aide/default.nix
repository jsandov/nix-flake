{ ... }:
{
  # audit-and-aide — auditd kernel events + journald persistence, AIDE
  # file integrity with hourly checks, drift alerting, evidence generation.
  #
  # Control families: NIST AU/CM/SI/IR; HIPAA Audit Controls/Integrity;
  # PCI Req 10/11/12.
  #
  # Audit rules must use NixOS paths (/run/current-system/sw/bin,
  # /run/wrappers/bin) — never /usr/bin or /sbin. See INFRA-04, INFRA-09,
  # AI-19 in todos/.
}
