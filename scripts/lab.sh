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


# shellcheck disable=SC2016 # remote commands expand on the node
smoke() {
  local n failed=0 ids=() peers
  remote() { ssh -n -F keys/ssh_config -o BatchMode=yes -o ConnectTimeout=5 "$@"; }
  expect() {
    local name=$1
    shift
    if "$@" >/dev/null 2>&1; then
      echo "PASS  $name"
    else
      echo "FAIL  $name"
      failed=$((failed + 1))
    fi
  }

  echo "docker $(docker version -f '{{.Server.Version}}'), compose $(docker compose version --short), kernel $(uname -r)"
  for n in "${nodes[@]}"; do
    peers=$(printf '%s ' "${nodes[@]/$n/}")
    expect "$n systemd is PID 1" remote "$n" 'test "$(ps -p 1 -o comm=)" = systemd'
    expect "$n systemd running, 0 failed units" remote "$n" 'systemctl is-system-running --wait'
    expect "$n hostname" remote "$n" "test \"\$(hostname)\" = $n"
    expect "$n deploy has sudo" remote "$n" 'sudo -n true'
    expect "$n root key login" remote "root@$n" true
    expect "$n password login refused" bash -c "! ssh -n -F keys/ssh_config -o BatchMode=yes -o PubkeyAuthentication=no $n true"
    expect "$n reaches peers on :22" remote "$n" "for p in $peers; do timeout 2 bash -c \"</dev/tcp/\$p/22\" || exit 1; done"
    expect "$n services start like on a VPS" remote "$n" 'test ! -e /usr/sbin/policy-rc.d && systemctl is-active -q cron'
    expect "$n unit sandboxing applies" remote "$n" 'test "$(sudo readlink /proc/1/ns/mnt)" != "$(sudo systemd-run --wait --pipe --quiet -p PrivateTmp=yes readlink /proc/self/ns/mnt)"'
    expect "$n cannot set the host clock" remote "$n" 'b=$(awk "/^CapBnd/{print \$2}" /proc/1/status); test $(((0x$b >> 25) & 1)) -eq 0'
    expect "$n sees no block devices" remote "$n" 'test -z "$(find /dev -type b)"'
    expect "$n memory is capped" remote "$n" 'test "$(cat /sys/fs/cgroup/memory.max)" != max'
    ids+=("$(remote "$n" cat /etc/machine-id)")
  done
  expect "machine-ids are unique" test "$(printf '%s\n' "${ids[@]}" | sort -u | wc -l)" -eq "${#nodes[@]}"
  expect "host keys are unique" test "$(awk '{print $3}' keys/known_hosts | sort -u | wc -l)" -eq "${#nodes[@]}"

  echo "$failed failed"
  return "$failed"
}

"$@"
