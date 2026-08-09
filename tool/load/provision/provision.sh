#!/usr/bin/env bash
# Ephemeral two-machine rig for scale tests (docs/LOAD_PROVISIONING.md).
#
# Creates two hourly-billed Hetzner Cloud ARM VMs — a target (app +
# postgres) and a load generator (k6) — runs are manual via ssh, and
# `down` destroys everything so cost stops accruing. A full evidence
# session (matrix + spike) is ~2-3 machine-hours ≈ well under EUR 0.10;
# a 4-hour soak on both boxes stays under ~EUR 0.20 at CAX rates.
#
# Requirements: hcloud CLI (https://github.com/hetznercloud/cli) with
# HCLOUD_TOKEN set, and an ssh key already registered in the project
# (name in HCLOUD_SSH_KEY).
#
# Usage:
#   HCLOUD_SSH_KEY=me ./provision.sh up [branch]   # create + bootstrap
#   ./provision.sh ips                             # print IPs
#   ./provision.sh down                            # destroy both VMs
set -euo pipefail

TARGET_NAME="${TARGET_NAME:-conduit-load-target}"
LOADGEN_NAME="${LOADGEN_NAME:-conduit-load-gen}"
# CAX = Ampere ARM, the post-June-2026 value line. cax31: 8 vCPU / 16 GB
# for the target (app + DB), cax21: 4 vCPU / 8 GB for the generator.
TARGET_TYPE="${TARGET_TYPE:-cax31}"
LOADGEN_TYPE="${LOADGEN_TYPE:-cax21}"
LOCATION="${LOCATION:-fsn1}"
IMAGE="${IMAGE:-debian-12}"
REPO_URL="${REPO_URL:-https://github.com/conduit-dart/conduit.git}"
K6_VERSION="${K6_VERSION:-v1.1.0}"

ip_of() { hcloud server ip "$1"; }

cmd_up() {
  local branch="${1:-master}"

  for spec in "${TARGET_NAME}:${TARGET_TYPE}" "${LOADGEN_NAME}:${LOADGEN_TYPE}"; do
    hcloud server create \
      --name "${spec%%:*}" --type "${spec##*:}" \
      --image "${IMAGE}" --location "${LOCATION}" \
      --ssh-key "${HCLOUD_SSH_KEY}"
  done

  local target_ip loadgen_ip
  target_ip="$(ip_of "${TARGET_NAME}")"
  loadgen_ip="$(ip_of "${LOADGEN_NAME}")"

  echo "waiting for ssh..."
  for ip in "${target_ip}" "${loadgen_ip}"; do
    until ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 \
      "root@${ip}" true 2>/dev/null; do sleep 3; done
  done

  echo "=== bootstrapping target (${target_ip}) ==="
  ssh "root@${target_ip}" bash -s <<EOF
set -euo pipefail
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  git curl ca-certificates apt-transport-https gnupg docker.io
# Dart SDK (official apt repo, has linux-arm64 builds)
curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub \
  | gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' \
  > /etc/apt/sources.list.d/dart_stable.list
apt-get update -qq && apt-get install -y -qq dart
export PATH="\$PATH:/usr/lib/dart/bin"
docker run -d --name pg -p 15432:5432 \
  -e POSTGRES_USER=conduit_test_user -e POSTGRES_PASSWORD='conduit!' \
  -e POSTGRES_DB=conduit_test_db postgres:18
git clone --depth 1 -b "${branch}" "${REPO_URL}" /opt/conduit
cd /opt/conduit && dart pub get
echo "target ready. start the app with e.g.:"
echo "  cd /opt/conduit/tool/load/target && ISOLATES=2 POOL_SIZE=8 \\"
echo "  dart run --enable-vm-service=8181 --disable-service-auth-codes bin/main.dart"
EOF

  echo "=== bootstrapping load generator (${loadgen_ip}) ==="
  ssh "root@${loadgen_ip}" bash -s <<EOF
set -euo pipefail
apt-get update -qq
apt-get install -y -qq --no-install-recommends git curl ca-certificates
curl -fsSL "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-arm64.tar.gz" \
  | tar -xz -C /tmp
install -m 0755 "/tmp/k6-${K6_VERSION}-linux-arm64/k6" /usr/local/bin/k6
git clone --depth 1 -b "${branch}" "${REPO_URL}" /opt/conduit
echo "loadgen ready. run e.g.:"
echo "  k6 run --tag pool=8 --tag isolates=2 -e TARGET=http://${target_ip}:8888 \\"
echo "  -e RATE=100 -e DURATION=5m /opt/conduit/tool/load/k6/pooling_baseline.js"
EOF

  echo ""
  echo "target:  ${target_ip}   loadgen: ${loadgen_ip}"
  echo "REMEMBER: ./provision.sh down when finished — billing is hourly."
}

cmd_ips() {
  echo "target:  $(ip_of "${TARGET_NAME}")"
  echo "loadgen: $(ip_of "${LOADGEN_NAME}")"
}

cmd_down() {
  for name in "${TARGET_NAME}" "${LOADGEN_NAME}"; do
    hcloud server delete "${name}" || true
  done
}

case "${1:-}" in
  up) shift; cmd_up "$@" ;;
  ips) cmd_ips ;;
  down) cmd_down ;;
  *) echo "usage: provision.sh up [branch] | ips | down" >&2; exit 64 ;;
esac
