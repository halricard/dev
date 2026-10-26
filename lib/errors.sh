#!/usr/bin/env bash
# O que a aplicação mostra na tela quando erra.

cmd_errors() {
  require_project
  local action="${1:-}"
  case "$action" in
    "")      errors_state ;;
    on|off)  errors_set "$action" ;;
    *)       die "uso: ${DEV_COMMAND:-$DEV errors} [on|off]" ;;
  esac
}

errors_state() {
  step "ERROS NA TELA · $PROJECT_NAME"
  if [[ -f "$DEV_QUIET/$PROJECT_NAME" ]]; then
    info "off — nada aparece na tela"
    hint "$DEV logs    é onde eles estão, agrupados"
    hint "$DEV errors on   volta a mostrar"
  else
    ok "on — a aplicação decide o que mostrar"
    hint "$DEV errors off   cala a tela; o log continua completo"
  fi
  blank
}

errors_set() {
  local action="$1"
  if [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
  fi
  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi

  mkdir -p "$DEV_QUIET"
  if [[ "$action" == off ]]; then
    : > "$DEV_QUIET/$PROJECT_NAME"
  else
    rm -f "$DEV_QUIET/$PROJECT_NAME"
  fi

  write_vhost "$PROJECT_NAME" "$PROJECT_DIR/${PROJECT_DOCROOT:-.}" \
    "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}"
  if [[ -f "$DEV_ROOT/lib/project.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/project.sh"
    reload_nginx
  fi

  local version pid
  version="$(php_version "${PROJECT_PHP:-}")"
  pid="$DEV_RUN/php-fpm-$version.pid"
  [[ -f "$pid" ]] && kill -USR2 "$(cat "$pid")" 2>/dev/null || true

  step "ERROS NA TELA · $PROJECT_NAME"
  if [[ "$action" == off ]]; then
    ok "off"
    hint "vale para qualquer erro, inclusive fatal — uma página em branco"
    hint "$DEV logs   mostra o que aconteceu, agrupado por mensagem"
  else
    ok "on"
    hint "a aplicação volta a decidir o modo de depuração em tela"
  fi
  blank
}
