#!/usr/bin/env bash
#
# renew_virtualizor_ssl.sh
# Usage: renew_virtualizor_ssl.sh <domain> <email>
# Example: sudo ./renew_virtualizor_ssl.sh server4.bdixnode.com support@bdixnode.com
#
# What it does:
#  - checks for socat and acme.sh
#  - stops & masks virtualizor (emps) so port 80/443 are free
#  - issues or forces renewal using acme.sh in standalone mode
#  - installs the cert into /usr/local/virtualizor/conf/
#  - restarts virtualizor and verifies the cert
#  - restores virtualizor enablement
#
set -u
#set -x   # uncomment for debugging

DOMAIN="${1:-server4.bdixnode.com}"
EMAIL="${2:-support@bdixnode.com}"
ACME_SH="/root/.acme.sh/acme.sh"
ACME_DIR="/root/.acme.sh/${DOMAIN}_ecc"
VIRT_CONF="/usr/local/virtualizor/conf"
BACKUP_TS="$(date +%Y%m%d_%H%M%S)"
LOG="/var/log/renew_virtualizor_ssl_${DOMAIN}.log"

exec > >(tee -a "$LOG") 2>&1

echo "=== renew_virtualizor_ssl.sh started: $(date) ==="
echo "Domain: $DOMAIN"
echo "Email:  $EMAIL"
echo "Log:    $LOG"

fail() {
  echo "ERROR: $*" >&2
  echo "Attempting to restore Virtualizor and exit..."
  systemctl unmask virtualizor >/dev/null 2>&1 || true
  systemctl start virtualizor >/dev/null 2>&1 || true
  exit 1
}

# 1) Prereqs: socat & acme.sh
if ! command -v socat >/dev/null 2>&1 ; then
  echo "socat not found. Installing..."
  if [ -f /etc/redhat-release ]; then
    if command -v dnf >/dev/null 2>&1; then dnf install -y epel-release || yum install -y epel-release; fi
    yum install -y socat || dnf install -y socat || fail "Failed to install socat"
  elif [ -f /etc/debian_version ]; then
    apt-get update -y
    apt-get install -y socat || fail "Failed to install socat"
  else
    fail "Unsupported OS: install socat manually"
  fi
fi
echo "socat ok: $(socat -V | head -n1 || true)"

if [ ! -x "$ACME_SH" ]; then
  fail "acme.sh not found at $ACME_SH. Install acme.sh first (https://github.com/acmesh-official/acme.sh)"
fi

# 2) Stop & mask virtualizor to prevent it from auto-restarting emps/nginx
echo "Stopping and masking virtualizor..."
systemctl stop virtualizor || true
systemctl mask virtualizor || true

# kill any stray emps/nginx/php processes (safe cleanup)
pkill -9 -f '/usr/local/emps/sbin/nginx' || true
pkill -9 -f '/usr/local/emps/bin/php' || true
sleep 1

# ensure ports free
if ss -ltnp | egrep ':80|:443' >/dev/null 2>&1; then
  echo "Warning: port 80 or 443 still in use; listing:"
  ss -ltnp | egrep ':80|:443' || true
  fail "Port 80/443 still in use; cannot continue"
fi
echo "Ports 80/443 free."

# 3) Issue or renew certificate
if [ -d "$ACME_DIR" ]; then
  echo "Existing acme.sh data found for $DOMAIN. Forcing renewal..."
  "$ACME_SH" --renew -d "$DOMAIN" --force || fail "acme.sh renewal failed"
else
  echo "Issuing new cert (standalone) for $DOMAIN ..."
  "$ACME_SH" --issue --standalone -d "$DOMAIN" -m "$EMAIL" || fail "acme.sh issue failed"
fi

# verify files exist
if [ ! -f "${ACME_DIR}/fullchain.cer" ] || [ ! -f "${ACME_DIR}/${DOMAIN}.key" ]; then
  echo "Expected cert/key not found in $ACME_DIR"
  ls -la "$ACME_DIR" || true
  fail "Cert generation failed or files missing"
fi

# 4) Backup existing Virtualizor certs
echo "Backing up current Virtualizor certs..."
mkdir -p "${VIRT_CONF}/backup"
cp -a "${VIRT_CONF}/virtualizor.crt" "${VIRT_CONF}/backup/virtualizor.crt.bak.${BACKUP_TS}" 2>/dev/null || true
cp -a "${VIRT_CONF}/virtualizor.key" "${VIRT_CONF}/backup/virtualizor.key.bak.${BACKUP_TS}" 2>/dev/null || true

# 5) Install the new certs using acme.sh install-cert (also registers reload hook)
echo "Installing certs into $VIRT_CONF using acme.sh --install-cert ..."
"$ACME_SH" --install-cert -d "$DOMAIN" \
  --cert-file      "${VIRT_CONF}/virtualizor.crt" \
  --key-file       "${VIRT_CONF}/virtualizor.key" \
  --fullchain-file "${VIRT_CONF}/virtualizor-fullchain.crt" \
  --ca-file        "${VIRT_CONF}/virtualizor-ca.cer" \
  --reloadcmd      "systemctl restart virtualizor" || {
    echo "acme.sh --install-cert failed; attempting manual copy..."
    cp -f "${ACME_DIR}/fullchain.cer" "${VIRT_CONF}/virtualizor.crt" || fail "Failed to copy fullchain"
    cp -f "${ACME_DIR}/${DOMAIN}.key" "${VIRT_CONF}/virtualizor.key" || fail "Failed to copy key"
    cp -f "${ACME_DIR}/ca.cer" "${VIRT_CONF}/virtualizor-ca.cer" || true
  }

# enforce permissions
chmod 600 "${VIRT_CONF}/virtualizor.key" || true
chown root:root "${VIRT_CONF}/virtualizor."* || true

# 6) Unmask & start Virtualizor
echo "Unmasking and starting virtualizor..."
systemctl unmask virtualizor || true
systemctl start virtualizor || fail "Failed to start virtualizor"

sleep 2

# 7) Verify cert served
echo "Verifying certificate being served by server..."
OPENSSL_OUT="$(openssl s_client -connect "${DOMAIN}:443" -servername "${DOMAIN}" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint 2>/dev/null || true)"
echo "openssl check result:"
echo "$OPENSSL_OUT"

if echo "$OPENSSL_OUT" | grep -qi "subject=.*CN = ${DOMAIN}"; then
  echo "SUCCESS: $DOMAIN is serving a certificate for CN=${DOMAIN}"
else
  echo "WARNING: served cert does not appear to match $DOMAIN — check manually"
  ss -ltnp | egrep ':80|:443' || true
  echo "Tail virtualizor logs:"
  journalctl -u virtualizor -n 80 --no-pager || true
fi

echo "=== Done: $(date) ==="
exit 0
