# nftables Translation Reference

Cheat-sheet for writing nftables rules on NixOS 24.11+. The firewall backend is nftables by policy (see [[../shared-controls/canonical-config|canonical.firewall.backend]]). `networking.firewall.extraCommands` with iptables syntax is forbidden — it conflicts with the nftables backend and produces undefined behaviour.

## Structured Module Pattern

The NixOS-native form for declaring rules. Always prefer this over raw `extraCommands`:

```nix
networking.nftables.tables.<table-name> = {
  family = "inet";  # inet = IPv4+IPv6; ip = IPv4-only; ip6 = IPv6-only
  content = ''
    chain <chain-name> {
      type filter hook <hook> priority <N>; policy <default>;
      ct state established,related accept
      oif lo accept               # always allow loopback (for output chains)
      <match clauses>
    }
  '';
};
```

## Hook + Priority Cheat-Sheet

| Hook | Priority | Purpose | Where used in this project |
|---|---|---|---|
| `input` | 0 | Incoming traffic, filter by arrival interface (`iifname`) | LAN-only inbound enforcement |
| `output` | 0 | Outgoing traffic, filter by user (`meta skuid`) | Per-UID egress for ollama, ai-services, agent |
| `forward` | 0 | Transit traffic | Not used — server is not a router |
| `prerouting` | -100 | Pre-routing mangle (NAT) | Not used |
| `postrouting` | 100 | Post-routing (masquerade) | Not used |

`policy drop;` at the chain level replaces the `-A OUTPUT -j DROP` trailing clause common in iptables.

## iptables → nftables Translation Table

The one-to-one mapping for the patterns this project actually uses:

| iptables | nftables |
|---|---|
| `-A INPUT -i <iface> -j DROP` | `iifname "<iface>" drop` |
| `-A OUTPUT -o lo -j ACCEPT` | `oif lo accept` |
| `-A OUTPUT -d 10.0.0.0/8 -j ACCEPT` | `ip daddr 10.0.0.0/8 accept` |
| `-A OUTPUT -p udp --dport 53 -j ACCEPT` | `udp dport 53 accept` |
| `-A INPUT -s 192.168.0.0/16 -j ACCEPT` | `ip saddr 192.168.0.0/16 accept` |
| `-A OUTPUT -m owner --uid-owner ollama -j ACCEPT` | `meta skuid ollama accept` |
| `-m state --state ESTABLISHED,RELATED -j ACCEPT` | `ct state established,related accept` |
| `-j LOG --log-prefix "PREFIX: "` | `log prefix "PREFIX: "` |

## `meta skuid` vs iptables `--uid-owner`

Near-identical semantics with one practical difference: `meta skuid` resolves user names at ruleset load time, so renaming a user after activation requires a reload. `--uid-owner` resolved at match time.

Not a big deal for this project's declarative model — renaming a user is a `nixos-rebuild switch`, which reloads the ruleset.

## What NOT To Do

- **Never** `networking.firewall.extraCommands = ''iptables ...''`. Even with `networking.nftables.enable = true` this can produce conflicting rulesets.
- **Never** mix `iptables-nft` commands with structured tables — use one or the other.
- **Never** include the `iptables` package in `environment.systemPackages` for admin use. On NixOS 24.11 it resolves to `iptables-nft` which produces confusing output when the admin expects native iptables semantics. Use `nft` directly.

## Evidence Commands

For compliance evidence dumps ([[../shared-controls/canonical-config|canonical.scanning]]):

```
nft list ruleset > firewall-rules.txt
```

Replaces the old `iptables -L -n -v` idiom — the `iptables` command is effectively unavailable on this project's nftables backend.

## Real Examples From This Project

Landed in PRs #30 and #33. See `docs/prd/prd-nist-800-53.md` §SC-7 (LAN-only input filter), `docs/prd/prd-hipaa.md` §7.2 (per-UID breach-detect egress), `docs/prd/prd-stig-disa.md` §egress (RFC1918 + DNS + NTP allowlist) for three complete patterns.

## Key Takeaways

- Always use `networking.nftables.tables.<name>` — never `extraCommands` with iptables.
- `policy drop;` at chain level > trailing `-j DROP` clause.
- Always add `ct state established,related accept` + `oif lo accept` at the top of output chains.
- `meta skuid` is the per-UID filter; matches iptables `--uid-owner` semantics minus rename-at-runtime behaviour.
- Evidence dump: `nft list ruleset`. Never `iptables -L -n -v`.
