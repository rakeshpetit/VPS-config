# Pi Agent Sandbox

One hardened container running the Pi coding agent, reachable only over Tailscale SSH. Design rationale: `../docs/adr/0001-pi-agent-sandbox-on-tailnet.md`. Terms: `../CONTEXT.md`.

```shell
ssh pi@pi-agent     # from a device on your Tailnet (browser re-auth about every 12h)
pi                  # starts the agent; credentials are loaded by the wrapper
```

## What lives where

| Thing | Location | Survives `docker rm`? | In git? |
| --- | --- | --- | --- |
| Image definition, compose, scripts | this directory (`/root/pi-agent` on the VPS) | yes | yes |
| Agent Credentials | `/root/pi-agent/secrets/*` on the VPS (root dir 700, files uid 1000 mode 400) | yes (host files) | **never** |
| Pi state (`~/.pi`, shell history) | volume `pi-agent_pi-home` | yes, unless volumes are deleted | no |
| Code checkouts | volume `pi-agent_pi-workspace` | yes, unless volumes are deleted | no (push your work to GitHub) |
| Tailscale node key | volume `pi-agent_pi-tailscale` | yes, unless volumes are deleted | no |
| Egress firewall rules | systemd unit `pi-sandbox-firewall` on the VPS | yes (re-applied at boot) | unit file is |
| Tailnet policy | Tailscale admin console; copy in `tailscale-policy.hujson` | n/a | yes (copy) |
| Swap | `/swapfile` | yes | no |

`docker-compose down` keeps volumes. `docker-compose down -v`, `docker volume rm` or `docker system prune --volumes` deletes them.

Shorthand used below (run from your laptop in the repo root):

```shell
export V=root@OUR_IP_ADDRESS K=$PWD/secrets/hetzner_rsa
vps() { ssh -i $K $V "$@"; }
```

---

## First-time setup (from zero)

This is the complete process, in order. Steps marked **you** need a web console or a token that only you can handle. Everything else is a command.

**Prerequisites:** the VPS from the top-level `README.md` (Docker, docker-compose, Nginx Proxy Manager running, Hetzner firewall with only 22/80/443), an SSH key to the VPS, a Tailscale account with the Tailscale app installed and signed in on your laptop, a GitHub account and an OpenRouter account.

Resource note: the reference VPS has 2 vCPU and 3.7 GiB RAM with the existing services using about 2 GiB. The Sandbox is capped at 1 GiB and 1 CPU.

### 0. Audit the VPS first (read-only)

```shell
export V=root@OUR_IP_ADDRESS K=$PWD/secrets/hetzner_rsa
vps() { ssh -i $K $V "$@"; }

vps 'uname -m; free -h; df -h /; nproc'
vps 'docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}"; docker network ls'
vps 'ss -tlnp | head -40; ufw status; iptables -S | head -40; iptables -S DOCKER-USER'
vps 'sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication)"'
vps 'ls -l /dev/net/tun; command -v tailscale || echo "tailscale not installed on host (expected)"'
vps 'docker ps --format "{{.Names}}: {{.Status}}" | sort' | tee baseline-containers.txt   # compare after the deploy
```

Check that `172.28.0.0/24` is unused (`docker network inspect $(docker network ls -q) | grep Subnet`). If it clashes, change the subnet in `docker-compose.yml` and `host/pi-sandbox-firewall.sh` together. From your laptop, record which public ports are open:

```shell
for p in 22 80 81 443 8000 9443; do nc -z -w 3 OUR_IP_ADDRESS $p && echo "$p open" || echo "$p filtered"; done
```

Expected: only 22, 80 and 443 open. If 81, 8000 or 9443 are open, fix the Hetzner firewall first (Nginx Proxy Manager's admin and Portainer should not be public). This setup does not change that.

### 1. Tailnet policy (**you**)

The Tailscale default policy allows every device to reach every device, **including tagged ones**. A tagged Sandbox would be able to reach your laptop and phone. Replace that.

1. Open https://login.tailscale.com/admin/acls/file (Access controls, JSON editor).
2. Compare your current policy with `tailscale-policy.hujson`. If you still have the stock policy, paste the file's contents over it. If you have customized rules, merge instead:
   - add `"tagOwners": { "tag:pi-agent": ["autogroup:admin"] }`
   - change any rule whose `src` is `*` to `autogroup:member` (so tagged devices have no outbound access)
   - add the `ssh` rule for `tag:pi-agent` with `"users": ["pi"]`
3. Tagged devices you already have (for example a Home subnet router set up with a tag) will lose outbound access under this change. Give them their own explicit rule before saving.
4. Optional but recommended: add a `tests` block so the console refuses a policy that ever lets the Sandbox reach your devices. Use your laptop's Tailnet IP (`tailscale ip -4`):

   ```jsonc
   "tests": [
       { "src": "tag:pi-agent", "deny":   ["100.x.y.z:22"] },
       { "src": "100.x.y.z",    "accept": ["tag:pi-agent:22"] },
   ],
   ```

5. Save. The console runs tests on every save and rejects a failing policy.

### 2. Tailscale auth key (**you**)

1. https://login.tailscale.com/admin/settings/keys, **Generate auth key**.
2. Description `pi-agent sandbox`. **Reusable: off** (single-use). **Expiration: 1 day**. **Ephemeral: off** (an ephemeral node vanishes when it goes offline, and would disappear on every restart). Tags **on**: `tag:pi-agent`. The tag only appears in the list once the policy from step 1 is saved.
3. Copy the `tskey-auth-...` value. It is shown once. Keep it only for step 8.

### 3. GitHub token (**you**)

GitHub, Settings, Developer settings, Fine-grained tokens, Generate new token:

- **Resource owner:** you or the organization that owns the repos.
- **Repository access:** *Only select repositories*, and pick only the repos the agent may work on.
- **Permissions:** Contents: Read and write. Pull requests: Read and write. Metadata: Read (automatic). Nothing else (no Administration, Workflows, or organization permissions).
- **Expiration:** 60 days or less. Put a reminder in your calendar.

Recommended on each repo: a ruleset on `main` that blocks force-push and deletion, while still allowing merges. Merging to `main` is allowed by design, so this limits the damage of a bad push.

### 4. OpenRouter key (**you**)

OpenRouter, Keys, create a **dedicated** key named `pi-agent` with a **credit limit** (a monthly cap you are comfortable losing). Restrict models if the dashboard offers it. A leaked or looping key then costs at most the cap.

### 5. Copy the files to the VPS

```shell
rsync -av --exclude secrets/ -e "ssh -i $K" pi-agent/ $V:/root/pi-agent/
vps 'chown -R root:root /root/pi-agent'     # root executes host/*.sh, so they must not be owned by another uid
vps 'cd /root/pi-agent && mkdir -p secrets && touch secrets/github_token secrets/openrouter_api_key secrets/ts_authkey && docker-compose config -q && echo COMPOSE_OK; rm -f secrets/*; chmod 700 secrets'
```

### 6. Egress firewall (changes the Host)

Do this **before** starting the container.

```shell
vps 'cp /root/pi-agent/host/pi-sandbox-firewall.service /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now pi-sandbox-firewall'
vps '/root/pi-agent/host/pi-sandbox-firewall.sh status'
vps 'docker ps -q | wc -l'      # same count as the baseline
```

The rules only match traffic from `172.28.0.0/24`, which does not exist yet, so they cannot affect your running containers.

### 7. Swap (optional but recommended, changes the Host)

```shell
vps '/root/pi-agent/host/add-swap.sh'
```

A 2 GiB swapfile as an out-of-memory safety net for the existing services.

### 8. Secrets (**you**)

```shell
ssh -i $K $V
cd /root/pi-agent
./set-secret.sh ts_authkey
./set-secret.sh github_token
./set-secret.sh openrouter_api_key
stat -c '%n %U %a %s' secrets/*      # owner shows as UNKNOWN (uid 1000), mode 400, size > 0
```

### 9. Build and start

```shell
vps 'cd /root/pi-agent && docker-compose up -d --build'      # first build takes a few minutes on ARM
vps 'docker ps --filter name=pi-agent --format "{{.Status}} ports=[{{.Ports}}]"'    # healthy, ports empty
vps 'docker logs --tail 30 pi-agent'      # look for: Switching ipn state Starting -> Running
vps 'cd /root/pi-agent && : > secrets/ts_authkey'            # the key is spent, empty it
```

In the Tailscale admin console, **Machines** should now list `pi-agent` with the tag `tag:pi-agent`. Check the container can restart without the key: `vps 'cd /root/pi-agent && docker-compose restart'`, wait 40 seconds, and it should be `healthy` again.

### 10. Connect (**you**)

Turn Tailscale on in your laptop, then:

```shell
tailscale ping pi-agent          # "via DERP(...)" is normal; a direct path is not required
ssh pi@pi-agent                  # first connection prints a Tailscale URL: open it and approve
pi                               # choose an OpenRouter model inside Pi
```

On macOS the CLI is `/Applications/Tailscale.app/Contents/MacOS/Tailscale` if `tailscale` is not on your PATH. You land as the unprivileged user `pi` in `/home/pi`.

### 11. Verify

```shell
vps 'bash -s' < pi-agent/verify.sh
for p in 22 80 81 443 8000 9443; do nc -z -w 3 OUR_IP_ADDRESS $p && echo "$p open" || echo "$p filtered"; done
```

All `PASS`. Public ports identical to step 0. The existing containers match `baseline-containers.txt`.

If you want a stronger check than the Tailnet `tests` block, listen on your laptop (`nc -l 8765`), then from the Sandbox run `tailscale --socket=/tmp/tailscaled.sock nc <laptop-tailnet-ip> 8765`. It should hang and receive nothing. (`tailscale ping` is not a valid test because it bypasses ACLs.)

### 12. Optional: turn off password login on the Host's sshd (not done in the original setup)

The Host's public SSH on port 22 is unchanged by this setup. It still accepts passwords. Keys-only is safer, but a mistake can lock you out, so keep a second session open.

```shell
ssh -i $K $V        # session 1: keep open
# session 2 (new terminal): confirm key login works before touching anything
ssh -i $K -o PasswordAuthentication=no -o PreferredAuthentications=publickey $V true && echo KEY_LOGIN_OK

# in session 1 (sshd uses the FIRST value it sees, so the file name must sort before 50-cloud-init.conf)
echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/01-no-password.conf
sshd -t && systemctl reload ssh
sshd -T | grep -i passwordauthentication       # expect: passwordauthentication no
# session 3: ssh in with your key again to confirm, and only then close session 1
```

Rollback: `rm /etc/ssh/sshd_config.d/01-no-password.conf && systemctl reload ssh`. If you ever lock yourself out, use the Hetzner web console (the VNC console under the server's menu).

---

## Recovery scenarios

Find yours, then follow only that section.

### A. Container removed or crashed (volumes and files still there)

```shell
vps 'cd /root/pi-agent && docker-compose up -d'
```

The node rejoins the Tailnet from the key in the `pi-tailscale` volume. Nothing else is needed. Check with `vps 'docker ps --filter name=pi-agent'` (expect `healthy`) and `ssh pi@pi-agent`.

### B. Image removed (`docker rmi`) or you want a clean rebuild

```shell
vps 'cd /root/pi-agent && docker-compose up -d --build'
```

Pinned versions are in the `Dockerfile` (`PI_VERSION`, the `tailscale/tailscale:vX` tag). Update them there to upgrade.

### C. Container **and volumes** removed (host files still there)

The Tailscale node key is gone, so the Sandbox needs a fresh auth key. `secrets/github_token` and `secrets/openrouter_api_key` are still on the host and are reused as they are.

1. In the Tailscale admin console, **Machines**: delete the old `pi-agent` machine. If you skip this the new node is named `pi-agent-1` and the old name is stale.
2. **Settings → Keys → Generate auth key**: Reusable **off**, Expiration **1 day**, Ephemeral **off**, Tags **on** with `tag:pi-agent`.
3. On the VPS, set it (prompts without echo):

   ```shell
   ssh -i $K $V
   cd /root/pi-agent && ./set-secret.sh ts_authkey
   ```

4. Start, then empty the spent key:

   ```shell
   docker-compose up -d --build
   docker logs --tail 5 pi-agent                  # look for: Switching ipn state Starting -> Running
   : > secrets/ts_authkey
   ```

5. On your laptop, the new node has a new SSH host key. Clear the stale entry: `ssh-keygen -R pi-agent`, then `ssh pi@pi-agent`.
6. Restore Pi state and workspace from your backup tar if you need it (see Backups).

### D. `/root/pi-agent` deleted from the VPS (files and secrets gone)

1. Copy the files back from the repo (never includes secrets):

   ```shell
   rsync -av --exclude secrets/ -e "ssh -i $K" pi-agent/ $V:/root/pi-agent/
   vps 'chown -R root:root /root/pi-agent'
   ```

2. Recreate **all three** secrets (see "Secrets" below). The GitHub token and OpenRouter key can be re-entered from your password manager, or regenerated if you no longer have them. Do step 1-2 of scenario C for the Tailscale key.
3. Reinstall the firewall unit if it is missing (`systemctl status pi-sandbox-firewall`):

   ```shell
   vps 'cp /root/pi-agent/host/pi-sandbox-firewall.service /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now pi-sandbox-firewall'
   ```

4. `docker-compose up -d --build`, empty `ts_authkey`, verify (below).

### E. VPS rebuilt from scratch

Do the basics from the top-level `README.md` first (Hetzner firewall with only 22/80/443, Docker, docker-compose, Nginx Proxy Manager). Then:

1. Create the Tailscale policy (below) if the Tailnet policy was reset. Delete the old `pi-agent` machine.
2. Follow **scenario D** completely (copy files, secrets, firewall unit, build).
3. Optional swap, as the 2 GiB safety net for the 3.7 GiB host: `vps '/root/pi-agent/host/add-swap.sh'`.
4. Restore volumes from the backup tar if you want Pi state and workspace back.

**Order matters:** the firewall unit should be active **before** the first `docker-compose up`, otherwise the Sandbox briefly has unrestricted access to the Host and other containers.

---

## Secrets

Three files in `/root/pi-agent/secrets/`, created with `set-secret.sh` so values never touch shell history or process arguments:

| File | What | How to get it |
| --- | --- | --- |
| `github_token` | Fine-grained PAT, only the repos the agent may use, Contents R/W and Pull requests R/W, with an expiry. | GitHub → Settings → Developer settings → Fine-grained tokens |
| `openrouter_api_key` | Dedicated key with a spend cap. | OpenRouter → Keys |
| `ts_authkey` | Single-use, tagged `tag:pi-agent`, 1 day expiry. Emptied after the first join. | Tailscale admin → Settings → Keys |

```shell
ssh -i $K $V
cd /root/pi-agent
./set-secret.sh github_token
./set-secret.sh openrouter_api_key
./set-secret.sh ts_authkey
stat -c '%n %U %a %s' secrets/*     # expect owner uid 1000 (shown as UNKNOWN), mode 400
```

`docker-compose up` fails if any of the three files is missing. If you only have some of the tokens yet, create the others as empty files (`touch`, then `chown 1000:1000` and `chmod 400`).

**Rotating or revoking:** revoke at the source (GitHub, OpenRouter) first, then `./set-secret.sh <name>` and `docker-compose restart`. Do this immediately if you suspect the Sandbox was compromised. `docker-compose down -v` also removes any copy of the work inside it.

Secrets are readable by the `pi` user inside the container because the agent needs them. The controls are scope, expiry and a spend cap, not secrecy.

---

## Tailnet policy

Paste `tailscale-policy.hujson` into https://login.tailscale.com/admin/acls/file. It declares `tag:pi-agent`, allows only your members to reach it, and gives the tagged Sandbox **no outbound access** to your other devices. Do not add any rule with `tag:pi-agent` or `*` as the source. Never rely on the default allow-all policy.

## Egress firewall

`host/pi-sandbox-firewall.sh apply|remove|status` blocks the Sandbox subnet (`172.28.0.0/24`) from the Host and from private ranges (10/8, 172.16/12, 192.168/16, 100.64/10, 169.254/16) while keeping general internet access. The systemd unit re-applies it after Docker starts at each boot.

---

## Verify

From the repo root:

```shell
vps 'bash -s' < pi-agent/verify.sh
```

Prints PASS/FAIL for hardening, egress isolation, secret handling and the existing services. Everything under "egress isolation (should all be blocked)" must pass. Also from your laptop:

```shell
for p in 22 80 81 443 8000 9443; do nc -z -w 3 OUR_IP_ADDRESS $p && echo "$p open" || echo "$p filtered"; done
# expect only 22, 80, 443 open
```

## Backups

Add the two Sandbox volumes to the backup command in the top-level `README.md`:

```
/var/lib/docker/volumes/pi-agent_pi-home
/var/lib/docker/volumes/pi-agent_pi-workspace
```

Do not back up `pi-agent_pi-tailscale` or `secrets/`. Re-issue the Tailscale key and re-enter the tokens on recovery. A backup tar containing live tokens is a leak waiting to happen.

## Remove everything

```shell
vps 'cd /root/pi-agent && docker-compose down -v'
vps 'systemctl disable --now pi-sandbox-firewall && rm /etc/systemd/system/pi-sandbox-firewall.service && /root/pi-agent/host/pi-sandbox-firewall.sh remove'
vps 'swapoff /swapfile && rm /swapfile && sed -i "\|^/swapfile |d" /etc/fstab'   # optional
```

Then delete the `pi-agent` machine in the Tailscale admin console, restore your previous policy, and revoke the GitHub and OpenRouter keys.

## Troubleshooting

| Symptom | Likely cause and fix |
| --- | --- |
| `ssh pi@pi-agent` hangs | Tailscale is off on your laptop, or the Sandbox is down. `tailscale status`, `docker ps` on the VPS. |
| `Host key verification failed` | The Sandbox was recreated with a new node key. `ssh-keygen -R pi-agent`. |
| Container restarts, logs show `invalid key` or `NeedsLogin` | The auth key was spent or expired and the `pi-tailscale` volume is empty. Scenario C. |
| `docker-compose up` says a secret file is missing | Create all three files in `secrets/`. |
| Out-of-memory kill of the Sandbox | The limit is 1 GiB. Raise `mem_limit` and `memswap_limit` in `docker-compose.yml` only if the VPS has room (`free -h`). |
| Agent cannot reach a site | Egress is open to the internet but blocked to private ranges. A target inside `10/8`, `172.16/12`, `192.168/16` or `100.64/10` is deliberately unreachable. |
