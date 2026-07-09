#!/usr/bin/env bash
# certbot manual-auth-hook for GoDaddy DNS-01. Publishes the _acme-challenge
# TXT record via GoDaddy's API so cert issuance/renewal is fully unattended.
# certbot passes $CERTBOT_DOMAIN and $CERTBOT_VALIDATION.
set -euo pipefail

CREDS="${GODADDY_CREDS:-/home/braap/EEAccess/server/godaddy.env}"
# shellcheck disable=SC1090
source "$CREDS"   # GODADDY_KEY, GODADDY_SECRET, GODADDY_DOMAIN

# subdomain relative to the GoDaddy zone (e.g. eeaccess), then the record name
SUB="${CERTBOT_DOMAIN%".$GODADDY_DOMAIN"}"
NAME="_acme-challenge${SUB:+.$SUB}"

curl -sS -X PUT \
  "https://api.godaddy.com/v1/domains/${GODADDY_DOMAIN}/records/TXT/${NAME}" \
  -H "Authorization: sso-key ${GODADDY_KEY}:${GODADDY_SECRET}" \
  -H "Content-Type: application/json" \
  -d "[{\"data\":\"${CERTBOT_VALIDATION}\",\"ttl\":600}]" >/dev/null

# Give GoDaddy time to propagate before certbot asks Let's Encrypt to validate.
sleep 45
