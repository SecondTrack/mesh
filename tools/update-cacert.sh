#!/bin/sh
# update-cacert.sh — Mozilla-CA-Bundle erneuern (Quelle: Homebrew ca-certificates) und prüfen,
# dass jedes Relay aus MeshSession damit verifizierbar ist. Ohne Argument nur prüfen.
#   tools/update-cacert.sh          prüfen
#   tools/update-cacert.sh update   Bundle ersetzen, dann prüfen
set -e
cd "$(dirname "$0")/.."
SRC=$(brew --prefix)/etc/ca-certificates/cert.pem
if [ "$1" = update ]; then cp "$SRC" Resources/cacert.pem; echo "Bundle ersetzt ($(grep -c 'BEGIN CERT' Resources/cacert.pem) Wurzeln)"; fi
fail=0
for host in $(grep -o 'wss://[a-z0-9.-]*' mesh/Domain/MeshSession.m | sed 's#wss://##'); do
  out=$(echo | /usr/bin/openssl s_client -connect "$host:443" -servername "$host" -CAfile Resources/cacert.pem 2>/dev/null)
  chain=$(echo "$out" | grep 'Verify return code')
  san=$(echo "$out" | /usr/bin/openssl x509 -noout -text 2>/dev/null | grep -A1 'Subject Alternative Name' | tail -1)
  wild="*.${host#*.}"
  case ", $san," in *"DNS:$host,"*|*"DNS:$wild,"*) name=ok ;; *) name=FEHLT ;; esac
  echo "$host: $chain, Hostname $name"
  case "$chain/$name" in *"0 (ok)"*/ok) ;; *) fail=1 ;; esac
done
exit $fail
