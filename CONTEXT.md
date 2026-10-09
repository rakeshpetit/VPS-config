# VPS Config

Configuration for a single personal Hetzner VPS that hosts self-run web services behind a reverse proxy, plus a sandboxed coding agent.

## Language

**VPS**:
The one Hetzner machine that runs everything in this repo.
_Avoid_: server, box, host (when the distinction from the Sandbox matters, say **Host**)

**Host**:
The VPS operating system itself, outside any container.
_Avoid_: VPS (when contrasting with the Sandbox)

**Public Service**:
An application on the VPS reachable from the internet through the Reverse Proxy under a domain name.
_Avoid_: app, site

**Reverse Proxy**:
Nginx Proxy Manager, the only component that terminates public HTTP/HTTPS for Public Services.
_Avoid_: NPM, nginx

**Tailnet**:
The owner's private Tailscale network. Only identities and devices the owner authorizes can join it.
_Avoid_: VPN, private network

**Pi Agent**:
The Pi coding agent, an LLM-driven command-line tool that runs shell commands and edits code on the owner's behalf.
_Avoid_: bot, AI, assistant

**Sandbox**:
The single container in which the Pi Agent runs. It is the only thing the owner reaches over the Tailnet to use the Pi Agent. A compromise of the Pi Agent must stay inside it.
_Avoid_: VM (it is a container, not a virtual machine), agent box

**Agent Credential**:
A secret the Sandbox holds so the Pi Agent can act (a GitHub token, an OpenRouter key). Always scoped, capped and revocable.
_Avoid_: key, token (when unspecific)

## Relationships

- A **Public Service** is reached only through the **Reverse Proxy**; the **Sandbox** is never behind it.
- The **Sandbox** is reached only over the **Tailnet**.
- The **Sandbox** holds **Agent Credentials** and has no access to the **Host** or any **Public Service**.
