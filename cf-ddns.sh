#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Cloudflare DDNS - IPv4 (A Record)
# IP source: curl ip.sb
#
# 用法：
#   sudo bash cf-ddns.sh install    # 交互式安装并启用自启动
#   sudo bash cf-ddns.sh run        # 立即执行一次 DDNS 更新
#   sudo bash cf-ddns.sh uninstall  # 卸载
#
# 依赖：
#   - bash
#   - curl
#   - systemd
# =========================================================

SCRIPT_PATH="/usr/local/bin/cf-ddns.sh"
CONF_PATH="/etc/cf-ddns.conf"
SERVICE_PATH="/etc/systemd/system/cf-ddns.service"
TIMER_PATH="/etc/systemd/system/cf-ddns.timer"

API="https://api.cloudflare.com/client/v4"
UA="cf-ddns/1.0"
RECORD_TYPE="A"

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "❌ 请使用 root 权限运行（sudo）"
    exit 1
  fi
}

has_systemd() {
  command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

prompt() {
  local var="$1" msg="$2" secret="${3:-no}" default="${4:-}"
  local input=""
  if [[ "$secret" == "yes" ]]; then
    read -r -s -p "$msg: " input
    echo
  else
    if [[ -n "$default" ]]; then
      read -r -p "$msg（默认：$default）: " input
      input="${input:-$default}"
    else
      read -r -p "$msg: " input
    fi
  fi
  printf -v "$var" "%s" "$input"
}

get_public_ipv4() {
  local ip
  ip="$(curl -fsS ip.sb | tr -d ' \n\r\t')"
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "$ip"
    return 0
  fi
  echo "❌ 无法从 ip.sb 获取公网 IPv4（返回：$ip）" >&2
  return 1
}

cf_api() {
  local method="$1"; shift
  local url="$1"; shift
  curl -fsS -X "$method" "$url" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: ${UA}" \
    "$@"
}

json_get() {
  local json="$1" field="$2"
  echo "$json" | sed -n "s/.*\"${field}\":[ ]*\"\([^\"]*\)\".*/\1/p" | head -n1
}

load_config() {
  if [[ ! -f "$CONF_PATH" ]]; then
    echo "❌ 配置文件不存在，请先运行 install"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$CONF_PATH"
}

run_ddns() {
  load_config

  local ip
  ip="$(get_public_ipv4)"
  echo "[*] 当前公网 IPv4：$ip"

  local query_url="${API}/zones/${CF_ZONE_ID}/dns_records?type=${RECORD_TYPE}&name=${CF_RECORD_NAME}"
  local resp
  resp="$(cf_api GET "$query_url")"

  local success
  success="$(json_get "$resp" "success")"
  [[ "$success" == "true" ]] || { echo "❌ 查询 DNS 失败"; exit 1; }

  local record_id
  record_id="$(json_get "$resp" "id")"
  [[ -n "$record_id" ]] || { echo "❌ DNS 记录不存在：$CF_RECORD_NAME"; exit 1; }

  local current_ip
  current_ip="$(echo "$resp" | sed -n 's/.*"content":"\([^"]*\)".*/\1/p' | head -n1)"
  echo "[*] Cloudflare 当前 IP：$current_ip"

  if [[ "$current_ip" == "$ip" ]]; then
    echo "[=] IP 未变化，跳过更新"
    exit 0
  fi

  local data
  data="$(cat <<EOF
{
  "type": "A",
  "name": "${CF_RECORD_NAME}",
  "content": "${ip}",
  "ttl": ${CF_TTL},
  "proxied": ${CF_PROXIED}
}
EOF
)"

  cf_api PUT "${API}/zones/${CF_ZONE_ID}/dns_records/${record_id}" --data "$data" >/dev/null
  echo "[+] DNS 更新成功：${CF_RECORD_NAME} → $ip"
}

install_ddns() {
  require_root

  has_systemd || { echo "❌ 系统不支持 systemd"; exit 1; }

  echo "=== Cloudflare DDNS 交互式安装 ==="
  echo "IP 获取方式：curl ip.sb"
  echo

  local CF_API_TOKEN CF_ZONE_ID CF_RECORD_NAME CF_TTL CF_PROXIED
  prompt CF_API_TOKEN "请输入 Cloudflare API Token（不回显）" yes
  prompt CF_ZONE_ID "请输入 Zone ID"
  prompt CF_RECORD_NAME "请输入 DNS 记录名（如 home.example.com）"
  prompt CF_TTL "TTL（1 = 自动）" no "1"
  prompt CF_PROXIED "是否启用代理（true/false）" no "false"

  install -m 755 "$0" "$SCRIPT_PATH"

  umask 077
  cat > "$CONF_PATH" <<EOF
CF_API_TOKEN="${CF_API_TOKEN}"
CF_ZONE_ID="${CF_ZONE_ID}"
CF_RECORD_NAME="${CF_RECORD_NAME}"
CF_TTL="${CF_TTL}"
CF_PROXIED="${CF_PROXIED}"
EOF
  chmod 600 "$CONF_PATH"

  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Cloudflare DDNS Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SCRIPT_PATH} run
EOF

  cat > "$TIMER_PATH" <<EOF
[Unit]
Description=Cloudflare DDNS Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now cf-ddns.timer

  echo
  echo "✅ 安装完成！"
  echo "- 配置文件：$CONF_PATH"
  echo "- 定时更新：每 5 分钟"
  echo
  echo "手动测试："
  echo "  sudo $SCRIPT_PATH run"
}

uninstall_ddns() {
  require_root
  systemctl disable --now cf-ddns.timer >/dev/null 2>&1 || true
  rm -f "$TIMER_PATH" "$SERVICE_PATH" "$CONF_PATH" "$SCRIPT_PATH"
  systemctl daemon-reload || true
  echo "🧹 已卸载 Cloudflare DDNS"
}

case "${1:-}" in
  install) install_ddns ;;
  run) run_ddns ;;
  uninstall) uninstall_ddns ;;
  *)
    echo "用法："
    echo "  sudo bash cf-ddns.sh install    # 安装并启用自启动"
    echo "  sudo bash cf-ddns.sh run        # 立即执行一次"
    echo "  sudo bash cf-ddns.sh uninstall  # 卸载"
    ;;
esac
