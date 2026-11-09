#!/usr/bin/env bash
# Instruções para agentes de IA: gera a skill "dev" dentro do projeto.
#
# Claude Code, Codex e Antigravity leem o mesmo formato (pasta com SKILL.md);
# só o diretório muda. A tabela fica em agent_target_dir.

# shellcheck source=lib/browser.sh
source "$DEV_ROOT/lib/browser.sh"
# shellcheck source=lib/docs.sh
source "$DEV_ROOT/lib/docs.sh"

AGENT_TARGETS=(claude codex antigravity)
AGENT_MARKER="generated-by: dev agent"

cmd_agent() {
  local subcmd="${1:-list}"; shift || true
  case "$subcmd" in
    add)             agent_add "$@" ;;
    remove|rm)       agent_remove "$@" ;;
    update)          agent_update "$@" ;;
    list)            agent_list "$@" ;;
    *)               die "uso: ${DEV_COMMAND:-$DEV agent} add [claude|codex|antigravity|all] [--browser] [--docs] | remove [alvo] | update | list" ;;
  esac
}

# Diretório da skill, relativo à raiz do projeto.
agent_target_dir() {
  case "$1" in
    claude)      printf '.claude/skills/dev\n' ;;
    codex)       printf '.agents/skills/dev\n' ;;
    antigravity) printf '.agent/skills/dev\n' ;;
    *)           return 1 ;;
  esac
}

agent_valid_target() {
  [[ " ${AGENT_TARGETS[*]} all " == *" $1 "* ]]
}

agent_installed() {
  local file
  file="$PROJECT_DIR/$(agent_target_dir "$1")/SKILL.md"
  [[ -f "$file" ]] && grep -q "$AGENT_MARKER" "$file"
}

# Resolve o alvo (argumento ou pergunta) em uma lista de alvos, um por linha.
# O terceiro argumento restringe as opções da pergunta.
agent_pick() {
  local verb="$1" given="${2:-}"; shift 2 || true
  local options=("$@") chosen
  if [[ -z "$given" ]]; then
    (( ${#options[@]} > 0 )) || return 1
    chosen="$(choose "para qual agente $verb a skill do dev?" "${options[@]}" all)" \
      || die "uso: ${DEV_COMMAND:-$DEV agent} $verb [claude|codex|antigravity|all]"
  else
    chosen="$given"
  fi
  agent_valid_target "$chosen" || die "agente desconhecido: $chosen (claude, codex, antigravity ou all)"
  if [[ "$chosen" == all ]]; then
    printf '%s\n' "${options[@]}"
  else
    printf '%s\n' "$chosen"
  fi
}

agent_app_title() {
  local title=""
  if [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP"; then
    title="$(recipe_title 2>/dev/null || true)"
  fi
  printf '%s\n' "${title:-${PROJECT_APP:-PHP}}"
}

# Versão instalada da aplicação, lida dos arquivos do projeto pela receita.
agent_app_version() {
  local version=""
  if [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP" && declare -F recipe_version >/dev/null; then
    version="$(recipe_version "$PROJECT_DIR" 2>/dev/null || true)"
  fi
  if [[ -n "$version" ]]; then
    printf '`%s`\n' "$version"
  else
    printf 'not detected (check it in the code)\n'
  fi
}

agent_app_notes() {
  local file
  [[ -n "$PROJECT_APP" ]] || return 0
  for file in "$DEV_PLUGINS/installed/$PROJECT_APP/agent.md" "$DEV_ROOT/plugins/$PROJECT_APP/agent.md"; do
    [[ -f "$file" ]] && { cat "$file"; return 0; }
  done
  return 0
}

agent_render() {
  local text notes
  text="$(cat "$DEV_ROOT/lib/agent/skill.md")"
  notes="$(agent_app_notes)"
  # As notas da aplicação entram primeiro: elas também usam os marcadores.
  text="${text//\{\{APP_NOTES\}\}/$notes}"
  text="${text//\{\{PROJECT\}\}/$PROJECT_NAME}"
  text="${text//\{\{APP_TITLE\}\}/$(agent_app_title)}"
  text="${text//\{\{APP_VERSION\}\}/$(agent_app_version)}"
  text="${text//\{\{PHP\}\}/${PROJECT_PHP:-$(config_get DEFAULT_PHP)}}"
  text="${text//\{\{DATABASE\}\}/${PROJECT_DATABASE:-none}}"
  text="${text//\{\{DOCROOT\}\}/$PROJECT_DOCROOT}"
  text="${text//\{\{URL\}\}/$(site_url "$PROJECT_NAME")}"
  text="${text//\{\{TEST_URL\}\}/https://$(test_host "$PROJECT_NAME")}"
  printf '%s\n' "$text"
}

agent_write() {
  local target="$1" dir file
  dir="$PROJECT_DIR/$(agent_target_dir "$target")"
  file="$dir/SKILL.md"
  if [[ -f "$file" ]] && ! grep -q "$AGENT_MARKER" "$file"; then
    warn "$target: já existe ${file#"$PROJECT_DIR"/} que não foi gerado pelo dev — mantido"
    return 0
  fi
  mkdir -p "$dir"
  agent_render > "$file"
  ok "$target  ${file#"$PROJECT_DIR"/}"
}

# Chamado também por "dev new --agent": o projeto já está carregado.
agent_install_targets() {
  local target
  for target in "$@"; do
    agent_write "$target"
  done
}

agent_add() {
  require_project
  local picked target given="" browser=0 docs=0
  local targets=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --browser) browser=1 ;;
      --docs)    docs=1 ;;
      -*)        die "opção desconhecida: $1" ;;
      *)         given="$1" ;;
    esac
    shift
  done
  picked="$(agent_pick add "$given" "${AGENT_TARGETS[@]}")" || exit 1
  mapfile -t targets <<< "$picked"

  step "SKILL DO DEV PARA AGENTES"
  agent_install_targets "${targets[@]}"
  if (( browser )); then
    step "NAVEGADOR PARA O AGENTE"
    install_browser
    browser_install_deps || true
    install_playwright_mcp || die "a instalação do Playwright MCP falhou"
    for target in "${targets[@]}"; do
      agent_mcp_write browser "$target"
    done
    hint "o navegador só alcança $(site_url "$PROJECT_NAME"), https://$(test_host "$PROJECT_NAME") e o Mailpit"
  fi
  if (( docs )); then
    step "DOCUMENTAÇÃO PARA O AGENTE"
    ensure_docs
    for target in "${targets[@]}"; do
      agent_mcp_write docs "$target"
    done
    hint "a chave do Context7 fica em ~/.dev/config, fora do projeto"
  fi
  blank
  (( docs )) || hint "documentação atualizada da aplicação para o agente: $DEV agent add ${targets[0]} --docs"
  hint "a skill descreve este projeto ($PROJECT_NAME); regenere após mudar o dev.conf ou atualizar a aplicação: $DEV agent update"
  hint "pode versionar os arquivos no git; para não versionar, adicione-os ao .gitignore"
  blank
}

agent_remove() {
  require_project
  local installed=() target picked
  for target in "${AGENT_TARGETS[@]}"; do
    agent_installed "$target" && installed+=("$target")
  done
  if (( ${#installed[@]} == 0 )); then
    info "nenhuma skill do dev instalada neste projeto"
    return 0
  fi
  local targets=()
  picked="$(agent_pick remove "${1:-}" "${installed[@]}")" || exit 1
  mapfile -t targets <<< "$picked"

  step "REMOVENDO SKILL DO DEV"
  local dir kind
  for target in "${targets[@]}"; do
    if ! agent_installed "$target"; then
      info "$target: nada gerado pelo dev para remover"
      continue
    fi
    for kind in "${AGENT_MCP_KINDS[@]}"; do
      agent_mcp_remove "$kind" "$target"
    done
    dir="$PROJECT_DIR/$(agent_target_dir "$target")"
    rm -f "$dir/SKILL.md"
    rmdir "$dir" 2>/dev/null || true
    rmdir "$(dirname "$dir")" 2>/dev/null || true
    rmdir "$(dirname "$(dirname "$dir")")" 2>/dev/null || true
    ok "$target removido"
  done
  blank
}

agent_update() {
  require_project
  local target count=0
  step "ATUALIZANDO SKILL DO DEV"
  for target in "${AGENT_TARGETS[@]}"; do
    agent_installed "$target" || continue
    agent_write "$target"
    count=$(( count + 1 ))
  done
  (( count > 0 )) || info "nenhuma skill do dev instalada — use: $DEV agent add"
  blank
}

agent_list() {
  require_project
  step "AGENTES NESTE PROJETO"
  local target mark status_label
  for target in "${AGENT_TARGETS[@]}"; do
    if agent_installed "$target"; then
      mark="${C_GREEN}✔${C_RESET}"; status_label="${C_GREEN}instalado${C_RESET}"
    else
      mark="${C_DIM}○${C_RESET}"; status_label="${C_DIM}disponível${C_RESET}"
    fi
    agent_mcp_installed browser "$target" && status_label+="  ${C_DIM}+ navegador${C_RESET}"
    agent_mcp_installed docs "$target" && status_label+="  ${C_DIM}+ documentação${C_RESET}"
    printf '  %b  %-14s %-26s %b\n' "$mark" "$target" "$(agent_target_dir "$target")/SKILL.md" "$status_label"
  done
  blank
  hint "gere com: $DEV agent add [claude|codex|antigravity|all] [--browser] [--docs]"
  blank
}

# ------------------------------------------------- servidores MCP do agente
# O dev registra dois servidores MCP, ambos chamados pelo próprio comando dev:
#   browser  "dev browser mcp <projeto>"  navegador restrito ao projeto
#   docs     "dev docs mcp"               documentação atualizada (Context7)
# A configuração não leva caminho da máquina nem segredo, então pode ir para o git.

AGENT_MCP_KINDS=(browser docs)

agent_mcp_name() {
  case "$1" in
    browser) printf 'dev-browser\n' ;;
    docs)    printf 'dev-docs\n' ;;
    *)       return 1 ;;
  esac
}

agent_mcp_label() {
  case "$1" in
    browser) printf 'navegador\n' ;;
    docs)    printf 'documentação\n' ;;
    *)       return 1 ;;
  esac
}

# Argumentos do comando dev, um por linha. O primeiro identifica o servidor.
agent_mcp_args() {
  case "$1" in
    browser) printf '%s\n' browser mcp "$PROJECT_NAME" ;;
    docs)    printf '%s\n' docs mcp ;;
    *)       return 1 ;;
  esac
}

agent_mcp_toml_begin() { printf '# >>> dev agent: %s\n' "$(agent_mcp_label "$1")"; }
agent_mcp_toml_end()   { printf '# <<< dev agent: %s\n' "$(agent_mcp_label "$1")"; }

# O comando dev como o agente o encontra: pelo nome, se estiver no PATH.
agent_dev_command() {
  if [[ "$(readlink -f "$(command -v dev 2>/dev/null)" 2>/dev/null || true)" == "$DEV_ROOT/dev" ]]; then
    printf 'dev\n'
  else
    printf '%s\n' "$DEV_ROOT/dev"
  fi
}

agent_node() {
  node_bin 2>/dev/null || command -v node 2>/dev/null || return 1
}

agent_mcp_json_file()  { printf '%s\n' "$PROJECT_DIR/.mcp.json"; }
agent_mcp_toml_file()  { printf '%s\n' "$PROJECT_DIR/.codex/config.toml"; }

# Lista de argumentos no formato JSON e TOML: ["a", "b"].
agent_mcp_args_list() {
  local arg list=""
  while IFS= read -r arg; do
    list+="${list:+, }\"$arg\""
  done < <(agent_mcp_args "$1")
  printf '[%s]\n' "$list"
}

agent_mcp_snippet() {
  printf '{ "mcpServers": { "%s": { "command": "%s", "args": %s } } }\n' \
    "$(agent_mcp_name "$1")" "$(agent_dev_command)" "$(agent_mcp_args_list "$1")"
}

# Acrescenta, troca ou tira a entrada do dev no .mcp.json, preservando as
# outras. JSON inválido não é tocado. A entrada é do dev quando os argumentos
# começam por "<tipo> mcp".
agent_mcp_json() {
  local action="$1" kind="$2" file node args=()
  file="$(agent_mcp_json_file)"
  node="$(agent_node)" || return 2
  mapfile -t args < <(agent_mcp_args "$kind")
  "$node" -e '
    const fs = require("fs");
    const [action, file, name, command, ...args] = process.argv.slice(1);
    let data = {};
    if (fs.existsSync(file)) {
      try { data = JSON.parse(fs.readFileSync(file, "utf8")); } catch (e) { process.exit(3); }
    }
    const servers = data.mcpServers || {};
    const ours = (entry) => entry && Array.isArray(entry.args) && entry.args[0] === args[0] && entry.args[1] === "mcp";
    if (action === "has") process.exit(ours(servers[name]) ? 0 : 1);
    if (action === "add") {
      if (servers[name] && !ours(servers[name])) process.exit(4);
      servers[name] = { command, args };
      data.mcpServers = servers;
    } else {
      if (!ours(servers[name])) process.exit(0);
      delete servers[name];
      if (Object.keys(servers).length === 0) delete data.mcpServers;
      if (Object.keys(data).length === 0) { fs.unlinkSync(file); process.exit(0); }
    }
    fs.writeFileSync(file, JSON.stringify(data, null, 2) + "\n");
  ' "$action" "$file" "$(agent_mcp_name "$kind")" "$(agent_dev_command)" "${args[@]}"
}

agent_mcp_toml_block() {
  cat <<TOML
$(agent_mcp_toml_begin "$1")
[mcp_servers.$(agent_mcp_name "$1")]
command = "$(agent_dev_command)"
args = $(agent_mcp_args_list "$1")
$(agent_mcp_toml_end "$1")
TOML
}

agent_mcp_toml_strip() {
  local kind="$1" file="$2" tmp
  tmp="$(mktemp)"
  # Linhas em branco só saem antes de outra linha: as que precedem o bloco do
  # dev e as do fim do arquivo somem junto com ele.
  awk -v begin="$(agent_mcp_toml_begin "$kind")" -v end="$(agent_mcp_toml_end "$kind")" '
    skip { if ($0 == end) skip = 0; next }
    $0 == begin { skip = 1; blanks = ""; next }
    /^[[:space:]]*$/ { blanks = blanks $0 "\n"; next }
    { printf "%s", blanks; blanks = ""; print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

agent_mcp_installed() {
  local kind="$1" target="$2"
  case "$target" in
    claude) [[ -f "$(agent_mcp_json_file)" ]] && agent_mcp_json has "$kind" >/dev/null 2>&1 ;;
    codex)  grep -qxF "$(agent_mcp_toml_begin "$kind")" "$(agent_mcp_toml_file)" 2>/dev/null ;;
    *)      return 1 ;;
  esac
}

agent_mcp_write() {
  local kind="$1" target="$2" name file rc=0
  name="$(agent_mcp_name "$kind")"
  case "$target" in
    claude)
      agent_mcp_json add "$kind" || rc=$?
      case "$rc" in
        0) ok "claude  .mcp.json  servidor $name" ;;
        2) warn "claude: sem Node para editar o .mcp.json — acrescente à mão:"
           agent_mcp_snippet "$kind" | sed 's/^/     /' ;;
        3) warn "claude: o .mcp.json não é JSON válido — mantido; acrescente à mão:"
           agent_mcp_snippet "$kind" | sed 's/^/     /' ;;
        4) warn "claude: o .mcp.json já tem um servidor $name que não é do dev — mantido" ;;
        *) warn "claude: não consegui editar o .mcp.json" ;;
      esac ;;
    codex)
      file="$(agent_mcp_toml_file)"
      mkdir -p "$(dirname "$file")"
      touch "$file"
      agent_mcp_toml_strip "$kind" "$file"
      if grep -q "^\[mcp_servers\.$name\]" "$file"; then
        warn "codex: o .codex/config.toml já tem um servidor $name que não é do dev — mantido"
        return 0
      fi
      [[ -s "$file" ]] && printf '\n' >> "$file"
      agent_mcp_toml_block "$kind" >> "$file"
      ok "codex  .codex/config.toml  servidor $name"
      hint "o Codex só lê o config.toml do projeto quando o projeto é confiável (trusted)" ;;
    antigravity)
      warn "antigravity: o MCP é configurado só na configuração global do Antigravity"
      hint "em Manage MCP Servers → View raw config, acrescente:"
      agent_mcp_snippet "$kind" | sed 's/^/     /' ;;
  esac
}

agent_mcp_remove() {
  local kind="$1" target="$2" file
  case "$target" in
    claude)
      file="$(agent_mcp_json_file)"
      [[ -f "$file" ]] && agent_mcp_json remove "$kind" >/dev/null 2>&1 || true ;;
    codex)
      file="$(agent_mcp_toml_file)"
      [[ -f "$file" ]] || return 0
      agent_mcp_toml_strip "$kind" "$file"
      if ! grep -q '[^[:space:]]' "$file"; then
        rm -f "$file"
        rmdir "$(dirname "$file")" 2>/dev/null || true
      fi ;;
  esac
  return 0
}
