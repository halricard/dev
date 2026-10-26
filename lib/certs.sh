#!/usr/bin/env bash
# HTTPS local: autoridade própria e certificados para *.localhost.

CMD_EXE="/mnt/c/Windows/System32/cmd.exe"
CERTUTIL_EXE="/mnt/c/Windows/System32/certutil.exe"

windows_available() { [[ -x "$CMD_EXE" && -x "$CERTUTIL_EXE" ]]; }

windows_profile() {
  local profile
  profile="$(cd /mnt/c 2>/dev/null && "$CMD_EXE" /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r' || true)"
  [[ -n "$profile" ]] || return 1
  wslpath -u "$profile" 2>/dev/null
}

generate_ca() {
  require_command openssl
  mkdir -p "$DEV_CERTS"
  if [[ -f "$CA_CRT" && -f "$CA_KEY" ]]; then
    ok "autoridade local  já existe"
  else
    openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
      -keyout "$CA_KEY" -out "$CA_CRT" \
      -subj "/CN=$CA_NAME/O=dev" \
      -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
      -addext "keyUsage=critical,keyCertSign,cRLSign" \
      >/dev/null 2>&1 || die "openssl falhou ao criar a autoridade"
    chmod 600 "$CA_KEY"
    ok "autoridade local criada  validade de 10 anos"
  fi
  trust_ca
}

trust_ca() {
  is_wsl && [[ -z "${BATS_TEST_TMPDIR:-}" ]] && trust_ca_on_windows
  trust_ca_on_linux
}

mkcert_path() { printf '%s\n' "$DEV_RUNTIME/mkcert/bin/mkcert"; }

NSSDB="$HOME/.pki/nssdb"

with_caroot() {
  local caroot rc
  caroot="$(scratch)"
  cp "$CA_CRT" "$caroot/rootCA.pem"
  CAROOT="$caroot" "$@"
  rc=$?
  rm -rf "$caroot"
  return "$rc"
}

trusted_in_system() {
  openssl verify -no-CAfile -CApath /etc/ssl/certs "$CA_CRT" >/dev/null 2>&1
}

trust_ca_on_linux() {
  [[ -x "$(mkcert_path)" ]] || {
    warn "o mkcert não está instalado — os domínios https://*.localhost não foram confiados no Linux"
    hint "$DEV install   instala"
    return 0
  }
  trust_ca_in_nss
  trust_ca_in_system
}

firefox_profiles() {
  local dir
  for dir in "$HOME"/.mozilla/firefox/* "$HOME"/snap/firefox/common/.mozilla/firefox/*; do
    [[ -f "$dir/cert9.db" ]] && printf '%s\n' "$dir"
  done
  return 0
}

firefox_needs_closing() {
  pgrep -x firefox >/dev/null 2>&1 || return 1
  [[ -n "$(firefox_profiles)" ]]
}

close_firefox() {
  [[ -t 0 ]] || return 0
  firefox_needs_closing || return 0

  warn "o Firefox está aberto"
  hint "ele regrava o banco de certificados ao sair, e a autoridade gravada agora pode se perder"
  if ! confirm "fechar o Firefox agora? (reabre com as abas no lugar)" s; then
    warn "seguindo com ele aberto: https://*.localhost pode avisar no Firefox"
    return 0
  fi

  pkill -TERM -x firefox 2>/dev/null || true
  local waited=0
  while (( waited < 10 )) && pgrep -x firefox >/dev/null 2>&1; do
    sleep 1
    waited=$(( waited + 1 ))
  done
  if pgrep -x firefox >/dev/null 2>&1; then
    warn "o Firefox não fechou em 10s — seguindo sem forçar"
    return 0
  fi
  ok "Firefox fechado"
}

trust_ca_in_nss() {
  local mkcert
  mkcert="$(mkcert_path)"
  [[ -x "$mkcert" ]] || return 0
  if has certutil; then
    close_firefox
    if [[ ! -f "$NSSDB/cert9.db" ]]; then
      mkdir -p "$NSSDB"
      certutil -d "sql:$NSSDB" -N --empty-password >/dev/null 2>&1 || true
    fi
    if TRUST_STORES=nss with_caroot "$mkcert" -install >/dev/null 2>&1; then
      ok "autoridade confiada na NSS  Chrome, Chromium e Firefox"
    else
      warn "o mkcert não conseguiu gravar na NSS"
    fi
  else
    warn "sem o certutil (libnss3-tools), o Chrome e o Firefox do Linux não confiam nos certificados"
  fi
}

trust_ca_in_system() {
  local mkcert
  mkcert="$(mkcert_path)"
  [[ -x "$mkcert" ]] || return 0
  if trusted_in_system; then
    ok "autoridade confiada no sistema  já estava"
    return 0
  fi
  info "o PHP, o curl e o git consultam a loja do sistema — gravar nela pede sudo"
  if ! confirm "confiar a autoridade do dev no sistema?" s; then
    warn "sem isso, conexões locais em https://*.localhost podem falhar verificação"
    return 0
  fi
  if TRUST_STORES=system with_caroot "$mkcert" -install; then
    ok "autoridade confiada no sistema"
  else
    warn "o mkcert não conseguiu gravar na loja do sistema"
  fi
}

remove_ca_from_linux() {
  local mkcert
  mkcert="$(mkcert_path)"
  [[ -x "$mkcert" && -f "$CA_CRT" ]] || return 0
  has certutil && TRUST_STORES=nss with_caroot "$mkcert" -uninstall >/dev/null 2>&1 || true
  if trusted_in_system; then
    TRUST_STORES=system with_caroot "$mkcert" -uninstall \
      && ok "autoridade removida do Linux" || true
  fi
}

trust_ca_on_windows() {
  if ! windows_available; then
    warn "sem interop com o Windows: domínios https://*.localhost vão dar aviso no navegador"
    return 0
  fi
  local profile target
  profile="$(windows_profile)" || { warn "não consegui achar o perfil do Windows"; return 0; }
  target="$profile/dev-ca.crt"
  cp "$CA_CRT" "$target"
  if "$CERTUTIL_EXE" -user -addstore Root "$(wslpath -w "$target")" >/dev/null 2>&1; then
    ok "autoridade confiada no Windows"
  else
    warn "o Windows recusou confiar a autoridade — https dará aviso"
  fi
  rm -f "$target"
}

remove_ca_from_windows() {
  windows_available || return 0
  [[ -f "$CA_CRT" ]] || return 0
  local thumbprint
  thumbprint="$(openssl x509 -in "$CA_CRT" -noout -fingerprint -sha1 2>/dev/null \
             | cut -d= -f2 | tr -d ': ' || true)"
  [[ -n "$thumbprint" ]] || return 0
  "$CERTUTIL_EXE" -user -delstore Root "$thumbprint" >/dev/null 2>&1 \
    && ok "autoridade removida do Windows" || true
}

issue_leaf() {
  local hosts=("$@") alt="" i=1 host
  [[ ${#hosts[@]} -eq 0 ]] && hosts=("localhost")
  for host in "${hosts[@]}"; do
    alt+="DNS.$i = $host"$'\n'
    i=$(( i + 1 ))
  done
  alt+="IP.1 = 127.0.0.1"$'\n'

  local cfg
  cfg="$(mktemp)"
  cat > "$cfg" <<CFG
[req]
distinguished_name = dn
req_extensions     = ext
prompt             = no
[dn]
CN = ${hosts[0]}
[ext]
basicConstraints = critical,CA:FALSE
keyUsage         = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt
[alt]
$alt
CFG

  local csr
  [[ -f "$CA_CRT" && -f "$CA_KEY" ]] || return 0
  csr="$(mktemp)"
  [[ -f "$LEAF_KEY" ]] || openssl genrsa -out "$LEAF_KEY" 2048 >/dev/null 2>&1
  chmod 600 "$LEAF_KEY"
  openssl req -new -key "$LEAF_KEY" -out "$csr" -config "$cfg" >/dev/null 2>&1 \
    || die "openssl falhou ao gerar o pedido de certificado"
  openssl x509 -req -in "$csr" -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "$LEAF_CRT" -days 825 -sha256 \
    -extfile "$cfg" -extensions ext >/dev/null 2>&1 \
    || die "openssl falhou ao assinar o certificado"
  rm -f "$cfg" "$csr"
}

served_hosts() {
  local names=() file
  for file in "$DEV_SITES"/*; do
    [[ -f "$file" ]] || continue
    names+=("$(basename "$file").localhost")
  done
  names+=("adminer.localhost" "mail.localhost" "localhost")
  printf '%s\n' "${names[@]}"
}

reissue_leaf() {
  local hosts=()
  mapfile -t hosts < <(served_hosts)
  issue_leaf "${hosts[@]}"
}
