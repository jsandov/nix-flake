# INFRA-01 + INFRA-02 — nftables conversion and listener binding sweep

Session notes from landing INFRA-01 (firewall backend) and INFRA-02 (listener bindings) as a batched PRD-sweep PR. Both act conceptually on the same `modules/lan-only-network` territory, which is why they were batched.

## Why batched

INFRA-01 is "use nftables, not iptables." INFRA-02 is "bind to LAN-interface or loopback, never 0.0.0.0." Both appear in the same Nix snippets across the same three PRDs (NIST, HIPAA, STIG). A batched PR cuts the reviewer's context-switching cost and lets one CI run validate the combined change.

Lesson 23 (one P0 per PR) has a legitimate exception: when two TODOs act on the same file regions and the same reviewer mental model, they can share a PR. The test is whether splitting would force the reviewer to page-in context twice — here it would, so batching wins.

## INFRA-01 fixes — iptables → nftables

Three PRD snippets had `networking.firewall.extraCommands = ''iptables ...''` or similar. Converted each to `networking.nftables.tables.<name>` with structured `content` strings. Per-UID rules use `meta skuid`, not iptables `--uid-owner`.

| File | What changed |
|---|---|
| `prd-nist-800-53.md` §SC-7 firewall block | `extraCommands` with 4 iptables INPUT rules → `networking.nftables.tables.lan-only` with `iifname "${lanInterface}"` source filters on input chain |
| `prd-hipaa.md` §7.2 breach-detect block | 15-line `extraCommands` with iptables `--uid-owner` per-service egress → `networking.nftables.tables.per-uid-egress` with `meta skuid <user>` filters, explicit `log prefix "BREACH-DETECT <svc>: "` then `drop` |
| `prd-stig-disa.md` §egress block | `extraCommands = ''iptables -A OUTPUT ...''` → `networking.nftables.tables.egress-control` with RFC1918 destinations, LAN DNS, NTP |

Also normalised a handful of related references:

- `prd-nist-800-53.md` SC-7 table row — was "via `networking.firewall.extraCommands` with iptables rules," now "via `networking.nftables.tables.*`."
- `prd-nist-800-53.md` evidence command — was `iptables -L -n -v`, now `nft list ruleset` with a note that `iptables` is unavailable on NixOS 24.11 nftables.
- `prd-hipaa.md` control-mapping table cell — was "iptables OUTPUT rules per service user," now "nftables per-UID egress rules (`meta skuid`)."
- `prd-stig-disa.md` `environment.systemPackages` list — removed `iptables` because on 24.11 it resolves to `iptables-nft` and produces confusing output for admins expecting native iptables semantics. Kept `nftables`.

## INFRA-02 fixes — listener bindings

Two Nginx virtualHost listen-address blocks in `prd-stig-disa.md` used `addr = "0.0.0.0"`. Replaced with `addr = "<LAN_INTERFACE_IP>"` plus an inline comment explaining that:

1. Nginx is the one service intentionally exposed on the LAN.
2. On a single-NIC host, LAN interface equals 0.0.0.0 plus firewall gating; the explicit address is still preferred so intent survives a future second NIC.
3. Per prd.md Appendix A.1, SSH and Nginx follow the same LAN-interface-only rule.

Verified OLLAMA_HOST is already `127.0.0.1:11434` everywhere (confirmed in earlier sweeps; AI-06 partial credit).

## Pattern for nftables structured tables on NixOS 24.11

The standard form used throughout:

```nix
networking.nftables.tables.<table-name> = {
  family = "inet";  # "ip", "ip6", "inet", "arp", "bridge", "netdev"
  content = ''
    chain <chain-name> {
      type filter hook <hook> priority <N>; policy <default>;
      ct state established,related accept
      oif lo accept           # always allow loopback
      <match clauses>
    }
  '';
};
```

Hook + priority options that matter here:

- `input` hook (priority 0) — incoming traffic. Use `iifname "<iface>"` to filter by arrival interface.
- `output` hook (priority 0) — outgoing. Use `meta skuid <user>` for per-UID filtering, `oif lo accept` to always allow loopback.
- `forward` hook (priority 0) — transit. Not needed here (server not a router).

## `meta skuid` vs iptables `--uid-owner`

The one-to-one translation:

```
iptables:  -A OUTPUT -m owner --uid-owner ollama -d 10.0.0.0/8 -j ACCEPT
nftables:  meta skuid ollama ip daddr 10.0.0.0/8 accept
```

Key differences worth noting for future implementers:

- `--uid-owner` takes a numeric UID or user name; nftables `meta skuid` also accepts both but resolves user names at ruleset load time. Rename users and the rule may need reloading.
- `--log-prefix` → `log prefix "<string>"` with the match syntax identical otherwise.
- Policy drops at chain level (`policy drop;`) replace the trailing `-A OUTPUT -j DROP` clause common in iptables.

## What's still out of scope for this PR

- **Actual `modules/lan-only-network/default.nix` implementation.** The stub module remains empty. Real wiring happens when the first host consumes the rules through `canonical.firewall` (future ARCH-??? once consumer patterns settle).
- **Multiple LAN interfaces.** Everything assumes a single-NIC host. The `<LAN_INTERFACE_IP>` placeholder makes the multi-NIC case a deployment-time substitution; no PR required unless architecture changes.
- **IPv6 scope.** Still an open decision (`todos/README.md` #6). Rules are IPv4-only today; `family = "inet"` is IPv4+IPv6 but the match clauses use `ip daddr`/`ip saddr`. When IPv6 lands, add parallel `ip6 daddr`/`ip6 saddr` clauses.

## Suggested wiki compile targets

- `wiki/nixos-platform/nftables-translation-reference.md` (new) — the iptables ↔ nftables one-to-one table, the structured `networking.nftables.tables.*` pattern, and the hook/priority cheat-sheet.
- `wiki/architecture/data-flows.md` — existing article; consider adding a note that Nginx is the one intentionally-LAN-exposed service, bound to the LAN interface per canonical, gated by the firewall default-deny.
