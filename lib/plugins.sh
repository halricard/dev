#!/usr/bin/env bash
# Gerenciamento de plugins de aplicação (WordPress, Laravel, Moodle).

cmd_plugin() {
  local subcmd="${1:-list}"; shift || true
  case "$subcmd" in
    list)            plugin_list "$@" ;;
    install)         plugin_install "$@" ;;
    remove|uninstall) plugin_remove "$@" ;;
    status)          plugin_status "$@" ;;
    *)               die "uso: ${DEV_COMMAND:-$DEV plugin} list | install <nome> | remove <nome>" ;;
  esac
}

available_plugins() {
  local dir name
  for dir in "$DEV_ROOT/plugins"/*; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    printf '%s\n' "$name"
  done
}

plugin_installed() {
  [[ -d "$DEV_PLUGINS/installed/$1" ]]
}

plugin_title() {
  local name="$1" title=""
  if [[ -f "$DEV_ROOT/plugins/$name/recipe.sh" ]]; then
    title="$(grep -oP 'recipe_title\(\)\s*\{\s*echo\s*"\K[^"]*' "$DEV_ROOT/plugins/$name/recipe.sh" 2>/dev/null || true)"
  fi
  printf '%s\n' "${title:-$name}"
}

plugin_list() {
  step "PLUGINS DE APLICAÇÃO"
  local name mark status_label title
  local found=0

  for name in $(available_plugins); do
    found=1
    title="$(plugin_title "$name")"
    if plugin_installed "$name"; then
      mark="${C_GREEN}✔${C_RESET}"
      status_label="${C_GREEN}instalado${C_RESET}"
    else
      mark="${C_DIM}○${C_RESET}"
      status_label="${C_DIM}disponível${C_RESET}"
    fi
    printf '  %b  %-14s %-24s %b\n' "$mark" "$name" "$title" "$status_label"
  done

  if (( ! found )); then
    hint "nenhum plugin disponível no catálogo"
  else
    blank
    hint "instale uma aplicação com: $DEV plugin install <nome>"
    hint "crie um projeto com:      $DEV new <app> <nome>"
  fi
  blank
}

plugin_install() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "uso: ${DEV_COMMAND:-$DEV plugin install} <nome>"

  local src="$DEV_ROOT/plugins/$name"
  [[ -d "$src" ]] || die "plugin \"$name\" não encontrado no catálogo"

  mkdir -p "$DEV_PLUGINS/installed"

  if plugin_installed "$name"; then
    ok "plugin \"$name\" já está instalado"
    blank
    return 0
  fi

  step "INSTALANDO PLUGIN $name"

  if [[ -f "$src/plugin.sh" ]]; then
    # shellcheck source=/dev/null
    source "$src/plugin.sh"
    if declare -F plugin_pre_install >/dev/null; then
      plugin_pre_install || die "falha na pré-instalação do plugin $name"
    fi
  fi

  local target="$DEV_PLUGINS/installed/$name"
  mkdir -p "$target"
  cp -r "$src"/* "$target/"

  if [[ -f "$target/plugin.sh" ]]; then
    # shellcheck source=/dev/null
    source "$target/plugin.sh"
    if declare -F plugin_install >/dev/null; then
      plugin_install || { rm -rf "$target"; die "falha ao instalar o plugin $name"; }
    fi
  fi

  date +%s > "$target/.installed"

  ok "plugin \"$name\" instalado com sucesso"
  blank
  hint "crie um novo projeto agora com: $DEV new $name <nome-do-site>"
  blank
}

plugin_remove() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "uso: ${DEV_COMMAND:-$DEV plugin remove} <nome>"

  local target="$DEV_PLUGINS/installed/$name"
  [[ -d "$target" ]] || die "o plugin \"$name\" não está instalado"

  step "REMOVENDO PLUGIN $name"

  if [[ -f "$target/plugin.sh" ]]; then
    # shellcheck source=/dev/null
    source "$target/plugin.sh"
    if declare -F plugin_remove >/dev/null; then
      plugin_remove || true
    fi
  fi

  rm -rf "$target"

  ok "plugin \"$name\" removido com sucesso"
  hint "projetos existentes continuam intactos no disco"
  blank
}

plugin_status() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "uso: ${DEV_COMMAND:-$DEV plugin status} <nome>"

  local src="$DEV_ROOT/plugins/$name"
  [[ -d "$src" || -d "$DEV_PLUGINS/installed/$name" ]] || die "plugin \"$name\" não existe"

  step "PLUGIN $name"
  label "nome" "$name"
  label "título" "$(plugin_title "$name")"
  if plugin_installed "$name"; then
    label "status" "${C_GREEN}instalado${C_RESET}"
    local when
    when="$(cat "$DEV_PLUGINS/installed/$name/.installed" 2>/dev/null || echo 0)"
    if (( when > 0 )); then
      label "instalado em" "$(date -d "@$when" '+%d/%m/%Y %H:%M' 2>/dev/null || date -r "$when" 2>/dev/null || true)"
    fi
  else
    label "status" "${C_DIM}não instalado (disponível)${C_RESET}"
  fi
  blank
}
