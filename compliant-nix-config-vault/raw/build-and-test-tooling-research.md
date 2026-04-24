# Build-and-test tooling — landscape and recommendation

Research date: 2026-04-24. Tracked by beads issue `nf-ugb`. Scope: how should
this project build and test `nixosConfigurations.ai-server` as a bootable
artifact (ISO, qcow2, Vagrant box, VM for acceptance tests)? Is Packer still
right? Is Vagrant earning its keep?

**Research-method caveat.** `WebSearch`, `WebFetch`, `curl`, and `gh api`
were sandbox-denied in this retry. Citations are paraphrased from
training-cutoff knowledge; every version- or API-specific claim carries a
`[verify: <url>]` marker for the upstream page to fetch before it is
treated as ground truth. The structural recommendation is robust across
version drift; only individual attribute/option claims need verification.

---

## TL;DR

- Drop Packer. `nixos-generators` emits every format the project needs (ISO,
  qcow2, raw, vm, vagrant-virtualbox, hyperv, proxmox, vmware, cloud images)
  from the same flake-pinned config. Packer is a second DSL whose
  provisioner inputs escape `flake.lock`.
- Drop Vagrant as a first-class dev target. `nix run
  .#nixosConfigurations.ai-server.config.system.build.vm` boots a KVM VM
  from the same evaluated config. Ship a `vagrant-virtualbox` box output on
  demand; do not commit a `Vagrantfile`.
- Adopt `pkgs.testers.runNixOSTest` (modern entry to the in-tree NixOS test
  framework) as the acceptance harness. ARCH-17 already reserves the slot.
  Tests run headless under KVM, are Python-driven, and compose into the
  ARCH-10 evidence bundle.
- ARM-host constraint: an `aarch64-linux` Pi cannot KVM-boot `x86_64-linux`
  at useful speed. Eval-only paths (`nix flake check`, `nix eval .drvPath`)
  work locally; full image builds and acceptance runs go to
  GitHub-hosted `ubuntu-24.04` or a remote x86_64 builder.
- CI: existing 8-step gate per PR (~1–3 min) + a fast `runNixOSTest` subset
  (~+3–6 min). Full matrix + ISO + qcow2 **nightly on `main`** and on
  `workflow_dispatch` for release candidates.

---

## Tools in the survey

### Packer (`hashicorp/packer`) + `packer-plugin-nixos`

- **What.** Templated multi-platform image builder; drives a base OS
  installer through a provisioner (shell, ansible, `nixos-rebuild`).
- **Plugin status.** Community `packer-plugin-nixos` forks exist
  (`nix-community/`, `nixbuild/`); none is listed in Packer's "Verified"
  integration tier at training cutoff. `[verify: https://github.com/nix-community/packer-plugin-nixos]`
  `[verify: https://developer.hashicorp.com/packer/integrations]`
- **Costs.** Second truth-source (HCL template re-encoding boot commands,
  disk, post-install). Provisioner phase executes outside Nix eval, so
  inputs escape `flake.lock`. Also HashiCorp BSL licensing since 2023
  `[verify: https://www.hashicorp.com/license-faq]`.
- **When right.** Non-NixOS base images; vendor installers (vSphere PXE).
  Not applicable here.
- **When wrong.** Pure-NixOS outputs with a native builder available.
- **This flake.** Either shadows `nixos-generators` or runs
  `nixos-rebuild`-as-provisioner into a blank qcow2 (worse `format = "qcow"`).
  No unique role.

### Vagrant

- **What.** Ruby `Vagrantfile` DSL wrapping a hypervisor (VirtualBox,
  libvirt, Hyper-V, VMware); box lifecycle; shell/ansible provisioning.
- **Costs.** Ruby DSL re-declares networking, port-forwards, CPU/RAM —
  already in the NixOS config. HashiCorp BSL since 2023. A `Vagrantfile` in
  the repo is a second CI-green surface that will diverge from the flake.
- **When right.** Multi-OS fleets; teams standardised on Vagrant; box
  publishing to a registry.
- **When wrong.** A single-OS NixOS project that can emit a driveable VM
  on its own.
- **This flake.** `nixos-generators format vagrant-virtualbox` produces a
  box on demand. Ship the box; no `Vagrantfile` in-tree.
  `[verify: https://github.com/nix-community/nixos-generators#supported-formats]`

### `nixos-generators` (`github:nix-community/nixos-generators`)

- **What.** Wraps `nixos/lib/make-disk-image.nix` to emit (training-cutoff
  list): `iso`, `install-iso`, `install-iso-hyperv`, `qcow`, `qcow-efi`,
  `raw`, `raw-efi`, `vm`, `vm-bootloader`, `vm-nogui`, `amazon`, `azure`,
  `do`, `gce`, `hyperv`, `openstack`, `proxmox`, `proxmox-lxc`,
  `vagrant-virtualbox`, `virtualbox`, `vmware`, `cloudstack`, `docker`,
  `lxc`, `kexec`, `kexec-bundle`, `sd-aarch64`, `sd-aarch64-installer`.
  `[verify: https://github.com/nix-community/nixos-generators#supported-formats]`
- **Costs.** One flake input. Shares the existing `nixosModules.*` outputs
  (flake.nix:50-61) for config reuse.
- **When right.** Any NixOS project needing "one config, many image
  shapes." Exactly this project.
- **When wrong.** Non-NixOS images; vcenter-side OVA plumbing beyond
  `make-disk-image`.
- **This flake.** Add as input; expose
  `packages.x86_64-linux.{iso,qcow2,vagrant-box}` each calling
  `nixosGenerate` with the shared module list. Image and live
  `nixos-rebuild switch` converge on the same toplevel derivation — the
  reproducibility contract Packer/Vagrant cannot offer.

### `nixos-rebuild build-vm` / `config.system.build.vm`

- **What.** Every `nixosConfigurations.*` exposes
  `config.system.build.vm` — a qemu/KVM runner with the host's `/nix/store`
  shared via 9p. `nixos-rebuild build-vm` is the wrapper.
  `[verify: https://nixos.org/manual/nixos/stable/#sec-running-nixos-tests-interactively]`
- **Costs.** Zero. Requires KVM; aarch64 cannot KVM x86_64.
- **When right.** Fast current-arch smoke on an x86_64 dev box (~30 s).
- **When wrong.** Artifact distribution; cross-arch dev.
- **This flake.** First-line local smoke on any x86_64 host. On the Pi:
  punt to CI or a remote builder.

### `pkgs.testers.runNixOSTest` (legacy `pkgs.nixosTest` / `makeTest`)

- **What.** In-tree NixOS test framework. Declares one or more machine
  definitions + a Python `testScript` (`machine.wait_for_unit`,
  `.succeed`, `.fail`, `.send_key`); runs headless under KVM; emits
  pass/fail + logs. `runNixOSTest` is the flake-friendly entry in
  `pkgs.testers.*`; `nixosTest` / `makeTest` are older but still supported.
  `[verify: https://nixos.org/manual/nixos/stable/#sec-nixos-tests]`
  `[verify: https://nixos.org/manual/nixos/stable/#sec-call-nixos-test-outside-nixpkgs]`
- **Costs.** KVM on the runner. Serial per invocation; parallelism via
  multiple derivations.
- **When right.** "Service X up, port Y answers, file Z has mode M,
  generation rollback boots." Covers every prd.md §10 criterion.
- **When wrong.** Real TPM / GPU / LAN switch / SB enrolment — hardware lab.
- **This flake.** Native fit for ARCH-17. Each criterion is a derivation
  under `checks.x86_64-linux.*`; `nix flake check` runs the fast subset,
  nightly runs the full matrix. `[verify:
  https://nixos.org/manual/nixpkgs/stable/#sec-tests-best-practices]`

### `nixos-anywhere`

- **What.** Installs a flake-defined NixOS onto a remote machine already
  running some Linux: kexec minimal installer, partition via `disko`,
  `nixos-install` over SSH. Supports non-root targets and reinstall of
  NixOS hosts. `[verify: https://github.com/nix-community/nixos-anywhere]`
- **Costs.** SSH reachability, `disko` config, kexec RAM floor; not for
  air-gapped.
- **When right.** First-install on factory-fresh x86_64 with a rescue OS;
  remote re-provisioning.
- **When wrong.** Air-gapped; tiny boot media.
- **This flake.** Shares a `disko` layout with `nixos-generators`. Claims
  lanzaboote support since v1.x `[verify:
  https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/secure-boot.md]`.

### `disko`

- **What.** Declarative disk partition/filesystem layout as a Nix
  attribute set; generates format/mount/install shell.
  `[verify: https://github.com/nix-community/disko]`
- **Costs.** One flake input; one new module subtree.
- **When right.** Layout-in-code; LUKS-on-disk tests in `runNixOSTest`.
- **When wrong.** Pure containers with no bare-metal footprint.
- **This flake.** One layout description feeds `nixos-generators` (image),
  `nixos-anywhere` (remote install), and `runNixOSTest` (LUKS assertion).

---

## Decision matrix

Legend: ✓ fit, ~ partial, ✗ wrong tool.

| Desired outcome | Packer | Vagrant | nixos-generators | `system.build.vm` | `runNixOSTest` | nixos-anywhere | disko | Recommended |
|---|---|---|---|---|---|---|---|---|
| Bootable ISO for USB bring-up | ~ | ✗ | ✓ | ✗ | ✗ | ✗ | ~ | nixos-generators `install-iso` |
| qcow2 for cloud / hypervisor | ~ | ✗ | ✓ | ✗ | ✗ | ✗ | ~ | nixos-generators `qcow` |
| Vagrant box for local dev | ~ | ~ | ✓ | ✗ | ✗ | ✗ | ✗ | nixos-generators `vagrant-virtualbox` (reserve) |
| Fast "does it boot?" smoke | ✗ | ~ | ~ | ✓ | ~ | ✗ | ✗ | `system.build.vm` |
| Acceptance-test runner | ✗ | ✗ | ✗ | ~ | ✓ | ✗ | ~ | `runNixOSTest` |
| Live installer ISO | ~ | ✗ | ✓ | ✗ | ✗ | ✗ | ~ | nixos-generators `install-iso` |
| Remote re-install of running host | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ | ✓ | nixos-anywhere + disko |
| Declarative disk-layout template | ✗ | ✗ | ~ | ✗ | ✗ | ~ | ✓ | disko |
| Evidence-bundle integration (ARCH-10) | ✗ | ✗ | ~ | ~ | ✓ | ~ | ✗ | `runNixOSTest` |

Packer and Vagrant do not win a single row.

---

## Recommendation

**Primary stack:**

- `nixos-generators` — all disk-image outputs.
- `pkgs.testers.runNixOSTest` — every prd.md §10 acceptance criterion.
- `config.system.build.vm` — ad-hoc local smoke on x86_64 workstations.
- `nixos-anywhere` + `disko` — remote install and re-install.

**Keep in reserve:**

- Packer — revisit only for vendor formats `nixos-generators` does not cover.
- Vagrant — ship a `vagrant-virtualbox` box + docs snippet; no `Vagrantfile`
  in-tree.

**Trade-off justification:**

- *Effort to land.* `nixos-generators` = one input + a few `packages` attrs;
  `runNixOSTest` = existing-pattern import. Packer = new HCL + provisioner
  + CI shell; Vagrant = new DSL + plugin dep.
- *Reproducibility.* Both chosen tools build from the flake-pinned eval;
  Packer's provisioner and Vagrant's box download are outside the seal.
- *Maintenance.* One config, many outputs; each extra tool is another
  CI-green surface.
- *Cross-compile / ARM.* `nixos-generators`, `system.build.vm`, and
  `runNixOSTest` honour `nixpkgs` cross and remote-builder infrastructure;
  Packer/Vagrant do not. None run well on the Pi, but `nixos-generators`
  lets the full build ship to a remote x86_64 builder via stock
  `nix build --builders …`.

---

## ARCH-09 interaction (Secure Boot)

`flake.nix:35` imports `lanzaboote.nixosModules.lanzaboote`; the skeleton
gates `security.secureBoot.enable` behind an opt-in. For built images the
right story is **(b) ship with lanzaboote pre-configured but keys deferred,
enrol on first boot.**

- Option (c) "bake test keys, rotate on deploy" risks signed-with-test-key
  production if rotation is skipped. Trust integrity ≠ operator discipline.
- Option (a) "systemd-boot → flip on first rebuild" ships a different
  bootloader than production, increasing first-boot drift.
- Option (b) keeps the production bootloader config; first-boot runbook is
  `sbctl create-keys && sbctl enroll-keys --microsoft && nixos-rebuild switch`.
  `[verify: https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md]`

SB verification in `runNixOSTest` needs OVMF + per-test-run nvram plumbing.
Mark the SB-enrolment criterion as "hardware-only, tagged-release gate."
`[verify: https://github.com/nix-community/lanzaboote/tree/master/nix/tests]`

---

## ARCH-10 interaction (evidence hook)

ARCH-10 (PR #47, shipped) runs the collector on every `nixos-rebuild switch`
via `system.activationScripts` + a weekly timer.

- **Burned install-ISO.** `nixos-install` + first boot = one activation,
  one snapshot — the *baseline*. Capture it via a `runNixOSTest` that boots
  the fresh image and `nix copy`es `/var/lib/compliance-evidence/` out.
- **qcow2 / vagrant-box.** Each `virsh start` + in-VM `nixos-rebuild switch`
  adds a snapshot. Fine for dev; pollutes acceptance-test output. In the
  test-harness module, `systemd.services.<collector>.enable = lib.mkForce false`
  silences the driver's `switch` calls.
- **Live server.** Unchanged: timer + activation both fire.

**Collector set change?** No. Two knobs worth adding to
`modules/audit-and-aide/evidence.nix`:

- `firstBootMarker` — tags the initial snapshot as
  `/var/lib/compliance-evidence/00000000-firstboot/`.
- `activationOnly = false` — test harness mutes the activation hook.

---

## CI integration sketch

Three-tier cadence extending (not replacing) the existing 8-step gate
(`wiki/architecture/ci-gate.md`, `wiki/nixos-platform/github-actions-nix-stack.md`).

| Trigger | Jobs | Runner | Wall clock | Artifacts |
|---|---|---|---|---|
| Every PR (existing) | `nix flake check`, eval, statix, deadnix, FHS lints, secret-leak lint | `ubuntu-24.04` | 1–3 min | none |
| Every PR (new) | `runNixOSTest` **fast subset** (sshd config eval, firewall ruleset eval, secret-not-in-store grep, one `wait_for_unit`) | `ubuntu-24.04` | +3–6 min | JUnit logs |
| Nightly on `main` | Full `runNixOSTest` matrix + `nixos-generators` ISO + qcow2 | `ubuntu-24.04` | 20–30 min | `ai-server-YYYYMMDD.iso`, `.qcow2`, full logs, `flake.meta.json`, `nix-store --query --requisites` manifest |
| `workflow_dispatch` (RC) | Nightly + SHA-256 + detached GPG signature | `ubuntu-24.04` | 25–35 min | above + `.sha256`, `.asc` |
| Tagged release (`v*`) | RC + upload to GitHub Releases | `ubuntu-24.04` | 25–35 min | published assets |

Rationale: PR budget is a gate, not a 20-min ISO build — blocking trains
"merge anyway." Fast subset catches what lints can't (sshd actually starts
on the resolved config). Nightly catches module-interaction regressions;
failures open issues rather than block merges. Release-only signing keeps
keys off day-to-day CI; use a CI-scoped GPG sub-key, not the root key.

**Per-image evidence trail.** Capture: `flake.lock` SHA, `nix flake
metadata --json`, toplevel `drvPath`, image SHA-256, closure manifest
(`nix-store --query --requisites`). Bundle as `ai-server-YYYYMMDD.meta.json`.
Claim: *toplevel derivation* reproducibility, not byte-level file-hash —
disk-image byte-reproducibility is not a current nixpkgs guarantee.
`[verify: https://nix.dev/manual/nix/stable/advanced-topics/diff-hashes.html]`
`[verify: https://reproducible-builds.org/docs/]`

---

## ARM-host dev-loop limitations

This Raspberry Pi (`aarch64-linux`) **can**: run `nix flake check`
eval-only paths; run `nix eval .#nixosConfigurations.ai-server.config.system.build.toplevel.drvPath`;
run `statix` / `deadnix` / grep-lints; edit source.

It **cannot, at useful speed**: realise `system.build.vm` for x86_64
(qemu-user TCG, ~30× KVM slowdown); run `runNixOSTest` with x86_64 nodes;
build the ISO or qcow2 locally (kernel + firmware closure realisation runs
hours under emulation).

Fallback order:

1. **GitHub-hosted `ubuntu-24.04` runner** — default for the nightly matrix.
2. **Remote x86_64 builder** via `nix.distributedBuilds = true` +
   `nix.buildMachines`. Pi dispatches; results come back via `nix copy`.
   Right story for same-session iteration.
3. **Cloud x86_64 dev VM** (EC2 c6i.large equivalent) as a manual escape
   hatch — cost and secrets handling make it non-default.

---

## Follow-up TODOs to create

All new; target `todos/01-architecture-and-cross-cutting.md`. ARCH-17
(acceptance-test harness) is reserved; these **extend**, not replace.

- `ARCH-19: Add nixos-generators flake input + packages.<system>.{iso,qcow2,vagrant-box} (P1, M)` — Prerequisite for every bootable artifact. Gate behind `workflow_dispatch` until nightly CI exists.
- `ARCH-20: Add disko flake input + declarative disk layout for ai-server (P1, M)` — Prerequisite for both nixos-anywhere and LUKS acceptance tests.
- `ARCH-21: Nightly ISO + qcow2 build on main (P2, M)` — Depends on ARCH-19. `ubuntu-24.04`, 20–30 min, uploads image + `.meta.json`.
- `ARCH-22: Evidence-collector firstBootMarker + activationOnly toggle (P2, S)` — Extends shipped ARCH-10 module.
- `ARCH-23: Release-tag signing workflow + SHA-256 + GPG sub-key ceremony (P2, M)` — Depends on ARCH-21 green.
- `ARCH-24: Remote x86_64 builder ops doc for ARM developers (P3, S)` — `nix.buildMachines` playbook; no code.
- `ARCH-25: Secure Boot first-boot enrolment runbook (P2, S)` — Depends on ARCH-09. Documents `sbctl` key enrolment + first switch.
- **ARCH-17 clarification (text edit, no new TODO).** Acceptance-test harness adopts `pkgs.testers.runNixOSTest`, PR-fast subset + nightly full matrix.

Total new TODOs: **7** (ARCH-19 through ARCH-25). Secrets/key work implied:
ARCH-23 signing sub-key ceremony + ARCH-25 sbctl enrolment runbook. No
change to sops-nix scope.

---

## Rejected approaches

- **Packer as primary image builder.** Duplicates `nixos-generators` in
  non-Nix DSL; provisioner inputs escape `flake.lock`; no unique role.
- **`Vagrantfile` in-tree.** Ruby-DSL second truth-source; `system.build.vm`
  covers the dev-VM case for free.
- **Bake sbctl test keys, rotate on deploy.** Signed-with-test-key
  production on rotation skip.
- **Full `runNixOSTest` matrix per PR.** Pushes wall clock past contributor
  tolerance; nightly catches the same regressions one night later.
- **DeterminateSystems `nix-installer-action` for image jobs.** Per
  `wiki/nixos-platform/github-actions-nix-stack.md`, `cachix/install-nix-action@v27`
  is the audited path.
- **Garnix / Hercules-CI.** Hosted-infra dependency; revisit only on cost
  pressure.

---

## Open questions

- **`pkgs.testers.runNixOSTest` vs `nixosTest` / `makeTest` in nixpkgs 24.11.** The testers-namespaced form was promoted mid-24.x; confirm canonical entry before ARCH-17 lands. `[verify: https://nixos.org/manual/nixos/stable/release-notes#sec-release-24.11]`
- **`nixos-anywhere` + lanzaboote end-to-end** with SB key enrolment over SSH — believed v1.x+. `[verify: https://github.com/nix-community/nixos-anywhere/blob/main/docs/howtos/secure-boot.md]`
- **Disk-image byte-reproducibility in 24.11.** Is `make-disk-image` byte-reproducible, or only toplevel-reproducible? Affects evidence-manifest wording. `[verify: https://github.com/NixOS/nixpkgs/blob/release-24.11/nixos/lib/make-disk-image.nix]`
- **Cross-build from aarch64 to x86_64 on CI.** Any module forcing IFD or a native eval that breaks cross-build? Needs a dry-run before ARCH-24.
- **Signing-key ceremony for ARCH-23.** Root key holder; sub-key location; revocation path. Human decision.
- **PR-tier subset selection.** Which prd.md §10 criteria are cheap enough per-PR? Measurement pass post-harness.
- **`install-iso` vs `iso`.** Live media with `nixos-install` vs boot-the-configured-system; `install-iso` is conventional for bare-metal. Confirm operator preference.
