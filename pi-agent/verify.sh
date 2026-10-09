#!/bin/bash
# Runs on the VPS. Prints PASS/FAIL only; never prints secret values.
x() { docker exec pi-agent bash -c "$1" 2>&1; }
ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; }
expect_blocked() { # label, host, port
  if x "timeout 5 bash -c '</dev/tcp/$2/$3'" >/dev/null 2>&1; then bad "reachable (should be blocked): $1"; else ok "blocked: $1"; fi
}

echo "== container hardening"
[ "$(x 'id -u')" = "1000" ] && ok "runs as uid 1000" || bad "uid"
x 'grep -E "^Cap(Eff|Prm|Bnd)" /proc/self/status' | tr '\n' ' '; echo
[ "$(x 'grep NoNewPrivs /proc/self/status | tr -dc 0-9')" = "1" ] && ok "no-new-privileges" || bad "no-new-privileges"
x 'touch /usr/test 2>&1' | grep -qi "read-only" && ok "rootfs read-only" || bad "rootfs writable"
x 'touch /workspace/.t && rm /workspace/.t' >/dev/null && ok "workspace writable" || bad "workspace"
x 'sudo -n true' >/dev/null 2>&1 && bad "sudo available" || ok "no sudo"
docker inspect pi-agent --format 'privileged={{.HostConfig.Privileged}} netmode={{.HostConfig.NetworkMode}} mem={{.HostConfig.Memory}} cpus={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}} ports={{json .NetworkSettings.Ports}}'
docker inspect pi-agent --format '{{range .Mounts}}{{.Type}}:{{.Source}}->{{.Destination}} {{end}}' | grep -q docker.sock && bad "docker.sock mounted" || ok "no docker.sock"
docker inspect pi-agent --format '{{range .Mounts}}{{.Type}} {{end}}' | grep -q bind && echo "NOTE  bind mounts present (expected: secrets only)" || ok "no bind mounts"

echo "== egress isolation (should all be blocked)"
expect_blocked "host public IP :22" 128.140.2.214 22
expect_blocked "bridge gateway :22" 172.28.0.1 22
expect_blocked "nginx_proxy net 172.19.0.3:80 (NPM)" 172.19.0.3 80
expect_blocked "portainer net 172.18.0.2:9443" 172.18.0.2 9443
expect_blocked "docker0 172.17.0.1:22" 172.17.0.1 22
expect_blocked "Hetzner metadata 169.254.169.254:80" 169.254.169.254 80
echo "== egress allowed (should succeed)"
for u in https://api.github.com https://openrouter.ai https://registry.npmjs.org; do
  c=$(x "curl -s -o /dev/null -m 10 -w %{http_code} $u"); [ "$c" != "000" ] && ok "$u -> $c" || bad "$u"
done

echo "== secrets"
for f in github_token openrouter_api_key ts_authkey; do
  x "stat -c '%n %U %a' /run/secrets/$f"
done
n=$(docker inspect pi-agent | grep -cE 'sk-or-|github_pat_|ghp_|tskey-')
[ "$n" = "0" ] && ok "no token patterns in docker inspect" || bad "token pattern found in docker inspect ($n)"
n=$(docker logs pi-agent 2>&1 | grep -cE 'sk-or-|github_pat_|ghp_|tskey-')
[ "$n" = "0" ] && ok "no token patterns in container logs" || bad "token pattern in logs ($n)"
x 'env | grep -ciE "sk-or-|github_pat_|ghp_|tskey-"' | grep -q '^0$' && ok "no tokens in default shell env" || bad "token in default env"
x 'pi --version' && ok "pi runs" || bad "pi"
x 'git config --system credential.helper'

echo "== existing services"
for p in 3001 3002 3003 3004 3005 3006 5000 5678; do
  printf "127.0.0.1:%s -> " $p; curl -s -o /dev/null -m 8 -w '%{http_code}\n' http://127.0.0.1:$p/
done
docker ps --format '{{.Names}}: {{.Status}}' | grep -v '^pi-agent' | sort
echo "== firewall unit"; systemctl is-active pi-sandbox-firewall
