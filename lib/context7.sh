#!/usr/bin/env bash
# Context7 para o Claude Code: documentação atualizada pelo servidor MCP.
#
# O Claude Code sobe o servidor pelo comando "dev context7 mcp". A chave de API
# fica em ~/.dev/config (CONTEXT7_API_KEY, gravada com "dev agent key
# context7") e nunca vai para o projeto: o servidor a recebe por variável de
# ambiente, fora da linha de comando e do git.

# shellcheck source=lib/keys.sh
source "$DEV_ROOT/lib/keys.sh"

cmd_context7() {
  local subcmd="${1:-status}"; shift || true
  case "$subcmd" in
    status)     context7_status ;;
    install)    context7_install_all ;;
    remove|rm)  context7_remove ;;
    mcp)        context7_mcp ;;
    *)          die "uso: ${DEV_COMMAND:-$DEV context7} [status|install|remove]   (a chave: $DEV agent key context7)" ;;
  esac
}

context7_mcp_prefix()    { printf '%s\n' "$DEV_RUNTIME/context7-mcp/$CONTEXT7_MCP_VERSION"; }
context7_mcp_cli()       { printf '%s\n' "$(context7_mcp_prefix)/node_modules/@upstash/context7-mcp/dist/index.js"; }
context7_mcp_installed() { [[ -f "$(context7_mcp_cli)" ]]; }

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
ensure_context7() {
  install_context7_mcp || die "a instalação do Context7 MCP falhou"
  [[ -n "$(key_value context7)" ]] && return 0
  warn "sem chave de API, o Context7 responde com limites de uso menores"
  if [[ -t 0 ]] && confirm "gravar a chave de API do Context7 agora?" s; then
    key_set context7
  else
    hint "grave a chave com: $DEV agent key context7   (crie uma em $CONTEXT7_KEYS_URL)"
  fi
}

context7_install_all() {
  ensure_tree
  step "CONTEXT7 PARA O CLAUDE CODE"
  ensure_context7
  blank
  hint "dê a documentação ao Claude Code de um projeto com: $DEV agent add --context7"
  blank
}

context7_remove() {
  step "REMOVENDO O CONTEXT7"
  rm -rf "$DEV_RUNTIME/context7-mcp"
  ok "Context7 MCP removido"
  [[ -n "$(config_get CONTEXT7_API_KEY)" ]] && hint "a chave continua gravada; apague com: $DEV agent key context7 --remove"
  hint "as configurações de MCP nos projetos continuam; tire com: $DEV agent remove"
  blank
}

context7_status() {
  step "CONTEXT7 PARA O CLAUDE CODE"
  local mark key
  if context7_mcp_installed; then mark="${C_GREEN}✔${C_RESET}"; else mark="${C_DIM}○${C_RESET}"; fi
  printf '  %b  %-16s %s\n' "$mark" "Context7 MCP" "$CONTEXT7_MCP_VERSION  documentação atualizada para o Claude Code"
  key="$(key_value context7)"
  if [[ -n "$key" ]]; then
    printf '  %b  %-16s %s\n' "${C_GREEN}✔${C_RESET}" "chave de API" "$(key_masked "$key")  em $(key_source context7)"
  else
    printf '  %b  %-16s %s\n' "${C_DIM}○${C_RESET}" "chave de API" "não gravada"
  fi
  blank
  context7_mcp_installed || hint "instale com: $DEV context7 install"
  [[ -n "$key" ]] || hint "grave a chave com: $DEV agent key context7   (crie uma em $CONTEXT7_KEYS_URL)"
  blank
}

# ---------------------------------------------------------- MCP para o agente
# Ponto de entrada do servidor MCP, chamado pelo Claude Code pelo comando
# "dev context7 mcp". A saída padrão pertence ao protocolo MCP: nenhuma
# mensagem pode ir para ela. Sem chave, o servidor funciona com os limites
# anônimos.
context7_mcp() {
  context7_mcp_installed \
    || die "o Context7 MCP do dev não está instalado — rode: $DEV context7 install"
  local node key
  node="$(node_bin)" || die "o Node do dev não está instalado — rode $DEV install"
  key="$(key_value context7)"
  [[ -n "$key" ]] || warn "sem chave do Context7; grave com: $DEV agent key context7" >&2
  export_node_env
  rm -rf "$DEV_TMP"
  # OTEL_SDK_DISABLED: o servidor não coleta nem expõe métricas locais.
  exec env CONTEXT7_API_KEY="$key" OTEL_SDK_DISABLED=true \
    "$node" "$(context7_mcp_cli)" --transport stdio
}
