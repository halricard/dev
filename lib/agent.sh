#!/usr/bin/env bash
# Instruções para agentes de IA: gera a skill "dev" dentro do projeto.
#
# Claude Code, Codex e Antigravity leem o mesmo formato (pasta com SKILL.md);
# só o diretório muda. A tabela fica em agent_target_dir.

# shellcheck source=lib/project.sh
source "$DEV_ROOT/lib/project.sh"

AGENT_TARGETS=(claude codex antigravity)
AGENT_MARKER="generated-by: dev agent"

cmd_agent() {
  local subcmd="${1:-list}"; shift || true
  case "$subcmd" in
    add)             agent_add "$@" ;;
    remove|rm)       agent_remove "$@" ;;
    update)          agent_update "$@" ;;
    list)            agent_list "$@" ;;
    *)               die "uso: ${DEV_COMMAND:-$DEV agent} add [claude|codex|antigravity|all] | remove [alvo] | update | list" ;;
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
  text="${text//\{\{PROJECT\}\}/$PROJECT_NAME}"
  text="${text//\{\{APP_TITLE\}\}/$(agent_app_title)}"
  text="${text//\{\{PHP\}\}/${PROJECT_PHP:-$(config_get DEFAULT_PHP)}}"
  text="${text//\{\{DATABASE\}\}/${PROJECT_DATABASE:-none}}"
  text="${text//\{\{DOCROOT\}\}/$PROJECT_DOCROOT}"
  text="${text//\{\{URL\}\}/$(site_url "$PROJECT_NAME")}"
  text="${text//\{\{APP_NOTES\}\}/$notes}"
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
  local picked target
  local targets=()
  picked="$(agent_pick add "${1:-}" "${AGENT_TARGETS[@]}")" || exit 1
  mapfile -t targets <<< "$picked"

  step "SKILL DO DEV PARA AGENTES"
  agent_install_targets "${targets[@]}"
  blank
  hint "a skill descreve este projeto ($PROJECT_NAME); regenere após mudar o dev.conf: $DEV agent update"
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
  local dir
  for target in "${targets[@]}"; do
    if ! agent_installed "$target"; then
      info "$target: nada gerado pelo dev para remover"
      continue
    fi
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
    printf '  %b  %-14s %-26s %b\n' "$mark" "$target" "$(agent_target_dir "$target")/SKILL.md" "$status_label"
  done
  blank
  hint "gere com: $DEV agent add [claude|codex|antigravity|all]"
  blank
}
