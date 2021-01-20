#!/usr/bin/env bash
set -ex
shopt -s nullglob

#shellcheck source=/dev/null
source ~/service-env.sh

~/bin/check-hostname.sh

# Delete any zero-length snapshots that can cause validator startup to fail
find ~/ledger/ -name 'snapshot-*' -size 0 -print -exec rm {} \; || true

#shellcheck source=/dev/null
source ~/service-env.sh

identity_keypair=~/validator-keypair.json
identity_pubkey=$(solana-keygen pubkey "$identity_keypair")

authorized_voter_args=()
for av in ~/vote-account-keypair.json; do
  authorized_voter_args+=(--authorized-voter "$av")
done

trusted_validator_args=()
for tv in "${TRUSTED_VALIDATOR_PUBKEYS[@]}"; do
  [[ $tv = "$identity_pubkey" ]] || trusted_validator_args+=(--trusted-validator "$tv")
done

if [[ ${#trusted_validator_args[@]} -gt 0 ]]; then
  trusted_validator_args+=(--halt-on-trusted-validators-accounts-hash-mismatch)
  trusted_validator_args+=(--no-untrusted-rpc)
fi

frozen_accounts=()
if [[ -r ~/frozen-accounts ]]; then
  #
  # The frozen-accounts file should be formatted as:
  #   FROZEN_ACCOUNT_PUBKEYS=()
  #   FROZEN_ACCOUNT_PUBKEYS+=(PUBKEY1)
  #   FROZEN_ACCOUNT_PUBKEYS+=(PUBKEY2)
  #

  #shellcheck source=/dev/null
  . ~/frozen-accounts
  for tv in "${FROZEN_ACCOUNT_PUBKEYS[@]}"; do
    frozen_accounts+=(--frozen-account "$tv")
  done
fi



args=(
  --dynamic-port-range 8002-8015
#  --gossip-port 8001
  --identity "$identity_keypair"
  --ledger /data/ledger
  --limit-ledger-size 50000000
  --log /data/logs/solana-validator.log
  --rpc-port 8899
  --vote-account your-vote-account-pub-key
  --accounts /mnt/ramdisk
#  --enable-rpc-transaction-history
#  --no-snapshot-fetch # do not download snapshots. remove if rebuilding takes too long
#  --snapshot-compression none
#  --account-shrink-path /data/ledger/accounts-shrink # <-- SSD
  --expected-genesis-hash "$EXPECTED_GENESIS_HASH"
  --expected-shred-version "$EXPECTED_SHRED_VERSION"
  --private-rpc
#  --no-voting
#  --cuda
#  "${authorized_voter_args[@]}"
  "${trusted_validator_args[@]}"
  "${frozen_accounts[@]}"
  --wal-recovery-mode skip_any_corrupted_record
)

if [[ -n "$EXPECTED_BANK_HASH" ]]; then
  args+=(--expected-bank-hash "$EXPECTED_BANK_HASH")
  if [[ -n "$WAIT_FOR_SUPERMAJORITY" ]]; then
    args+=(--wait-for-supermajority "$WAIT_FOR_SUPERMAJORITY")
  fi
elif [[ -n "$WAIT_FOR_SUPERMAJORITY" ]]; then
  echo "WAIT_FOR_SUPERMAJORITY requires EXPECTED_BANK_HASH be specified as well!" 1>&2
  exit 1
fi

if [[ -n $GOSSIP_HOST ]]; then
  args+=(--gossip-host "$GOSSIP_HOST")
else
  args+=(--entrypoint "$ENTRYPOINT")
fi

exec solana-validator "${args[@]}"
