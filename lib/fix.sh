#!/usr/bin/env bash
# Recuperação de máquinas e serviços em estado inconsistente.

recover_service() {
  local service="$1"
  if running "$service"; then
    printf 'up\n'
    return 0
  fi
  if adopt_orphan "$service"; then
    printf 'adopted\n'
    return 0
  fi
  local file
  file="$(pid_file "$service")"
  if [[ -f "$file" ]]; then
    rm -f "$file"
    printf 'cleaned\n'
    return 0
  fi
  printf 'stopped\n'
}

cmd_fix() {
  source "$DEV_ROOT/lib/config.sh"
  source "$DEV_ROOT/lib/services.sh"
  source "$DEV_ROOT/lib/runtime.sh"
  [[ -d "$DEV_RUNTIME" ]] || die "nada instalado ainda — rode $DEV install"

  local arg
  for arg in "$@"; do
    case "$arg" in
      -f|--force) FORCE=1 ;;
      *) die "fix não conhece $arg — só -f" ;;
    esac
  done

  local stopped=0 changed=0 locked=0

  step "SERVIÇOS"
  local nginx_bin
  nginx_bin="$(nginx_prefix)/sbin/nginx"
  if [[ -f "$nginx_bin" ]] && (( HTTP_PORT < 1024 || HTTPS_PORT < 1024 )); then
    if ! has_net_bind_capability "$nginx_bin"; then
      warn "nginx sem permissão para portas 80/443 (cap_net_bind_service)"
      if sudo -n setcap 'cap_net_bind_service=+ep' "$nginx_bin" 2>/dev/null; then
        ok "permissão 80/443 restaurada no nginx"
        changed=$(( changed + 1 ))
      elif [[ "${FORCE:-0}" == 1 ]] || confirm "restaurar permissão de porta do nginx com sudo?" s; then
        if sudo setcap 'cap_net_bind_service=+ep' "$nginx_bin" 2>/dev/null; then
          ok "permissão 80/443 restaurada no nginx"
          changed=$(( changed + 1 ))
        else
          bad "não foi possível aplicar a permissão no nginx"
          locked=$(( locked + 1 ))
        fi
      else
        hint "$DEV fix -f   confirma com root e restaura permissão"
        hint "ou execute: sudo setcap 'cap_net_bind_service=+ep' $nginx_bin"
        locked=$(( locked + 1 ))
      fi
    fi
  fi
  local services=(nginx mysql mailpit) php_runtime
  php_runtime="$(php_version "")"
  [[ -n "$php_runtime" ]] && services+=("php-fpm-$php_runtime")
  local service
  for service in "${services[@]}"; do
    case "$(recover_service "$service")" in
      up)      ok   "$(printf '%-14s %s' "$service" "de pé")" ;;
      adopted) ok   "$(printf '%-14s %s' "$service" "adotado — de pé sem pid (pid $(cat "$(pid_file "$service")" 2>/dev/null))")"
               changed=$(( changed + 1 )) ;;
      cleaned) warn "$(printf '%-14s %s' "$service" "parado — pid órfão apagado")"
               changed=$(( changed + 1 )); stopped=$(( stopped + 1 )) ;;
      *)       warn "$(printf '%-14s %s' "$service" "parado")"
               stopped=$(( stopped + 1 )) ;;
    esac
  done

  step "PORTAS"
  local port
  for port in "$HTTP_PORT" "$HTTPS_PORT" "$MYSQL_PORT" "$SMTP_PORT" "$MAILPIT_UI_PORT"; do
    if ! port_busy "$port"; then
      printf '  %s○%s  %-6s livre\n' "$C_DIM" "$C_RESET" "$port"
      continue
    fi
    port_owner "$port"
    if [[ "$OWNER_CLASS" == own ]]; then
      ok "$(printf '%-6s %s' "$port" "${OWNER_SERVICE:-$OWNER_NAME} (pid $OWNER_PID)")"
      continue
    fi
    if [[ "$FORCE" == 1 ]]; then
      if [[ "$OWNER_CLASS" == alien ]]; then
        hand_over_to_root "$port" && changed=$(( changed + 1 )) || locked=$(( locked + 1 ))
      else
        release_port "$port" && changed=$(( changed + 1 )) || locked=$(( locked + 1 ))
      fi
      continue
    fi
    warn "$(printf '%-6s %s' "$port" "$(owner_description)")"
    case "$OWNER_CLASS" in
      stack|user) hint "$DEV fix -f   encerra e devolve a porta" ;;
      *)          hint "$DEV fix -f   confirma com root e encerra"
                  [[ -n "$OWNER_REMEDY" ]] && hint "ou manualmente: $OWNER_REMEDY" ;;
    esac
    locked=$(( locked + 1 ))
  done

  blank
  if (( changed == 0 && locked == 0 && stopped == 0 )); then
    ok "nada a recuperar"; blank; return 0
  fi
  (( changed > 0 )) && ok "$changed ponto(s) recuperados"
  if (( locked > 0 )); then
    bad "$locked porta(s) continuam ocupadas"
    if [[ "$FORCE" != 1 ]]; then
      hint "$DEV fix -f   pergunta, confirma com root e encerra"
    fi
  fi
  blank
}
