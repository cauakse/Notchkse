#!/bin/zsh
# Cria um certificado de assinatura local ("Notchkse Local Signing") no seu
# Keychain. Com ele, as permissões do macOS (Acessibilidade, Bluetooth…)
# continuam valendo depois de cada build. Para remover depois:
#   security delete-identity -c "Notchkse Local Signing"
set -euo pipefail
NAME="Notchkse Local Signing"
if security find-identity -p codesigning | grep -q "$NAME"; then
  echo "Certificado \"$NAME\" já existe."; exit 0
fi
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -config "$TMP/cert.cnf" 2>/dev/null
PASS=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12" \
  -passout pass:"$PASS" -name "$NAME" -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
echo "Pronto: certificado \"$NAME\" criado. Rode ./scripts/install.sh"
