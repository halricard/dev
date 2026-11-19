#!/usr/bin/env bash
# Chaves das ferramentas do Claude Code: "dev agent key <ferramenta>".
#
# Cada chave fica em ~/.dev/config (permissão 600), com o nome da variável de
# ambiente que a substitui. Nunca vai para o projeto, para o git nem para a
# linha de comando: o dev a entrega por variável de ambiente aos servidores MCP
# que ele mesmo inicia.
#
# O Penpot é a exceção: o servidor dele é remoto e só aceita a chave na URL,
# que o Claude Code monta a partir do próprio ambiente. Para ele, o dev mantém
# no ~/.bashrc um bloco marcado que lê a chave de ~/.dev/config a cada
# terminal novo; o bloco não guarda segredo.

KEY_TOOLS=(context7 github penpot)
KEY_SHELL_TOOLS=(penpot)
KEY_PROFILE_FILE="$HOME/.bashrc"
KEY_PROFILE_START="# >>> dev agent key >>>"
KEY_PROFILE_END="# <<< dev agent key <<<"

CONTEXT7_API="https://context7.com/api"
CONTEXT7_KEYS_URL="https://context7.com/dashboard"
GITHUB_API="https://api.github.com"
GITHUB_KEYS_URL="https://github.com/settings/personal-access-tokens"
PENPOT_KEYS_PLACE="Penpot → Your account → Integrations → MCP Server"

key_known() { [[ " ${KEY_TOOLS[*]} " == *" $1 "* ]]; }
key_shell()  { [[ " ${KEY_SHELL_TOOLS[*]} " == *" $1 "* ]]; }

key_var() {
  case "$1" in
    context7) printf 'CONTEXT7_API_KEY\n' ;;
    github)   printf 'GITHUB_PAT\n' ;;
    penpot)   printf 'PENPOT_MCP_KEY\n' ;;
    *)        return 1 ;;
  esac
}

key_title() {
  case "$1" in
    context7) printf 'Context7\n' ;;
    github)   printf 'GitHub\n' ;;
    penpot)   printf 'Penpot\n' ;;
    *)        return 1 ;;
  esac
}

key_label() {
  case "$1" in
    context7) printf 'chave de API do Context7\n' ;;
    github)   printf 'token do GitHub\n' ;;
    penpot)   printf 'chave do servidor MCP do Penpot\n' ;;
    *)        return 1 ;;
  esac
}

key_create_url() {
  case "$1" in
    context7) printf '%s\n' "$CONTEXT7_KEYS_URL" ;;
    github)   printf '%s\n' "$GITHUB_KEYS_URL" ;;
    penpot)   printf '%s\n' "$PENPOT_KEYS_PLACE" ;;
    *)        return 1 ;;
  esac
}

# A variável de ambiente vence a configuração da máquina.
key_value() {
  local var
  var="$(key_var "$1")" || return 1
  if [[ -n "${!var:-}" ]]; then
    printf '%s\n' "${!var}"
    return 0
  fi
  config_get "$var"
}

key_source() {
  local var
  var="$(key_var "$1")" || return 1
  if [[ -n "${!var:-}" ]]; then
    printf 'variável %s\n' "$var"
  else
    printf '%s\n' "${DEV_CONFIG/#"$HOME"/\~}"
  fi
}

# Mostra só o começo e o fim da chave.
key_masked() {
  local key="$1"
  if (( ${#key} > 12 )); then
    printf '%s…%s\n' "${key:0:7}" "${key: -4}"
  else
    printf '…\n'
  fi
}

# Confere a chave no serviço. Ela vai pela entrada padrão do curl, não pela
# linha de comando, para não aparecer na lista de processos.
# Retorno: 0 aceita, 1 recusada, 2 sem resposta, 3 o serviço não confere.
key_check() {
  local tool="$1" key="$2" url code
  case "$tool" in
    context7) url="$CONTEXT7_API/v2/libs/search?libraryName=laravel&query=routing" ;;
    github)   url="$GITHUB_API/user" ;;
    *)        return 3 ;;
  esac
  code="$(printf 'Authorization: Bearer %s\n' "$key" \
    | curl -s -o /dev/null -w '%{http_code}' --max-time 15 -H @- "$url" 2>/dev/null)" || code=""
  case "$code" in
    2??)     return 0 ;;
    401|403) return 1 ;;
    *)       return 2 ;;
  esac
}

# Pede a chave sem eco no terminal; fora de um terminal, lê uma linha da
# entrada padrão (para "echo chave | dev agent key github").
key_read() {
  local key=""
  if [[ -t 0 ]]; then
    read -r -s -p "  ?  $(key_label "$1") (não aparece ao digitar): " key || true
    printf '\n' >&2
  else
    IFS= read -r key || true
  fi
  printf '%s\n' "$key"
  blank
}

key_usage() {
  local tools="${KEY_TOOLS[*]}"
  printf 'uso: %s key [%s] [--remove]\n' "${DEV_COMMAND:-$DEV agent}" "${tools// /|}"
}

cmd_key() {
  local tool="${1:-}"; shift || true
  [[ -n "$tool" ]] || { key_status; return 0; }
  key_known "$tool" || die "ferramenta sem chave: $tool ($(key_usage))"
  key_set "$tool" "$@"
}

key_set() {
  local tool="$1" key="" var title
  var="$(key_var "$tool")"
  title="$(key_title "$tool")"
  case "${2:-}" in
    --remove|-r)
      config_unset "$var"
      ok "$title: chave apagada de ${DEV_CONFIG/#"$HOME"/\~}"
      key_shell "$tool" && key_profile_sync
      return 0 ;;
    -*) die "$(key_usage)" ;;
    "") key="$(key_read "$tool")" ;;
    *)  key="$2"
        hint "a chave passada como argumento fica no histórico do shell; prefira: $DEV agent key $tool" ;;
  esac
  key="${key//[[:space:]]/}"
  [[ -n "$key" ]] || die "nada informado — crie em $(key_create_url "$tool")"

  local rc=0
  key_check "$tool" "$key" || rc=$?
  case "$rc" in
    0) ok "aceita pelo $title" ;;
    1) die "o $title recusou — confira em $(key_create_url "$tool")" ;;
    3) info "o $title não tem como conferir a chave daqui; ela será gravada assim mesmo" ;;
    *) warn "não consegui falar com o $title para conferir; será gravada assim mesmo" ;;
  esac
  ensure_tree
  config_set "$var" "$key"
  chmod 600 "$DEV_CONFIG"
  ok "gravada em ${DEV_CONFIG/#"$HOME"/\~}  $(key_masked "$key")"
  if key_shell "$tool"; then
    key_profile_sync
    hint "abra um terminal novo (ou rode: source ~/.bashrc) antes de abrir o Claude Code"
  elif [[ -n "${!var:-}" ]]; then
    warn "a variável $var do ambiente continua valendo no lugar desta"
  fi
  return 0
}

# ------------------------------------------------ chaves lidas do ambiente
# O bloco do ~/.bashrc exporta, a cada terminal, as chaves gravadas das
# ferramentas que o Claude Code lê do próprio ambiente. Sem nenhuma, o bloco
# sai do arquivo.
key_profile_block() {
  local tool var config="$DEV_CONFIG"
  printf '%s\n' "$KEY_PROFILE_START"
  printf '# Chaves que o Claude Code lê do ambiente, gravadas com "dev agent key"; o valor fica em %s.\n' "$config"
  for tool in "${KEY_SHELL_TOOLS[@]}"; do
    var="$(key_var "$tool")"
    [[ -n "$(config_get "$var")" ]] || continue
    printf '[ -f "%s" ] && export %s="$(. "%s"; printf %%s "${%s:-}")"\n' "$config" "$var" "$config" "$var"
  done
  printf '%s\n' "$KEY_PROFILE_END"
}

key_profile_strip() {
  [[ -f "$KEY_PROFILE_FILE" ]] && grep -qxF "$KEY_PROFILE_START" "$KEY_PROFILE_FILE" || return 0
  local tmp
  tmp="$(mktemp)"
  awk -v a="$KEY_PROFILE_START" -v b="$KEY_PROFILE_END" '
    $0 == a { inside = 1; next }
    $0 == b { inside = 0; next }
    !inside' "$KEY_PROFILE_FILE" > "$tmp"
  cat "$tmp" > "$KEY_PROFILE_FILE"
  rm -f "$tmp"
}

key_profile_sync() {
  local tool needed=0
  for tool in "${KEY_SHELL_TOOLS[@]}"; do
    [[ -n "$(config_get "$(key_var "$tool")")" ]] && needed=1
  done
  key_profile_strip
  if (( needed )); then
    key_profile_block >> "$KEY_PROFILE_FILE"
    ok "${KEY_PROFILE_FILE/#"$HOME"/\~}  carrega a chave nos terminais novos (o arquivo não guarda a chave)"
  fi
  return 0
}

key_status() {
  step "CHAVES DAS FERRAMENTAS"
  local tool key
  for tool in "${KEY_TOOLS[@]}"; do
    key="$(key_value "$tool")"
    if [[ -n "$key" ]]; then
      printf '  %b  %-12s %s\n' "${C_GREEN}✔${C_RESET}" "$tool" "$(key_masked "$key")  em $(key_source "$tool")"
    else
      printf '  %b  %-12s %s\n' "${C_DIM}○${C_RESET}" "$tool" "não gravada  ${C_DIM}crie em $(key_create_url "$tool")${C_RESET}"
    fi
  done
  blank
  hint "grave com: $DEV agent key <ferramenta>   (--remove apaga)"
  blank
}
