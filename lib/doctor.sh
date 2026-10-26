#!/usr/bin/env bash
# Diagnóstico de integridade do ambiente e serviços.

present() {
  local label="$1" file="$2" version="${3:-}"
  if [[ -n "$file" && -f "$file" ]]; then
    ok "$(printf '%-10s %s' "$label" "${version:+$version }presente")"
  else
    warn "$(printf '%-10s %s' "$label" "ausente")"
    problems=$(( problems + 1 ))
  fi
}

runtime_line() {
  local comp="$1" label="$2"
  if runtime_installed "$comp"; then
    ok "$(printf '%-10s %s' "$label" "$(runtime_version "$comp") (instalado)")"
  else
    warn "$(printf '%-10s %s' "$label" "não instalado")"
    problems=$(( problems + 1 ))
  fi
}

cmd_doctor() {
  source "$DEV_ROOT/lib/config.sh"
  source "$DEV_ROOT/lib/services.sh"
  source "$DEV_ROOT/lib/runtime.sh"
  local problems=0 missing_command=0

  step "INSTALAÇÃO"
  if [[ -d "$DEV_RUNTIME" ]]; then
    ok "sandbox  $DEV_HOME  $(du -sh "$DEV_HOME" 2>/dev/null | cut -f1 || true)"
  else
    bad "nada instalado"; hint "$DEV install"; return 1
  fi
  runtime_line php PHP
  runtime_line nginx nginx
  if runtime_installed nginx; then
    local nginx_bin
    nginx_bin="$(nginx_prefix)/sbin/nginx"
    if (( HTTP_PORT < 1024 || HTTPS_PORT < 1024 )); then
      if has_net_bind_capability "$nginx_bin"; then
        ok "$(printf '%-10s %s' "portas" "permissão 80/443 ativa no nginx")"
      else
        warn "$(printf '%-10s %s' "portas" "nginx sem permissão para portas 80/443")"
        hint "$DEV fix   reaplica permissão no binário"
        hint "ou execute: sudo setcap 'cap_net_bind_service=+ep' $nginx_bin"
        problems=$(( problems + 1 ))
      fi
    fi
  fi
  present "MySQL"    "$(mysql_prefix)/bin/mysqld"            "$(config_get MYSQL_VERSION)"
  present "Node"     "$(node_bin 2>/dev/null || true)"       "$(config_get DEFAULT_NODE)"
  present "Mailpit"  "$DEV_RUNTIME/mailpit/bin/mailpit"     "$MAILPIT_VERSION"
  present "Adminer"  "$DEV_HOME/adminer/adminer.php"        "$ADMINER_VERSION"
  present "Composer" "$DEV_RUNTIME/composer/composer.phar"  "$COMPOSER_VERSION"

  if [[ "$DEV" == dev ]]; then
    ok "$(printf '%-10s %s' "comando" "dev no PATH")"
  else
    warn "$(printf '%-10s %s' "comando" "dev não está no PATH")"
    hint "$DEV install   põe o link de volta"
    missing_command=1
  fi

  step "SERVIÇOS"
  local services=(nginx mysql mailpit) php_runtime
  php_runtime="$(php_version "")"
  [[ -n "$php_runtime" ]] && services+=("php-fpm-$php_runtime")
  local service
  for service in "${services[@]}"; do
    if running "$service"; then ok "$service"
    else warn "$service parado"; problems=$(( problems + 1 )); fi
  done
  (( problems > 0 )) && hint "$DEV start"

  step "PORTAS"
  local port
  for port in "$HTTP_PORT" "$HTTPS_PORT" "$MYSQL_PORT" "$SMTP_PORT" "$MAILPIT_UI_PORT"; do
    if ! port_busy "$port"; then
      printf '  %s○%s  %-6s livre\n' "$C_DIM" "$C_RESET" "$port"
      continue
    fi
    port_owner "$port"
    case "$OWNER_CLASS" in
      own)
        ok "$(printf '%-6s %s' "$port" "${OWNER_SERVICE:-$OWNER_NAME}")" ;;
      stack)
        warn "$(printf '%-6s %s' "$port" "outra pilha ocupa a porta — $DEV start -f assume")" ;;
      *)
        bad "$(printf '%-6s %s' "$port" "ocupada por $(owner_description)")"
        [[ -n "$OWNER_REMEDY" ]] && hint "$OWNER_REMEDY"
        hint "$DEV fix   recupera o que for do dev"
        problems=$(( problems + 1 )) ;;
    esac
  done

  step "CERTIFICADO"
  if [[ -f "$LEAF_CRT" ]]; then
    local expires days
    expires="$(openssl x509 -in "$LEAF_CRT" -noout -enddate 2>/dev/null | cut -d= -f2 || true)"
    days=0
    [[ -n "$expires" ]] && days=$(( ( $(date -d "$expires" +%s) - $(date +%s) ) / 86400 ))
    if [[ -z "$expires" ]]; then
      warn "não consegui ler a validade"; hint "$DEV install"
    elif (( days < 0 )); then
      bad "vencido há $(( -days )) dias"; hint "$DEV start  reemite"
      problems=$(( problems + 1 ))
    else
      ok "certificado válido por mais $days dias"
    fi
  else
    warn "certificado de site ausente"; hint "$DEV install"
    problems=$(( problems + 1 ))
  fi

  blank
  problems=$(( problems + missing_command ))
  if (( problems == 0 )); then
    ok "tudo saudável"
  else
    warn "$problems problema(s) apontado(s)"
  fi
  blank
}
