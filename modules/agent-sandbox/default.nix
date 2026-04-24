{ ... }:
{
  # agent-sandbox — systemd isolation for AI agents: PrivateTmp,
  # ProtectSystem=strict, NoNewPrivileges, seccomp, per-agent UID,
  # tool allowlisting, human-in-the-loop approval gates, resource quotas.
  #
  # Control families: NIST AC/SC/SI/AU; HIPAA Min Necessary; PCI Req 7/8;
  # OWASP tool restriction; ATLAS agent-risk controls.
  #
  # Implementation lives in AI-08, AI-11 in todos/03-ai-and-compliance.md.
}
