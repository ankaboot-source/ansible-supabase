#!/bin/sh
# Generate secrets and write them directly into env/supabase.yml
# Usage:
#   sh generate-keys.sh           # generate (refuses if env is locked)
#   sh generate-keys.sh --force   # regenerate even if env is locked
#
# Locking: if env/.setup.lock exists, this script refuses to run unless
# --force is passed — regenerating secrets breaks running Supabase services
# that were configured with the old keys (issue #127).

set -e

FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help)
      echo "Usage: sh generate-keys.sh [--force]"
      echo "  --force   Regenerate secrets even if env/.setup.lock exists"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

LOCK_FILE="env/.setup.lock"
if [ -f "$LOCK_FILE" ] && [ "$FORCE" -eq 0 ]; then
  echo "error: env is locked ($LOCK_FILE exists)." >&2
  echo "       Regenerating secrets would break running Supabase services." >&2
  echo "       Re-run with --force to override:" >&2
  echo "         sh generate-keys.sh --force" >&2
  exit 1
fi

gen_hex()    { openssl rand -hex "$1"; }
gen_b64()    { openssl rand -base64 "$1"; }
b64url()     { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
gen_jwt()    {
  header='{"alg":"HS256","typ":"JWT"}'
  payload=$1
  hdr=$(printf '%s' "$header" | b64url)
  pld=$(printf '%s' "$payload" | b64url)
  sig=$(printf '%s' "$hdr.$pld" | openssl dgst -binary -sha256 -hmac "$jwt_secret" | b64url)
  echo "$hdr.$pld.$sig"
}

jwt_secret=$(gen_b64 30)
iat=$(date +%s)
exp=$((iat + 157680000)) # 5 years

anon_key=$(gen_jwt "{\"role\":\"anon\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")
service_role_key=$(gen_jwt "{\"role\":\"service_role\",\"iss\":\"supabase\",\"iat\":$iat,\"exp\":$exp}")

sed -i "s|^postgres_db_pwd:.*|postgres_db_pwd: $(gen_hex 16)|" env/supabase.yml
sed -i "s|^sb_jwt_secret:.*|sb_jwt_secret: $jwt_secret|" env/supabase.yml
sed -i "s|^sb_anon_key:.*|sb_anon_key: $anon_key|" env/supabase.yml
sed -i "s|^sb_service_role_key:.*|sb_service_role_key: $service_role_key|" env/supabase.yml
sed -i "s|^secret_key_base:.*|secret_key_base: $(gen_b64 48)|" env/supabase.yml
sed -i "s|^vault_enc_key:.*|vault_enc_key: $(gen_hex 16)|" env/supabase.yml
sed -i "s|^pg_meta_crypto_key:.*|pg_meta_crypto_key: $(gen_b64 24)|" env/supabase.yml
sed -i "s|^logflare_public_access_token:.*|logflare_public_access_token: $(gen_b64 24)|" env/supabase.yml
sed -i "s|^logflare_private_access_token:.*|logflare_private_access_token: $(gen_b64 24)|" env/supabase.yml
sed -i "s|^s3_protocol_access_key_id:.*|s3_protocol_access_key_id: $(gen_hex 16)|" env/supabase.yml
sed -i "s|^s3_protocol_access_key_secret:.*|s3_protocol_access_key_secret: $(gen_hex 32)|" env/supabase.yml

echo "env/supabase.yml updated with fresh secrets"