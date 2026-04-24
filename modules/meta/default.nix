{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  # meta — project-level qualitative metadata about the deployment.
  #
  # Distinct from canonical/ which holds cross-framework-resolved
  # quantitative values (Appendix A). Meta holds the *shape* of the
  # system: who the adversaries are, how data is classified, whether the
  # host is single- or multi-tenant. Downstream modules read from
  # `config.system.compliance.*` to gate behaviour — e.g. an AI service
  # can refuse to handle a `Restricted` collection unless encryption and
  # audit modules are enabled.
  #
  # See todos/01-architecture-and-cross-cutting.md ARCH-08 and
  # compliant-nix-config-vault/wiki/architecture/threat-model.md for the
  # narrative that these values codify.

  options.system.compliance = {

    threatModel = mkOption {
      description = "Codified threat model. The adversary types this system is designed to resist, the crown-jewel data, and explicit out-of-scope attacks. Referenced by downstream modules that need to know whether a given control is worth enabling.";
      type = types.submodule {
        options = {
          adversaries = mkOption {
            type = types.listOf (types.enum [
              "insider-unprivileged"
              "insider-privileged"
              "external-lan-unauthorised"
              "supply-chain-compromise"
              "malicious-model-upstream"
              "prompt-injection-via-user-input"
            ]);
            description = "Adversary types in scope for defensive controls.";
          };
          crownJewels = mkOption {
            type = types.listOf types.str;
            description = "Data classes whose confidentiality, integrity, or availability the system must protect. Free-form because framework-specific labels vary.";
          };
          outOfScope = mkOption {
            type = types.listOf (types.enum [
              "physical-access"
              "nation-state-actor"
              "rubber-hose-cryptanalysis"
              "hypervisor-escape"
              "gpu-firmware-compromise"
            ]);
            description = "Attacks explicitly accepted as out-of-scope. Documenting these prevents scope creep and sets audit expectations.";
          };
        };
      };
      default = {
        adversaries = [
          "insider-unprivileged"
          "external-lan-unauthorised"
          "supply-chain-compromise"
          "malicious-model-upstream"
          "prompt-injection-via-user-input"
        ];
        crownJewels = [
          "ePHI (HIPAA)"
          "PCI cardholder data if CHD in scope"
          "Model weights and fine-tuning deltas"
          "API tokens and session credentials"
          "LUKS passphrases and age private keys"
          "AI decision logs (EU AI Act Article 12)"
        ];
        outOfScope = [
          "physical-access"
          "nation-state-actor"
          "rubber-hose-cryptanalysis"
        ];
      };
    };

    dataClassification = mkOption {
      description = "Four-tier data classification scheme. Each tier carries a baseline handling requirement; downstream modules (agent-sandbox, ai-services) can gate on the tier of the data they are asked to process.";
      type = types.submodule {
        options = {
          scheme = mkOption {
            type = types.enum [ "four-tier-public-internal-sensitive-restricted" ];
            description = "Name of the classification scheme in use. Single-value enum keeps the door open for future schemes without breaking the option.";
          };
          tiers = mkOption {
            type = types.listOf (types.submodule {
              options = {
                name = mkOption { type = types.str; };
                level = mkOption { type = types.ints.positive; };
                examples = mkOption { type = types.listOf types.str; };
                handling = mkOption { type = types.str; };
              };
            });
            description = "Ordered list of tiers, lowest to highest sensitivity.";
          };
        };
      };
      default = {
        scheme = "four-tier-public-internal-sensitive-restricted";
        tiers = [
          {
            name = "Public";
            level = 1;
            examples = [ "Published documentation" "Open-source code" "Public model cards" ];
            handling = "No confidentiality controls required. Integrity via Git.";
          }
          {
            name = "Internal";
            level = 2;
            examples = [ "Deployment hostnames" "Infrastructure topology" "Non-sensitive operational logs" ];
            handling = "LAN-only, access-controlled. No encryption at rest mandatory.";
          }
          {
            name = "Sensitive";
            level = 3;
            examples = [ "AI inference metadata (no content)" "Aggregate model usage stats" "Agent action logs" ];
            handling = "LAN-only, authenticated access, encryption in transit (TLS), audit logged.";
          }
          {
            name = "Restricted";
            level = 4;
            examples = [ "ePHI" "PCI CHD if in scope" "LUKS passphrases" "Age private keys" "TLS private keys" "TOTP seeds" "API tokens" ];
            handling = "sops-nix only; never in plaintext; never in Nix store; encryption in transit required; audit logging required; memory isolation (ProtectSystem=strict, RAM considerations documented).";
          }
        ];
      };
    };

    tenancy = mkOption {
      description = "Single-tenant vs multi-tenant declaration. Downstream crypto, secrets, and agent-sandbox modules gate on this. Single-tenant is the project's designed-for mode; multi-tenant would require substantial additions (per-tenant sops recipients, per-tenant agent UIDs, per-tenant model registries, per-tenant audit streams).";
      type = types.submodule {
        options = {
          mode = mkOption {
            type = types.enum [ "single-tenant" "multi-tenant" ];
            description = "Tenancy mode. Default is single-tenant.";
          };
          rationale = mkOption {
            type = types.str;
            description = "Short prose explaining the choice. Useful as evidence for compliance assessors who ask 'how do you isolate tenants?' — answer differs fundamentally between the two modes.";
          };
        };
      };
      default = {
        mode = "single-tenant";
        rationale = "The system is designed for a single operator and a single organisation's data. Multi-tenant would require per-tenant age keys in sops recipients, per-tenant UIDs on every service, per-tenant ePHI separation in storage, and per-tenant audit streams — none of which are implemented. Declaring single-tenant explicitly prevents compliance assessors from assuming isolation controls that are not there.";
      };
    };

  };
}
