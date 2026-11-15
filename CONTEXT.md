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

**Private Service**:
An application on the VPS reachable only over the Tailnet, never through the Reverse Proxy. New applications are Private Services by default; a Public Service is the exception, made only when someone other than the owner needs access.
_Avoid_: internal app, hidden service

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
The single container in which the Pi Agent runs. It is the only thing the owner reaches over the Tailnet to use the Pi Agent, by Tailscale SSH or through the Web UI. A compromise of the Pi Agent must stay inside it.
_Avoid_: VM (it is a container, not a virtual machine), agent box

**Web UI**:
pi-web, the browser interface to the Pi Agent. It runs inside the Sandbox and is published to the Tailnet only; its optional password login is not enabled.
_Avoid_: dashboard, frontend

**Agent Credential**:
A secret the Sandbox holds so the Pi Agent can act (a GitHub token, an OpenRouter key). Always scoped, capped and revocable.
_Avoid_: key, token (when unspecific)

## Relationships

- A **Public Service** is reached only through the **Reverse Proxy**; the **Sandbox** is never behind it.
- The **Sandbox** is reached only over the **Tailnet**; it is the one **Private Service** that also holds **Agent Credentials**.
- A **Private Service** is never behind the **Reverse Proxy**.
- The **Sandbox** holds **Agent Credentials** and has no access to the **Host** or any **Public Service**.
