#!/bin/sh
# Verifies a DaGym-generated .pkpass on a Mac: unzips it, recomputes every manifest.json SHA-1,
# and checks the detached CMS `signature` over manifest.json against the Apple WWDR G4
# intermediate (Configs/wallet/wwdr.pem, or the copy bundled in the app) chained to the Apple
# Root CA (downloaded once into ~/.dagym-tools/ if absent).
#
#   scripts/verify-pass.sh path/to/card.pkpass
#
# Export a pass from a device: Wallet → the pass → "…" → Share, or AirDrop it from the add sheet.
set -eu

pass="${1:?usage: scripts/verify-pass.sh <file.pkpass>}"
repo="$(cd "$(dirname "$0")/.." && pwd)"
wwdr="$repo/Configs/wallet/wwdr.pem"
[ -f "$wwdr" ] || wwdr="$repo/DaGym/Resources/AppleWWDRG4.pem"
cache="$HOME/.dagym-tools"
root="$cache/AppleIncRootCertificate.pem"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -q "$pass" -d "$work"

echo "Manifest hashes:"
status=0
for entry in $(python3 -c 'import json,sys; [print(k) for k in json.load(open(sys.argv[1]))]' "$work/manifest.json"); do
    expected="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$work/manifest.json" "$entry")"
    actual="$(shasum -a 1 "$work/$entry" | cut -d' ' -f1)"
    if [ "$expected" = "$actual" ]; then
        echo "  ok    $entry"
    else
        echo "  BAD   $entry (manifest $expected, file $actual)"
        status=1
    fi
done
for f in pass.json signature manifest.json icon.png; do
    [ -f "$work/$f" ] || { echo "  missing $f"; status=1; }
done

if [ ! -f "$root" ]; then
    mkdir -p "$cache"
    echo "Fetching Apple Root CA into $root..."
    if curl -fsSL https://www.apple.com/appleca/AppleIncRootCertificate.cer -o "$cache/AppleIncRootCertificate.cer"; then
        openssl x509 -inform DER -in "$cache/AppleIncRootCertificate.cer" -out "$root"
    else
        echo "  could not download the Apple Root CA; verifying against the WWDR intermediate only."
    fi
fi

echo "CMS signature:"
if [ -f "$root" ]; then
    cat "$wwdr" "$root" > "$work/chain.pem"
    openssl smime -verify -inform DER -in "$work/signature" -content "$work/manifest.json" \
        -CAfile "$work/chain.pem" -purpose any -out /dev/null
else
    openssl smime -verify -inform DER -in "$work/signature" -content "$work/manifest.json" \
        -CAfile "$wwdr" -partial_chain -purpose any -out /dev/null
fi

echo "Signer:"
openssl pkcs7 -inform DER -in "$work/signature" -print_certs -noout | sed 's/^/  /'
echo "pass.json:"
python3 -m json.tool "$work/pass.json" | sed 's/^/  /'
exit $status
