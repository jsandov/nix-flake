_:
{
  # ai-services — Ollama bound to 127.0.0.1:11434, LAN access via Nginx
  # TLS reverse proxy only. Model registry with provenance, per-client
  # rate limiting (≤30 req/min), input/output logging, prompt-injection
  # mitigations.
  #
  # Depends on: gpu-node, agent-sandbox, lan-only-network.
  #
  # Control families: NIST AC/SC/SI/AU; HIPAA ePHI/Encryption;
  # PCI Req 3/4/8; OWASP prompt-injection/data-leakage; AI-Gov model
  # governance.
  #
  # Implementation lives in AI-02, AI-03, AI-06, AI-09, AI-11, AI-22
  # in todos/03-ai-and-compliance.md.
}
