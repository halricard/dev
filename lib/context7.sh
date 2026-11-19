#!/usr/bin/env bash
# Documentação atualizada para o agente de IA: o servidor MCP do Context7.
#
# O agente sobe o servidor pelo comando "dev docs mcp". A chave de API fica em
# ~/.dev/config (CONTEXT7_API_KEY) e nunca vai para o projeto: o servidor a
# recebe por variável de ambiente, fora da linha de comando e do git.

CONTEXT7_API="https://context7.com/api"
CONTEXT7_KEYS_URL="https://context7.com/dashboard"

cmd_docs() {
  local subcmd="${1:-status}"; shift || true
  case "$subcmd" in
    status)     docs_status ;;
    install)    docs_install_all ;;
    key)        docs_key "$@" ;;
    remove|rm)  docs_remove ;;
    mcp)        docs_mcp ;;
    *)          die "uso: ${DEV_COMMAND:-$DEV docs} [status|install|key [--remove]|remove]" ;;
  esac
}

context7_mcp_prefix()    { printf '%s\n' "$DEV_RUNTIME/context7-mcp/$CONTEXT7_MCP_VERSION"; }
context7_mcp_cli()       { printf '%s\n' "$(context7_mcp_prefix)/node_modules/@upstash/context7-mcp/dist/index.js"; }
context7_mcp_installed() { [[ -f "$(context7_mcp_cli)" ]]; }

# ---------------------------------------------------------------- chave de API
# A variável de ambiente vence a configuração da máquina.
docs_api_key() {
  if [[ -n "${CONTEXT7_API_KEY:-}" ]]; then
    printf '%s\n' "$CONTEXT7_API_KEY"
    return 0
  fi
  config_get CONTEXT7_API_KEY
}

docs_key_source() {
  if [[ -n "${CONTEXT7_API_KEY:-}" ]]; then
    printf 'variável CONTEXT7_API_KEY\n'
  else
    printf '%s\n' "${DEV_CONFIG/#"$HOME"/\~}"
  fi
}

# Mostra só o começo e o fim da chave.
docs_key_masked() {
  local key="$1"
  if (( ${#key} > 12 )); then
    printf '%s…%s\n' "${key:0:7}" "${key: -4}"
  else
    printf '…\n'
  fi
}

# Confere a chave na API do Context7. A chave vai pela entrada padrão do curl,
# não pela linha de comando, para não aparecer na lista de processos.
# Retorno: 0 aceita, 1 recusada, 2 sem resposta.
docs_key_check() {
  local key="$1" code
  code="$(printf 'Authorization: Bearer %s\n' "$key" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time 15 -H @- \
      "$CONTEXT7_API/v2/libs/search?libraryName=laravel&query=routing" 2>/dev/null)" || code=""
  case "$code" in
    2??)     return 0 ;;
    401|403) return 1 ;;
    *)       return 2 ;;
  esac
}

# Pede a chave sem eco no terminal; fora de um terminal, lê uma linha da
# entrada padrão (para "echo chave | dev docs key").
docs_key_read() {
  local key=""
  if [[ -t 0 ]]; then
    read -r -s -p "  ?  chave de API do Context7 (não aparece ao digitar): " key || true
    printf '\n' >&2
  else
    IFS= read -r key || true
  fi
  printf '%s\n' "$key"
}

docs_key() {
  local key=""
  case "${1:-}" in
    --remove|-r)
      config_unset CONTEXT7_API_KEY
      ok "chave do Context7 apagada de $(docs_key_source)"
      return 0 ;;
    -*) die "uso: ${DEV_COMMAND:-$DEV docs} key [--remove]" ;;
    "") key="$(docs_key_read)" ;;
    *)  key="$1"
        hint "a chave passada como argumento fica no histórico do shell; prefira: $DEV docs key" ;;
  esac
  key="${key//[[:space:]]/}"
  [[ -n "$key" ]] || die "nenhuma chave informada — crie uma em $CONTEXT7_KEYS_URL"

  local rc=0
  docs_key_check "$key" || rc=$?
  case "$rc" in
    0) ok "chave aceita pelo Context7" ;;
    1) die "o Context7 recusou a chave — confira em $CONTEXT7_KEYS_URL" ;;
    *) warn "não consegui falar com o Context7 para conferir a chave; ela será gravada assim mesmo" ;;
  esac
  ensure_tree
  config_set CONTEXT7_API_KEY "$key"
  chmod 600 "$DEV_CONFIG"
  ok "chave gravada em ${DEV_CONFIG/#"$HOME"/\~}  $(docs_key_masked "$key")"
  [[ -n "${CONTEXT7_API_KEY:-}" ]] && warn "a variável CONTEXT7_API_KEY do ambiente continua valendo no lugar desta"
  return 0
}

# ------------------------------------------------------------------ instalação
install_context7_mcp() {
  if context7_mcp_installed; then
    ok "Context7 MCP $CONTEXT7_MCP_VERSION  já instalado"
    return 0
  fi
  local node prefix
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  prefix="$(context7_mcp_prefix)"
  mkdir -p "$prefix"
  # --ignore-scripts: nenhum script de instalação de terceiros roda na máquina.
  if ! with_progress "instalando o Context7 MCP $CONTEXT7_MCP_VERSION" \
      env PATH="$(dirname "$node"):$PATH" \
      "$(dirname "$node")/npm" install --prefix "$prefix" --ignore-scripts \
      --no-audit --no-fund --save-exact "@upstash/context7-mcp@$CONTEXT7_MCP_VERSION"; then
    rm -rf "$prefix"
    return 1
  fi
}

# Garante o servidor e, num terminal, oferece gravar a chave que falta.
ensure_docs() {
  install_context7_mcp || die "a instalação do Context7 MCP falhou"
  [[ -n "$(docs_api_key)" ]] && return 0
  warn "sem chave de API, o Context7 responde com limites de uso menores"
  if [[ -t 0 ]] && confirm "gravar a chave de API do Context7 agora?" s; then
    docs_key
  else
    hint "grave a chave com: $DEV docs key   (crie uma em $CONTEXT7_KEYS_URL)"
  fi
}

docs_install_all() {
  ensure_tree
  step "DOCUMENTAÇÃO PARA O AGENTE"
  ensure_docs
  blank
  hint "dê a documentação ao agente de um projeto com: $DEV agent add claude --docs"
  blank
}

docs_remove() {
  step "REMOVENDO A DOCUMENTAÇÃO DO AGENTE"
  rm -rf "$DEV_RUNTIME/context7-mcp"
  ok "Context7 MCP removido"
  [[ -n "$(config_get CONTEXT7_API_KEY)" ]] && hint "a chave continua gravada; apague com: $DEV docs key --remove"
  hint "as configurações de MCP nos projetos continuam; tire com: $DEV agent remove"
  blank
}

docs_status() {
  step "DOCUMENTAÇÃO PARA O AGENTE"
  local mark key
  if context7_mcp_installed; then mark="${C_GREEN}✔${C_RESET}"; else mark="${C_DIM}○${C_RESET}"; fi
  printf '  %b  %-16s %s\n' "$mark" "Context7 MCP" "$CONTEXT7_MCP_VERSION  documentação atualizada para o agente de IA"
  key="$(docs_api_key)"
  if [[ -n "$key" ]]; then
    printf '  %b  %-16s %s\n' "${C_GREEN}✔${C_RESET}" "chave de API" "$(docs_key_masked "$key")  em $(docs_key_source)"
  else
    printf '  %b  %-16s %s\n' "${C_DIM}○${C_RESET}" "chave de API" "não gravada"
  fi
  blank
  context7_mcp_installed || hint "instale com: $DEV docs install"
  [[ -n "$key" ]] || hint "grave a chave com: $DEV docs key   (crie uma em $CONTEXT7_KEYS_URL)"
  blank
}

# ---------------------------------------------------------- MCP para o agente
# Ponto de entrada do servidor MCP, chamado pelo agente pelo comando
# "dev docs mcp". A saída padrão pertence ao protocolo MCP: nenhuma mensagem
# pode ir para ela. Sem chave, o servidor funciona com os limites anônimos.
docs_mcp() {
  context7_mcp_installed \
    || die "o Context7 MCP do dev não está instalado — rode: $DEV docs install"
  local node key
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  key="$(docs_api_key)"
  [[ -n "$key" ]] || warn "sem chave do Context7; grave com: $DEV docs key" >&2
  export_node_env
  rm -rf "$DEV_TMP"
  # OTEL_SDK_DISABLED: o servidor não coleta nem expõe métricas locais.
  exec env CONTEXT7_API_KEY="$key" OTEL_SDK_DISABLED=true \
    "$node" "$(context7_mcp_cli)" --transport stdio
}
