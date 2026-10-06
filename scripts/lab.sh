#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

mapfile -t nodes < <(docker compose config --services | sort)

keys() {
  mkdir -p keys
  [[ -f keys/id_ed25519 ]] || ssh-keygen -q -t ed25519 -N '' -C vpslab -f keys/id_ed25519
}

trust() {
  local n port ip hostkey
  : >keys/known_hosts.tmp
  : >keys/ssh_config.tmp
  for n in "${nodes[@]}"; do
    port=$(docker port "$n" 22/tcp | head -1 | cut -d: -f2)
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$n")
    hostkey=$(docker exec "$n" cut -d' ' -f1,2 /etc/ssh/ssh_host_ed25519_key.pub)
    printf '[127.0.0.1]:%s %s\n%s %s\n' "$port" "$hostkey" "$ip" "$hostkey" >>keys/known_hosts.tmp
    cat >>keys/ssh_config.tmp <<CONF
Host $n
  HostName 127.0.0.1
  Port $port
  User deploy
  IdentityFile $PWD/keys/id_ed25519
  IdentitiesOnly yes
  UserKnownHostsFile $PWD/keys/known_hosts
  StrictHostKeyChecking yes

CONF
  done
  mv keys/known_hosts.tmp keys/known_hosts
  mv keys/ssh_config.tmp keys/ssh_config
}

check() {
  local n failed=0
  for n in "${nodes[@]}"; do
    if ssh -n -F keys/ssh_config -o BatchMode=yes -o ConnectTimeout=5 "$n" \
      "test \"\$(hostname)\" = $n && systemctl is-system-running --wait >/dev/null && sudo -n true"; then
      echo "$n  ok"
    else
      echo "$n  FAIL"
      failed=$((failed + 1))
    fi
  done
  return "$failed"
}

"$@"
