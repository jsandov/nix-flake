{ lib, ... }:
{
  # audit-and-aide — aggregator module.
  #
  # Split into focused submodules so each concern can evolve
  # independently:
  #   - auditd.nix   : kernel audit rules + persistent journal (INFRA-04)
  #   - evidence.nix : shared compliance evidence framework (ARCH-10)
  #
  # AIDE file integrity (INFRA-09) will land as a third submodule when
  # that TODO is implemented; it will consume config.canonical.aidePaths
  # for path selection.
  #
  # Control families: NIST AU-2 / AU-3 / AU-6 / AU-12 / SI-4;
  # HIPAA §164.312(b) Audit Controls; PCI 10.2 / 10.3 / 10.7;
  # HITRUST 06.e; STIG primary audit baseline.

  imports = [
    ./auditd.nix
    ./evidence.nix
  ];

  # Default-enable the evidence framework whenever audit-and-aide is
  # imported. mkDefault (not mkForce) so an operator can still disable
  # it explicitly at the host level for a test deployment.
  services.complianceEvidence.enable = lib.mkDefault true;
}
