# Pi Agent runs in one hardened Sandbox container reachable only over the Tailnet

The Pi Agent runs shell commands on our behalf, so a compromise must not reach the other services on the VPS. We run it in a single container on its own network, with no published ports. Tailscale runs inside that container in userspace mode (Tailscale SSH), so the owner reaches the Sandbox over the Tailnet and nothing else. The Host is deliberately not on the Tailnet and keeps its existing public SSH.

## Considered Options

- **Tailscale on the Host plus `docker exec`**: rejected, a docker-group login on the Host is effectively root on everything.
- **Sidecar Tailscale container sharing a network namespace**: rejected, Tailscale SSH would land in the sidecar, not the agent's container.
- **A real VM (Firecracker/KVM)**: not available, Hetzner ARM cloud instances do not allow nested virtualization. A container shares the Host kernel, so isolation relies on dropped capabilities, a read-only root filesystem, resource limits, and firewall rules blocking the Sandbox from the Host and private networks.

## Consequences

- Open internet egress is kept on purpose (the agent needs it), so Agent Credentials are protected by scope, expiry and spend caps rather than by secrecy alone.
- Egress rules live on the Host (`pi-agent/host/pi-sandbox-firewall.sh`) because traffic from the Sandbox to the Host itself bypasses `DOCKER-USER`.
- The Tailnet policy must give `tag:pi-agent` no outbound access, otherwise a compromised Sandbox could reach the owner's other devices.
