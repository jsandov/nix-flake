# Build-and-test strategy

How the project produces bootable artifacts (ISO, qcow2) and exercises acceptance checks. Recommendation landed in the build-and-test tooling research (PRs #50 + #51); this article is the compiled wiki form. Raw note: `compliant-nix-config-vault/raw/build-and-test-tooling-research.md`.

## Primary stack

- **`nixos-generators`** — all disk-image outputs (ISO, qcow2, raw, vm, vagrant-virtualbox, proxmox, hyperv, vmware, …) from the same flake-pinned eval.
- **`pkgs.testers.runNixOSTest`** — headless pytest-style acceptance tests; each prd.md §10 criterion becomes a derivation under `checks.x86_64-linux.*`. Canonical for out-of-tree consumers in nixpkgs 24.11+. `pkgs.nixosTest` / `make-test-python.nix` are outdated.
- **`config.system.build.vm`** — fastest smoke-boot on an x86_64 dev box (`nix run .#nixosConfigurations.ai-server.config.system.build.vm`).
- **`nixos-anywhere` + `disko`** — remote install and re-install; declarative disk layout shared with `nixos-generators` image builds and `runNixOSTest` LUKS assertions.

## Dropped

- **Packer.** `nixos-generators` covers every format the project needs; Packer's HCL is a second truth-source, and its provisioner inputs escape `flake.lock`. No unique role.
- **Vagrant as a first-class dev target.** `system.build.vm` covers the dev-VM case. `nixos-generators format vagrant-virtualbox` emits a box on demand for contributors who want one; **no `Vagrantfile` in-tree**.

## Forward-looking note on `nixos-generators`

The `github:nix-community/nixos-generators` repo was **archived 2026-01-30** (read-only). Content was upstreamed into nixpkgs starting with NixOS 25.05. On the current `nixos-24.11` pin the archived flake input still works exactly as described; when the project bumps to 25.05+, switch to the in-tree equivalents (likely `pkgs.nixos-generators` or a `nixos/lib/*` entry point — decide at bump time).

## ARCH-09 interaction — Secure Boot

Stance: **ship images with lanzaboote pre-configured but defer sbctl key enrolment to first boot**. Operator runbook:

```
sbctl create-keys
sbctl enroll-keys --microsoft
nixos-rebuild switch
```

Rejected alternatives: baking a build-time test key and rotating on deploy (risks signed-with-test-key production on rotation skip); shipping systemd-boot and flipping to lanzaboote on first rebuild (two different bootloaders, first-boot drift).

SB verification inside `runNixOSTest` needs OVMF + per-test-run nvram plumbing. Practical rule: mark SB-enrolment criteria as "hardware-only, tagged-release gate" rather than a per-PR test.

Authoritative lanzaboote docs: https://nix-community.github.io/lanzaboote/ (the repo-relative `docs/QUICK_START.md` is a 404 and should not be cited).

## ARCH-10 interaction — evidence hook

The [[../shared-controls/evidence-generation|ARCH-10 snapshot]] runs on every `nixos-rebuild switch`. Consequences for each artifact shape:

- **Burned install-ISO.** First boot = one activation = one snapshot. Capture the baseline by `runNixOSTest`-ing a fresh install and `nix copy`ing `/var/lib/compliance-evidence/` out of the VM.
- **qcow2 / vagrant-box.** Each `virsh start` + in-VM rebuild adds a snapshot — fine for dev; pollutes acceptance-test output. Test-harness modules should `systemd.services.compliance-evidence-snapshot.enable = lib.mkForce false` to silence the driver's switch calls.
- **Live server.** Unchanged — weekly timer + activation hook both fire.

Two toggles worth adding to `modules/audit-and-aide/evidence.nix` (proposed ARCH-22): `firstBootMarker` to tag the initial snapshot as `/var/lib/compliance-evidence/00000000-firstboot/`, and `activationOnly = false` to let a test harness mute the activation path.

## CI integration — three tiers

| Trigger | Jobs | Runner | Wall clock | Artifacts |
|---|---|---|---|---|
| Every PR (existing) | 8-step CI gate | `ubuntu-24.04` | 1–3 min | none |
| Every PR (new) | `runNixOSTest` fast subset | `ubuntu-24.04` | +3–6 min | JUnit logs |
| Nightly on `main` | Full `runNixOSTest` matrix + ISO + qcow2 | `ubuntu-24.04` | 20–30 min | image + `.meta.json` + closure manifest |
| `workflow_dispatch` (RC) | Nightly + SHA-256 + GPG signature | `ubuntu-24.04` | 25–35 min | signed assets |
| Tagged release (`v*`) | RC + upload to GitHub Releases | `ubuntu-24.04` | 25–35 min | published |

Rationale: the per-PR budget is a **gate**, not a 20-minute ISO build — blocking CI on image builds would train "merge anyway." The fast subset catches what lints cannot (sshd actually starts on the resolved config). Nightly catches module-interaction regressions; failures open issues rather than block merges. Release-only signing keeps keys off day-to-day CI.

## Per-image evidence trail

Every image build captures: `flake.lock` SHA, `nix flake metadata --json`, toplevel `drvPath`, image SHA-256, closure manifest (`nix-store --query --requisites`). Bundle as `ai-server-YYYYMMDD.meta.json`. The reproducibility claim is **toplevel derivation** reproducibility, not byte-level file-hash — NixOS disk-image byte-reproducibility is not a current nixpkgs guarantee.

## ARM-host dev-loop limitations

The Raspberry Pi dev environment (`aarch64-linux`) **can** run `nix flake check`, `nix eval`, statix, deadnix, and grep-based lints locally. It **cannot** realistically realise `system.build.vm` for `x86_64-linux` (qemu-user TCG is ~30× KVM slowdown), run `runNixOSTest` with x86_64 nodes, or build the ISO/qcow2 locally.

Fallback order: GitHub-hosted `ubuntu-24.04` runner → remote x86_64 builder via `nix.distributedBuilds = true` → cloud x86_64 dev VM.

## What this unblocks

- **ARCH-17** — acceptance-test harness; each prd.md §10 criterion becomes a `checks.x86_64-linux.*` derivation under `runNixOSTest`.
- **ARCH-19..25** (proposed TODOs from the research note, not yet created): nixos-generators wiring, disko layout, nightly ISO build, evidence-collector `firstBootMarker` + `activationOnly`, release signing, remote-builder ops doc, Secure Boot first-boot runbook.

## Rejected approaches

- Packer as primary image builder — duplicates `nixos-generators` in non-Nix DSL.
- `Vagrantfile` in-tree — second truth-source.
- Bake test Secure Boot keys — rotation-skip risk.
- Full `runNixOSTest` matrix per PR — pushes wall clock past contributor tolerance.
- `DeterminateSystems/nix-installer-action` for image jobs — repo is on `cachix/install-nix-action@v27` per [[../nixos-platform/github-actions-nix-stack]].
- Hosted build infra (Garnix, Hercules-CI) — revisit only on cost pressure.

## Open questions (unresolved after the verify pass)

- **`nixos-anywhere` + lanzaboote end-to-end** — no documented Secure Boot howto in nixos-anywhere as of v1.13.0. ARCH-25's runbook will need original integration work.
- **Disk-image byte-reproducibility in nixpkgs 24.11** — not resolvable by doc lookup; needs a build-and-diff experiment once ARCH-21 lands.
- **Cross-build from `aarch64` to `x86_64` on CI** — any module forcing IFD or native eval that breaks cross-build? Dry-run before ARCH-24.
- **Signing-key ceremony for ARCH-23** — human decision on root key holder, sub-key location, revocation path.
- **Per-PR subset of `runNixOSTest` criteria** — measurement pass post-harness.
- **`install-iso` vs `iso`** — operator preference between live-installer media and boot-the-configured-system.

## Key Takeaways

- One stack, driven from `flake.nix`: `nixos-generators` for images + `runNixOSTest` for checks + `nixos-anywhere` + `disko` for install.
- Per-PR fast; nightly full matrix + images; release-only signing.
- Toplevel-derivation reproducibility is the claim; byte-level is not guaranteed.
- ARM-host dev can eval; image builds and tests run on `ubuntu-24.04` CI or a remote x86_64 builder.
- Secure Boot: ship pre-configured, enrol at first boot. Never bake test keys.
