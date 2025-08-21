#!/usr/bin/env bash
# ICMP Tunnel Manager by Hossein.IT
# Features: interactive menu, auto NIC detection, systemd persistence, NAT, cleanup
# Tested on: Ubuntu 20.04/22.04/24.04

set -euo pipefail

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
RESET="\e[0m"

CONF_FILE="/etc/icmptunnel.conf"
INSTALL_DIR="/opt/icmptunnel"
SERVICE_NAME="icmptunnel"
SYSCTL_FILE="/etc/sysctl.d/99-icmp-tunnel.conf"

# Detect primary network interface (internet-facing)
detect_iface() {
  local iface
  iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
  if [[ -z "${iface:-}" ]]; then
    iface=$(ip -o link show | awk -F': ' '/state UP/ {print $2; exit}')
  fi
  echo "${iface:-eth0}"
}

NET_IFACE="$(detect_iface)"

banner() {
  echo -e "${CYAN}"
  echo "========================================="
  echo "   Hossein.IT - ICMP Tunnel Manager      "
  echo "========================================="
  echo -e "${RESET}"
}

pause() {
  read -rp "ادامه با Enter..." _ || true
}

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[!] لطفاً اسکریپت را با sudo اجرا کنید.${RESET}"
    exit 1
  fi
}

install_common() {
  echo -e "${GREEN}[+] نصب پیش‌نیازها...${RESET}"
  apt update -y
  DEBIAN_FRONTEND=noninteractive apt install -y git build-essential iproute2 iptables
  if [[ ! -d "$INSTALL_DIR" ]]; then
    git clone https://github.com/DhavalKapil/icmptunnel.git "$INSTALL_DIR"
  fi
  make -C "$INSTALL_DIR"
}

iptables_has_rule() {
  iptables -t nat -C POSTROUTING -o "$NET_IFACE" -j MASQUERADE >/dev/null 2>&1
}

add_nat_rule() {
  if ! iptables_has_rule; then
    iptables -t nat -A POSTROUTING -o "$NET_IFACE" -j MASQUERADE
  fi
}

remove_nat_rule() {
  if iptables_has_rule; then
    iptables -t nat -D POSTROUTING -o "$NET_IFACE" -j MASQUERADE || true
  fi
}

persist_ip_forward_on() {
  echo "net.ipv4.ip_forward=1" > "$SYSCTL_FILE"
  sysctl --system >/dev/null
}

persist_ip_forward_off() {
  rm -f "$SYSCTL_FILE"
  sysctl --system >/dev/null 2>&1 || true
}

create_server_service() {
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=ICMP Tunnel Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/icmptunnel -s
Restart=always
RestartSec=2
# Configure tun0 & NAT after the daemon starts
ExecStartPost=/bin/sh -c 'ip addr replace 10.0.0.1/24 dev tun0; ip link set tun0 up'
ExecStartPost=/bin/sh -c 'iptables -t nat -C POSTROUTING -o ${NET_IFACE} -j MASQUERADE || iptables -t nat -A POSTROUTING -o ${NET_IFACE} -j MASQUERADE'

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
}

create_client_service() {
  cat >"/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=ICMP Tunnel Client
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$CONF_FILE
ExecStart=${INSTALL_DIR}/icmptunnel \$SERVER_IP
Restart=always
RestartSec=2
# Configure tun0 & default route after the daemon starts
ExecStartPost=/bin/sh -c 'ip addr replace 10.0.0.2/24 dev tun0; ip link set tun0 up'
ExecStartPost=/bin/sh -c 'ip route replace default via 10.0.0.1 dev tun0'

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
}

start_service() {
  systemctl restart "${SERVICE_NAME}"
  sleep 2
  systemctl --no-pager --full status "${SERVICE_NAME}" || true
}

stop_disable_service() {
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
}

set_server_ip() {
  read -rp "IP kharej: " SERVER_IP
  if [[ -z "${SERVER_IP}" ]]; then
    echo -e "${RED}[!] IP نامعتبر.${RESET}"; exit 1
  fi
  echo "SERVER_IP=${SERVER_IP}" > "$CONF_FILE"
  echo -e "${GREEN}[✓] IP در ${CONF_FILE} ذخیره شد.${RESET}"
}

setup_server() {
  install_common
  persist_ip_forward_on
  add_nat_rule
  create_server_service
  start_service
  echo -e "${GREEN}سرور خارج آماده و سرویس پایدار شد ✅${RESET}"
  echo -e "${YELLOW}اینترفیس اینترنت تشخیص‌داده‌شده: ${NET_IFACE}${RESET}"
}

setup_client() {
  install_common
  if [[ ! -f "$CONF_FILE" ]]; then
    set_server_ip
  fi
  create_client_service
  start_service
  echo -e "${GREEN}سرور ایران آماده و سرویس پایدار شد ✅${RESET}"
}

remove_tunnel() {
  echo -e "${RED}[!] حذف کامل تونل و پاکسازی...${RESET}"
  stop_disable_service
  pkill -x icmptunnel 2>/dev/null || true
  ip link set tun0 down 2>/dev/null || true
  ip route del default via 10.0.0.1 dev tun0 2>/dev/null || true
  remove_nat_rule
  persist_ip_forward_off
  echo -e "${GREEN}[✓] پاکسازی انجام شد.${RESET}"
}

main_menu() {
  banner
  echo -e "${YELLOW}لطفاً گزینه را انتخاب کنید:${RESET}"
  echo "1) نصب و راه‌اندازی سرور ایران (Client)"
  echo "2) نصب و راه‌اندازی سرور آلمان (Server)"
  echo "3) وارد کردن/تغییر IP سرور خارج"
  echo "4) حذف تونل و پاکسازی"
  echo "5) نمایش وضعیت سرویس"
  echo "6) خروج"
  read -rp "انتخاب شما: " choice
  case "${choice}" in
    1) ensure_root; setup_client;;
    2) ensure_root; setup_server;;
    3) ensure_root; set_server_ip;;
    4) ensure_root; remove_tunnel;;
    5) systemctl status "${SERVICE_NAME}" --no-pager || true;;
    6) exit 0;;
    *) echo -e "${RED}گزینه نامعتبر.${RESET}";;
  esac
}

main_menu
