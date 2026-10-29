#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '  [OK]   %s\n' "$desc"
        ((PASS+=1))
    else
        printf "  [FAIL] %s (expected: '%s', actual: '%s')\n" "$desc" "$expected" "$actual"
        ((FAIL+=1))
    fi
}

printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%Y-%m-%d %H:%M')"
echo '[1] SSH service'
SSH_CONFIG=$(sudo /usr/sbin/sshd -T) || exit 1
check 'Root login disabled' no "$(awk '/^permitrootlogin / {print $2}' <<< "$SSH_CONFIG")"
check 'Password authentication disabled' no "$(awk '/^passwordauthentication / {print $2}' <<< "$SSH_CONFIG")"
SSH_PORTS=$(awk '/^port / {print $2}' <<< "$SSH_CONFIG")
NONSTANDARD=yes
if [[ -z "$SSH_PORTS" ]] || grep -qx '22' <<< "$SSH_PORTS"; then NONSTANDARD=no; fi
check 'SSH uses a nonstandard port' yes "$NONSTANDARD"
check 'MaxAuthTries equals 3' 3 "$(awk '/^maxauthtries / {print $2}' <<< "$SSH_CONFIG")"

echo '[2] Firewall'
UFW_STATUS=$(sudo ufw status verbose) || exit 1
check 'Firewall active' active "$(awk '/^Status:/ {print $2}' <<< "$UFW_STATUS")"
check 'Default incoming policy is deny' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$UFW_STATUS")"

echo '[3] User accounts'
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd
echo '[4] Web server'
check 'Nginx active' active "$(systemctl is-active nginx)"
NGINX_TEST=no
if sudo nginx -t >/dev/null 2>&1; then NGINX_TEST=yes; fi
check 'Nginx configuration valid' yes "$NGINX_TEST"
CERT_VALID=no
if openssl x509 -checkend 2592000 -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then CERT_VALID=yes; fi
check 'Certificate valid for at least 30 days' yes "$CERT_VALID"
SAFE_PERMISSIONS=no
if [[ -d /var/www/devops-site ]] && \
   [[ -z $(sudo find /var/www/devops-site -perm -o+w -print) ]] && \
   [[ $(sudo stat -c %a /etc/ssl/private/devops.key) == 600 ]]; then
    SAFE_PERMISSIONS=yes
fi
check 'Site not world-writable and TLS key mode 600' yes "$SAFE_PERMISSIONS"
echo '[5] Containerization'
check 'Docker active' active "$(systemctl is-active docker)"
check 'Database container healthy' healthy "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null)"
PRIVATE_PORTS=no
if SOCKETS=$(ss -H -ltn); then
    PRIVATE_PORTS=$(awk '$4 ~ /:(5000|5432)$/ && $4 !~ /^127[.]0[.]0[.]1:/ {bad=1} END {print bad ? "no" : "yes"}' <<< "$SOCKETS")
fi
check 'App and DB ports bound only to 127.0.0.1' yes "$PRIVATE_PORTS"
APP_DIR=${APP_DIR:-/home/devops/app}
check 'Application env file mode 600' 600 "$(stat -c '%a' "$APP_DIR/.env" 2>/dev/null)"
printf 'Passed: %s, failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
