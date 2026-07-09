#!/usr/bin/env bash
# certbot manual-cleanup-hook for GoDaddy DNS-01. Overwrites the challenge TXT
# with a placeholder after validation (GoDaddy's API has no clean single-record
# delete; a placeholder is harmless).
set -euo pipefail

CREDS="${GODADDY_CREDS:-/home/braap/EEAccess/server/godaddy.env}"
# shellcheck disable=SC1090
source "$CREDS"

SUB="${CERTBOT_DOMAIN%".$GODADDY_DOMAIN"}"
NAME="_acme-challenge${SUB:+.$SUB}"

curl -sS -X PUT \
  "https://api.godaddy.com/v1/domains/${GODADDY_DOMAIN}/records/TXT/${NAME}" \
  -H "Authorization: sso-key ${GODADDY_KEY}:${GODADDY_SECRET}" \
  -H "Content-Type: application/json" \
  -d '[{"data":"acme-cleaned","ttl":600}]' >/dev/null || true
