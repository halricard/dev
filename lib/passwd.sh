#!/usr/bin/env bash
# Define uma nova senha para a conta de administrador da aplicação.

cmd_passwd() {
  local site="" password=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --password) password="${2:-}"; shift ;;
      -*)      die "opção desconhecida: $1" ;;
      *)       site="$1" ;;
    esac
    shift
  done

  if [[ -n "$site" ]]; then
    [[ -f "$DEV_SITES/$site" ]] || die "não há projeto chamado \"$site\" — veja \`$DEV sites\`"
    local dir
    dir="$(cat "$DEV_SITES/$site")"
    load_project "$dir" || die "o projeto $site não tem dev.conf"
  else
    require_project
  fi

  [[ -n "$PROJECT_APP" ]] || die "este projeto não declara aplicação no dev.conf — não há conta para trocar"
  load_recipe "$PROJECT_APP" || die "não sei trocar a senha de $PROJECT_APP"

  declare -F recipe_change_password >/dev/null \
    || die "$PROJECT_APP não tem conta de administrador própria — quem usa se cadastra pela aplicação"

  [[ -n "$password" ]] || password="$(random_password)"
  local user="${DEFAULT_ADMIN:-admin}"

  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  running mysql || die "o MySQL está parado — rode \`$DEV start\`"

  recipe_change_password "$PROJECT_DIR" "$user" "$password" \
    || die "não consegui trocar a senha"

  local identity="$user"
  declare -F recipe_identity >/dev/null && identity="$(recipe_identity "$user")"

  blank
  ok "senha trocada em $PROJECT_NAME"
  printf '  %s%s%s / %s%s%s\n' "$C_BOLD" "$identity" "$C_RESET" "$C_BOLD" "$password" "$C_RESET"
  hint "vale agora; não fica guardada em lugar nenhum"
  blank
}
