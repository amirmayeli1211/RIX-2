#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Run on a Debian/Ubuntu x86_64 or ARM64 VPN server as root.
if [[ "$(id -u)" -ne 0 ]]; then echo "Run as root: sudo bash install_xray_agent.sh"; exit 1; fi
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ASSET="Xray-linux-64.zip" ;;
  aarch64|arm64) ASSET="Xray-linux-arm64-v8a.zip" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac
apt-get update
apt-get install -y ca-certificates curl unzip python3 python3-venv
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL --retry 3 "https://github.com/XTLS/Xray-core/releases/latest/download/${ASSET}" -o "$TMP_DIR/xray.zip"
unzip -q "$TMP_DIR/xray.zip" -d "$TMP_DIR/unpacked"
id -u rixagent >/dev/null 2>&1 || useradd --system --home /opt/rix-storm-agent --shell /usr/sbin/nologin rixagent
install -d -o rixagent -g rixagent /opt/rix-storm-agent
# Keep the official CLI binary beside the Agent; do not overwrite the existing Xray service binary.
install -m 0755 "$TMP_DIR/unpacked/xray" /opt/rix-storm-agent/xray
chown rixagent:rixagent /opt/rix-storm-agent/xray
install -m 0644 "$SCRIPT_DIR/xray_agent.py" /opt/rix-storm-agent/xray_agent.py
python3 -m venv /opt/rix-storm-agent/venv
/opt/rix-storm-agent/venv/bin/pip install --upgrade pip
/opt/rix-storm-agent/venv/bin/pip install 'fastapi>=0.115,<1.0' 'uvicorn[standard]>=0.34,<1.0'
install -m 0644 "$SCRIPT_DIR/xray-agent.service.example" /etc/systemd/system/rix-storm-agent.service
cat <<'MSG'
Xray binary and Agent source have been installed.
Next steps:
  1) Create /etc/rix-storm-agent.env with XRAY_BIN=/opt/rix-storm-agent/xray, XRAY_API_ADDR, AGENT_TOKEN, AGENT_PORT_START and AGENT_PORT_END.
  2) Configure the running Xray-core instance with its API listening only on 127.0.0.1:10085 and HandlerService.
  3) Configure a valid HTTPS reverse proxy for the Agent (see Caddyfile.example).
  4) Review /etc/systemd/system/rix-storm-agent.service and its security settings.
  5) Enable and start the Agent only after reviewing permissions and your server's existing Xray configuration.
Do not expose Xray's gRPC API directly to the public internet.
MSG
