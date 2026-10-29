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
printf 'Passed: %s, failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
