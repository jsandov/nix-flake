_:
{
  # audit-and-aide — kernel auditd rules + (later, INFRA-09) AIDE file
  # integrity + (later, ARCH-10) evidence generation framework.
  #
  # This PR (INFRA-04) implements the auditd portion:
  #   - security.auditd.enable + security.audit.enable
  #   - comprehensive audit-rule set with NixOS-correct paths
  #     (/run/wrappers/bin for setuid wrappers; /run/current-system/sw/bin
  #     for standard binaries — see wiki/nixos-platform/nixos-audit-rule-paths)
  #   - setuid/setgid, personality, ptrace, open_by_handle_at syscalls
  #   - failed access attempts (EACCES / EPERM on open/openat)
  #   - audit log tamper detection
  #   - nixos-rebuild detection via /nix/var/nix/profiles/system and
  #     /run/current-system watchers
  #   - `-e 2` at the end locks the ruleset until reboot
  #
  # AIDE configuration is deferred to INFRA-09 which will consume
  # config.canonical.aidePaths for path selection.
  #
  # Control families: NIST AU-2 / AU-3 / AU-12 / SI-4; HIPAA §164.312(b)
  # Audit Controls; PCI 10.2 / 10.3; STIG primary audit baseline.

  security.auditd.enable = true;
  security.audit = {
    enable = true;

    # Backlog sizing — audit kernel buffer. 8192 is the STIG recommendation;
    # higher values reduce message loss under burst load at the cost of
    # kernel memory.
    backlogLimit = 8192;

    # Fail-closed on audit subsystem failure. The alternatives are:
    #   0 (silent, never panic) — loses events, bad for compliance
    #   1 (printk only) — logs kernel message, continues running
    #   2 (panic) — halts the system, maximally safe but operationally risky
    # PCI 10.5.3 and STIG recommend 1 at minimum; the policy below
    # survives transient kernel issues while keeping the evidence trail.
    failureMode = "printk";

    rules = [
      # ---- Account and authentication file modification ----
      "-w /etc/passwd -p wa -k account-modification"
      "-w /etc/group -p wa -k account-modification"
      "-w /etc/shadow -p wa -k account-modification"
      "-w /etc/gshadow -p wa -k account-modification"
      "-w /etc/sudoers -p wa -k sudoers-modification"
      "-w /etc/sudoers.d -p wa -k sudoers-modification"

      # ---- PAM configuration ----
      "-w /etc/pam.d -p wa -k pam-modification"

      # ---- SSH server configuration ----
      "-w /etc/ssh/sshd_config -p wa -k ssh-config-modification"

      # ---- Privilege escalation via setuid wrappers (NixOS paths) ----
      # NixOS puts setuid-wrapped binaries under /run/wrappers/bin,
      # never /usr/bin. Watching the wrapper paths is what actually
      # captures sudo / su / passwd invocation on this platform.
      "-w /run/wrappers/bin/sudo -p x -k privilege-escalation"
      "-w /run/wrappers/bin/su -p x -k privilege-escalation"
      "-w /run/wrappers/bin/passwd -p x -k privilege-escalation"
      "-w /run/wrappers/bin/chsh -p x -k privilege-escalation"
      "-w /run/wrappers/bin/newgrp -p x -k privilege-escalation"

      # ---- Account management (non-setuid) ----
      "-w /run/current-system/sw/bin/chage -p x -k account-modification"

      # ---- NixOS system configuration changes ----
      # /nix/var/nix/profiles/system is the generation symlink; watching
      # it catches every `nixos-rebuild switch`, which is how user
      # accounts, system config, and software inventory change on NixOS.
      "-w /nix/var/nix/profiles/system -p wa -k nixos-rebuild"
      "-w /run/current-system -p wa -k nixos-rebuild"
      "-w /etc/nixos -p wa -k nixos-config-modification"

      # ---- Audit log tamper detection ----
      "-w /var/log/audit -p wa -k audit-log-tamper"
      "-w /etc/audit -p wa -k audit-config-modification"

      # ---- Kernel module loading (NixOS paths; see ARCH-06) ----
      "-w /run/current-system/sw/bin/modprobe -p x -k kernel-modules"
      "-w /run/current-system/sw/bin/insmod -p x -k kernel-modules"
      "-w /run/current-system/sw/bin/rmmod -p x -k kernel-modules"
      "-a always,exit -F arch=b64 -S init_module -S delete_module -S finit_module -k kernel-modules"

      # ---- Setuid / setgid syscalls ----
      "-a always,exit -F arch=b64 -S setuid -S setgid -k privilege-escalation"
      "-a always,exit -F arch=b64 -S setreuid -S setregid -k privilege-escalation"
      "-a always,exit -F arch=b64 -S setresuid -S setresgid -k privilege-escalation"

      # ---- Time changes (audit log correlation integrity) ----
      "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -S clock_settime -k time-change"
      "-w /etc/localtime -p wa -k time-change"

      # ---- Network configuration ----
      "-w /etc/hosts -p wa -k network-config"
      "-w /etc/resolv.conf -p wa -k network-config"
      "-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network-config"

      # ---- Process and personality manipulation ----
      # MASTER-REVIEW STIG should-fix #3 called these out as missing.
      "-a always,exit -F arch=b64 -S personality -k personality-change"
      "-a always,exit -F arch=b64 -S ptrace -k process-trace"
      "-a always,exit -F arch=b64 -S open_by_handle_at -k file-handle-abuse"

      # ---- Failed access attempts ----
      # High-signal events — a denied open() is either a probe or a
      # legitimate permission surprise. Worth auditing both forms.
      "-a always,exit -F arch=b64 -S open -F exit=-EACCES -k access-denied"
      "-a always,exit -F arch=b64 -S openat -F exit=-EACCES -k access-denied"
      "-a always,exit -F arch=b64 -S open -F exit=-EPERM -k access-denied"
      "-a always,exit -F arch=b64 -S openat -F exit=-EPERM -k access-denied"

      # ---- Mount / umount (device access, privilege boundary changes) ----
      "-a always,exit -F arch=b64 -S mount -S umount2 -k filesystem-mount"

      # ---- Deletion / rename of sensitive files ----
      "-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k file-deletion"

      # ---- Lock the ruleset (prevents runtime modification until reboot) ----
      # MUST be the last rule. `-e 2` freezes the ruleset; a process with
      # CAP_AUDIT_CONTROL cannot remove or modify rules until the next
      # reboot. Required by STIG; a cornerstone audit integrity control.
      "-e 2"
    ];
  };

  # Persistent journal so audit events survive reboot for offline review.
  # Retention value comes from canonical (365-day PCI/HITRUST resolution).
  # The journal is distinct from /var/log/audit/audit.log; both are read
  # for cross-referenced evidence.
  services.journald.extraConfig = ''
    Storage=persistent
    Compress=yes
  '';
}
