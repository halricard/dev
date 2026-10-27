#!/usr/bin/env bash
# Gerenciamento de daemons, processos e portas sem systemd.

FORCE="${DEV_FORCE:-0}"

pid_file() { printf '%s\n' "$DEV_RUN/$1.pid"; }

running() {
  local file
  file="$(pid_file "$1")"
  [[ -f "$file" ]] || return 1
  local pid
  pid="$(cat "$file" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

port_busy() {
  ss -ltn "sport = :$1" 2>/dev/null | tail -n +2 | grep -q .
}

OWNER_PID=""
OWNER_NAME=""
OWNER_USER=""
OWNER_CLASS="free"
OWNER_SERVICE=""
OWNER_REMEDY=""

port_owner() {
  local port="$1" line pid exe stack
  OWNER_PID=""; OWNER_NAME=""; OWNER_USER=""; OWNER_SERVICE=""; OWNER_REMEDY=""
  OWNER_CLASS="free"

  port_busy "$port" || return 1
  OWNER_CLASS="alien"

  line="$(ss -ltnp "sport = :$port" 2>/dev/null | tail -n +2 | head -1 || true)"
  pid="$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1 || true)"

  if [[ -z "$pid" ]]; then
    line="$(sudo -n ss -ltnp "sport = :$port" 2>/dev/null | tail -n +2 | head -1 || true)"
    pid="$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1 || true)"
  fi

  [[ -n "$pid" ]] || { guess_owner "$port"; return 0; }

  OWNER_PID="$(master_of "$pid")"
  OWNER_NAME="$(cat "/proc/$OWNER_PID/comm" 2>/dev/null || echo '?')"
  OWNER_USER="$(stat -c %U "/proc/$OWNER_PID" 2>/dev/null || echo '?')"
  exe="$(process_exe "$OWNER_PID")"

  local expected_service
  expected_service="$(service_of_port "$port")"
  if [[ -n "$expected_service" && -f "$(pid_file "$expected_service")" ]] \
     && [[ "$OWNER_PID" == "$(cat "$(pid_file "$expected_service")" 2>/dev/null || true)" ]] \
     && kill -0 "$OWNER_PID" 2>/dev/null; then
    OWNER_CLASS="own"
    OWNER_SERVICE="$expected_service"
    return 0
  fi

  if [[ -n "$exe" && "$exe" == "$DEV_RUNTIME"/* ]]; then
    OWNER_CLASS="own"
    OWNER_SERVICE="$(service_of_exe "$exe")"
    [[ -z "$OWNER_SERVICE" && -n "$expected_service" ]] && OWNER_SERVICE="$expected_service"
  elif [[ "$OWNER_USER" == "$USER" ]]; then
    stack="$(stack_root_of_process "$OWNER_PID" || true)"
    if [[ -n "$stack" ]]; then
      OWNER_CLASS="stack"
    else
      OWNER_CLASS="user"
      OWNER_REMEDY="kill $OWNER_PID"
    fi
  else
    OWNER_CLASS="alien"
    OWNER_REMEDY="$(owner_remedy "$OWNER_NAME" "$OWNER_PID")"
  fi
  return 0
}

stack_root_of() {
  local path="$1" home real_runtime root
  home="$(readlink -f "$HOME" 2>/dev/null || printf '%s\n' "$HOME")"

  case "$path" in
    *"$home"/*) path="$home/${path#*"$home"/}" ;;
    *) return 0 ;;
  esac

  case "$path" in
    "$home"/*/runtime/*) ;;
    *) return 0 ;;
  esac

  case "$path" in
    "$DEV_RUNTIME"/*) return 0 ;;
  esac
  real_runtime="$(readlink -f "$DEV_RUNTIME" 2>/dev/null || true)"
  if [[ -n "$real_runtime" ]]; then
    case "$path" in
      "$real_runtime"/*) return 0 ;;
    esac
  fi

  root="$home/${path#"$home"/}"
  root="${root%%/runtime/*}"

  [[ -d "$root/etc" && -d "$root/services" && -d "$root/sites" ]] || return 0
  printf '%s\n' "$root"
}

stack_root_of_process() {
  local pid="$1" root part
  [[ "$(stat -c %U "/proc/$pid" 2>/dev/null || true)" == "$USER" ]] || return 1

  root="$(stack_root_of "$(process_exe "$pid")")"
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi

  while IFS= read -r part; do
    [[ -n "$part" ]] || continue
    root="$(stack_root_of "$part")"
    if [[ -n "$root" ]]; then
      printf '%s\n' "$root"
      return 0
    fi
  done < <(process_argv "$pid")
  return 1
}

process_argv() {
  tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null || true
}

service_of_port() {
  case "$1" in
    "$HTTP_PORT"|"$HTTPS_PORT")      printf 'nginx\n' ;;
    "$MYSQL_PORT")                   printf 'mysql\n' ;;
    "$SMTP_PORT"|"$MAILPIT_UI_PORT") printf 'mailpit\n' ;;
  esac
}

port_uid() {
  local hex
  hex="$(printf '%04X' "$1")"
  awk -v p=":$hex" '$4=="0A" && index($2,p)==length($2)-length(p)+1 {print $8; exit}' \
    /proc/net/tcp /proc/net/tcp6 2>/dev/null || true
}

guess_owner() {
  local port="$1" service uid pid=""
  OWNER_CLASS="alien"

  uid="$(port_uid "$port")"
  if [[ -n "$uid" ]]; then
    OWNER_USER="$(getent passwd "$uid" 2>/dev/null | cut -d: -f1 || true)"
    [[ -n "$OWNER_USER" ]] || OWNER_USER="uid $uid"
  else
    if is_wsl; then
      OWNER_USER="fora do Linux"
      OWNER_NAME="porta do Windows, espelhada pelo WSL2"
      OWNER_REMEDY="no PowerShell: netstat -ano | findstr :$port"
    else
      OWNER_USER="outro namespace de rede"
      OWNER_NAME="provavelmente um contêiner"
      OWNER_REMEDY="veja com: docker ps ou podman ps"
    fi
    return 0
  fi

  if [[ "$uid" == "$(id -u)" ]]; then
    service="$(service_of_port "$port")"
    if [[ -n "$service" ]]; then
      if running "$service"; then pid="$(cat "$(pid_file "$service")" 2>/dev/null || true)"
      else pid="$(find_own_process "$service" || true)"; fi
      if [[ -n "$pid" ]]; then
        OWNER_CLASS="own"; OWNER_SERVICE="$service"; OWNER_PID="$pid"; OWNER_NAME="$service"
        return 0
      fi
    fi
  fi

  if pgrep -af docker-proxy 2>/dev/null | grep -q -- "-host-port $port"; then
    OWNER_NAME="um contêiner publicando a porta (docker-proxy)"
    OWNER_REMEDY="docker ps e então docker stop <contêiner>"
    return 0
  fi

  if [[ "$port" == "$HTTP_PORT" || "$port" == "$HTTPS_PORT" ]] \
     && command -v systemctl >/dev/null 2>&1; then
    for service in nginx apache2 httpd caddy lighttpd traefik; do
      if [[ "$(systemctl is-active "$service" 2>/dev/null || true)" == "active" ]]; then
        OWNER_NAME="provavelmente o $service do sistema"
        OWNER_REMEDY="sudo systemctl disable --now $service"
        return 0
      fi
    done
  fi

  OWNER_NAME="um processo que o ss não mostra"
  OWNER_REMEDY="sudo ss -lptn 'sport = :$port' mostra qual é"
}

owner_description() {
  if [[ -n "$OWNER_PID" ]]; then
    printf '%s (pid %s, %s)\n' "$OWNER_NAME" "$OWNER_PID" "$OWNER_USER"
  elif [[ -n "$OWNER_USER" ]]; then
    printf '%s (%s)\n' "$OWNER_NAME" "$OWNER_USER"
  else
    printf '%s\n' "$OWNER_NAME"
  fi
}

owner_remedy() {
  case "$1" in
    nginx|apache2|httpd|caddy|lighttpd|traefik)
      printf 'sudo systemctl disable --now %s\n' "$1" ;;
    docker-proxy|dockerd)
      printf 'docker ps e então docker stop <contêiner>\n' ;;
    *)
      printf 'sudo kill %s\n' "$2" ;;
  esac
}

process_exe() {
  local pid="$1" exe part parts=() real
  exe="$(readlink -e "/proc/$pid/exe" 2>/dev/null || true)"
  if [[ -n "$exe" && "$exe" != "/proc/"* ]]; then
    real="$(readlink -f "$DEV_RUNTIME" 2>/dev/null || true)"
    [[ -n "$real" && "$real" != "$DEV_RUNTIME" && "$exe" == "$real"/* ]] \
      && exe="$DEV_RUNTIME/${exe#"$real"/}"
    printf '%s\n' "$exe"
    return 0
  fi
  [[ "$(stat -c %U "/proc/$pid" 2>/dev/null || true)" == "$USER" ]] || return 0
  read -ra parts <<<"$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  for part in "${parts[@]}"; do
    [[ "$part" == "$DEV_RUNTIME"/* ]] && { printf '%s\n' "$part"; return 0; }
  done
  return 0
}

master_of() {
  local pid="$1" mark parent parent_mark
  mark="$(process_mark "$pid")"
  [[ -n "$mark" ]] || { printf '%s\n' "$pid"; return 0; }
  while :; do
    parent="$(awk '/^PPid:/{print $2}' "/proc/$pid/status" 2>/dev/null || true)"
    [[ -n "$parent" && "$parent" != 0 && "$parent" != 1 ]] || break
    parent_mark="$(process_mark "$parent")"
    [[ -n "$parent_mark" && "$parent_mark" == "$mark" ]] || break
    pid="$parent"
  done
  printf '%s\n' "$pid"
}

process_mark() {
  local exe
  exe="$(readlink -e "/proc/$1/exe" 2>/dev/null || true)"
  if [[ -n "$exe" && "$exe" != "/proc/"* ]]; then
    printf 'exe:%s\n' "$exe"
    return 0
  fi
  exe="$(cat "/proc/$1/comm" 2>/dev/null || true)"
  [[ -n "$exe" ]] && printf 'comm:%s\n' "$exe"
  return 0
}

pid_unit() {
  grep -oP '/[^/]+\.service' "/proc/$1/cgroup" 2>/dev/null | tail -1 | sed 's|^/||' || true
}

service_of_exe() {
  local version
  case "$1" in
    "$DEV_RUNTIME"/nginx/*)   printf 'nginx\n' ;;
    "$DEV_RUNTIME"/mysql/*)   printf 'mysql\n' ;;
    "$DEV_RUNTIME"/mailpit/*) printf 'mailpit\n' ;;
    "$DEV_RUNTIME"/php/*)
      version="${1#"$DEV_RUNTIME"/php/}"
      printf 'php-fpm-%s\n' "${version%%/*}" ;;
    *) printf '\n' ;;
  esac
}

adopt_process() {
  printf '%s\n' "$2" > "$(pid_file "$1")"
}

find_own_process() {
  local target="$1" pid exe
  for pid in $(ps -u "$USER" -o pid= 2>/dev/null || true); do
    exe="$(process_exe "$pid")"
    [[ -n "$exe" && "$exe" == "$DEV_RUNTIME"/* ]] || continue
    [[ "$(service_of_exe "$exe")" == "$target" ]] || continue
    [[ "$(master_of "$pid")" == "$pid" ]] || continue
    printf '%s\n' "$pid"
    return 0
  done
  return 1
}

kill_process() {
  local pid="$1" i=0
  kill "$pid" 2>/dev/null || return 1
  while (( i < 100 )); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1; i=$(( i + 1 ))
  done
  kill -9 "$pid" 2>/dev/null || true
  sleep 0.2
  ! kill -0 "$pid" 2>/dev/null
}

adopt_orphan() {
  local service="$1" found
  running "$service" && return 0
  found="$(find_own_process "$service" || true)"
  [[ -n "$found" ]] || return 1
  adopt_process "$service" "$found"
  return 0
}

release_port() {
  local port="$1"
  port_busy "$port" || return 0
  port_owner "$port"
  case "$OWNER_CLASS" in
    own|stack|user)
      if kill_process "$OWNER_PID"; then
        ok "porta $port liberada — era $OWNER_NAME (pid $OWNER_PID)"
        if [[ "$OWNER_CLASS" == own && -n "$OWNER_SERVICE" ]]; then
          rm -f "$(pid_file "$OWNER_SERVICE")"
        fi
        return 0
      fi
      bad "porta $port: não consegui encerrar $OWNER_NAME (pid $OWNER_PID)"
      return 1 ;;
    *)
      if [[ -t 0 ]]; then
        hand_over_to_root "$port"
        return $?
      fi
      bad "porta $port ocupada por $(owner_description)"
      hint "não é do dev, e o dev não roda como root"
      [[ -n "$OWNER_REMEDY" ]] && hint "$OWNER_REMEDY"
      return 1 ;;
  esac
}

hand_over_to_root() {
  local port="$1" answer line pid name unit
  bad "a porta $port é de um processo de $OWNER_USER — $OWNER_NAME"
  hint "o dev não roda como root, e daqui não dá nem para ver qual processo é"
  blank
  printf '  %s─  posso rodar sudo ss -lptn para descobrir de quem é? [s/N] %s' "$C_DIM" "$C_RESET"
  read -r answer || { blank; return 1; }
  if [[ ! "$answer" =~ ^[sSyY] ]]; then
    hint "ok, nada foi feito"
    [[ -n "$OWNER_REMEDY" ]] && hint "$OWNER_REMEDY"
    return 1
  fi

  line="$(sudo ss -lptn "sport = :$port" 2>/dev/null | tail -n +2 | head -1 || true)"
  pid="$(grep -oP 'pid=\K[0-9]+' <<<"$line" | head -1 || true)"
  if [[ -z "$pid" ]]; then
    bad "nem com root apareceu processo nesta porta"
    if is_wsl; then
      hint "no WSL2 isso quer dizer Windows — no PowerShell: netstat -ano | findstr :$port"
    else
      hint "provavelmente um contêiner — veja com docker ps ou podman ps"
    fi
    return 1
  fi

  pid="$(master_of "$pid")"
  name="$(cat "/proc/$pid/comm" 2>/dev/null || echo '?')"
  unit="$(pid_unit "$pid")"

  if [[ -z "$unit" ]]; then
    ok "é o $name (pid $pid) — sem unidade do systemd atrás"
    confirm_and_run "$port" "encerrar o $name" sudo kill "$pid"
    return $?
  fi
  ok "é o $name (pid $pid), do $unit"
  confirm_and_run "$port" "encerrar o $unit e tirá-lo do boot" \
    sudo systemctl disable --now "$unit"
}

confirm_and_run() {
  local port="$1" what="$2" answer
  shift 2
  blank
  hint "$what:"
  printf '     %s%s%s\n' "$C_BOLD" "$*" "$C_RESET"
  printf '  %s─  rodar? [s/N] %s' "$C_DIM" "$C_RESET"
  read -r answer || { blank; return 1; }
  [[ "$answer" =~ ^[sSyY] ]] || { hint "ok, nada foi feito"; return 1; }
  "$@" || { bad "o comando falhou"; return 1; }
  sleep 0.5
  if port_busy "$port"; then
    bad "o comando rodou, mas a porta $port continua ocupada"
    hint "então o dono era outro — rode $DEV fix -f de novo"
    return 1
  fi
  ok "porta $port liberada"
  return 0
}

port_conflict() {
  local port="$1" service="$2" line
  shift 2
  if [[ "$FORCE" == 1 ]]; then
    release_port "$port" && return 0
    return 1
  fi
  port_owner "$port"
  bad "a porta $port está ocupada por $(owner_description)"
  for line in "$@"; do hint "$line"; done
  case "$OWNER_CLASS" in
    own|stack|user)
      hint "$DEV start -f   encerra e sobe o $service no lugar" ;;
    *)
      hint "não é do dev, e o dev não roda como root"
      [[ -n "$OWNER_REMEDY" ]] && hint "$OWNER_REMEDY" ;;
  esac
  return 1
}

stack_ports() {
  printf '%s\n' "$HTTP_PORT" "$HTTPS_PORT" "$MYSQL_PORT" "$SMTP_PORT" "$MAILPIT_UI_PORT"
}

take_over_ports() {
  local port failed=0
  while IFS= read -r -u 3 port; do
    [[ -n "$port" ]] || continue
    port_busy "$port" || continue
    port_owner "$port"
    case "$OWNER_CLASS" in
      own) ;;
      stack)
        if kill_process "$OWNER_PID"; then
          warn "porta $port em uso por outra pilha de desenvolvimento (pid $OWNER_PID) — encerrada"
        else
          bad "porta $port: não consegui encerrar $(owner_description)"
          failed=1
        fi ;;
      user)
        if confirm "encerrar o processo da porta $port? ($(owner_description))" s; then
          if kill_process "$OWNER_PID"; then
            ok "porta $port liberada — era $(owner_description)"
          else
            bad "porta $port: não consegui encerrar $(owner_description)"
            failed=1
          fi
        else
          warn "porta $port continua ocupada por $(owner_description)"
          failed=1
        fi ;;
      *)
        bad "porta $port ocupada por $(owner_description)"
        hint "não é do dev, e o dev não roda como root"
        [[ -n "$OWNER_REMEDY" ]] && hint "$OWNER_REMEDY"
        failed=1 ;;
    esac
  done 3< <(stack_ports)
  (( failed == 0 ))
}

stack_holds_ports() {
  local port
  while IFS= read -r port; do
    [[ -n "$port" ]] || continue
    port_busy "$port" || continue
    port_owner "$port"
    if [[ "$OWNER_CLASS" == "stack" ]]; then
      return 0
    fi
  done < <(stack_ports)
  return 1
}

wait_for_file() {
  local target="$1" limit="${2:-30}" i=0
  while (( i < limit * 10 )); do
    [[ -e "$target" ]] && return 0
    sleep 0.1; i=$(( i + 1 ))
  done
  return 1
}

start_mysql() {
  running mysql && return 0
  local prefix
  prefix="$(mysql_prefix)"
  [[ -x "$prefix/bin/mysqld" ]] || die "MySQL não está instalado — rode $DEV install"
  sandbox_libs
  adopt_orphan mysql && return 0
  if port_busy "$MYSQL_PORT"; then
    port_conflict "$MYSQL_PORT" mysql || return 1
  fi
  nohup "$prefix/bin/mysqld" --defaults-file="$DEV_ETC/my.cnf" --user="$USER" \
    >/dev/null 2>&1 &
  echo $! > "$(pid_file mysql)"
  wait_for_file "$DEV_RUN/mysql.sock" 40 \
    || die "o MySQL não subiu; veja $DEV_LOG/mysql.log"
}

ensure_mysql_password() {
  [[ "$(config_get MYSQL_PASSWORD_APPLIED)" == "1" ]] && return 0
  running mysql || return 0
  [[ -x "$(mysql_prefix)/bin/mysql" ]] || return 0
  [[ -n "$(config_get MYSQL_PASSWORD)" ]] || return 0
  if [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
    set_mysql_root_password
    config_set MYSQL_PASSWORD_APPLIED 1
  fi
}

start_single_fpm() {
  local version="$1" service bin
  service="php-fpm-$version"
  running "$service" && return 0
  adopt_orphan "$service" && return 0
  bin="$(php_prefix "$version")/sbin/php-fpm"
  [[ -x "$bin" ]] || die "PHP $version não está instalado — rode $DEV install"
  "$bin" --fpm-config "$DEV_ETC/php/$version/php-fpm.conf" -c "$DEV_ETC/php/$version/php.ini" \
    >/dev/null 2>&1 || die "o php-fpm $version não subiu; veja $DEV_LOG/php-fpm-$version.log"
  wait_for_file "$(fpm_socket "$version")" 10 \
    || die "o socket do php-fpm $version não apareceu"
}

start_fpm() {
  local target="${1:-}"
  if [[ -n "$target" ]]; then
    start_single_fpm "$target"
    return $?
  fi

  local ver all_ok=1
  while IFS= read -r ver; do
    [[ -n "$ver" ]] || continue
    start_single_fpm "$ver" || all_ok=0
  done < <(active_php_versions)
  (( all_ok ))
}

start_nginx() {
  local prefix port
  prefix="$(nginx_prefix)"
  [[ -x "$prefix/sbin/nginx" ]] || die "nginx não está instalado — rode $DEV install"
  mkdir -p "$prefix/logs"
  if running nginx || adopt_orphan nginx; then
    refresh_nginx
    return
  fi
  for port in "$HTTP_PORT" "$HTTPS_PORT"; do
    if port_busy "$port"; then
      port_conflict "$port" nginx \
        "o dev serve sempre em 80 e 443 — porta na URL quebra vhosts locais" \
        || return 1
    fi
  done
  if (( HTTP_PORT < 1024 || HTTPS_PORT < 1024 )); then
    declare -f has_net_bind_capability >/dev/null 2>&1 || source "$DEV_ROOT/lib/runtime.sh" 2>/dev/null || true
    if declare -f has_net_bind_capability >/dev/null 2>&1; then
      if ! has_net_bind_capability "$prefix/sbin/nginx"; then
        grant_net_bind_capability "$prefix/sbin/nginx" 2>/dev/null || true
      fi
      if ! has_net_bind_capability "$prefix/sbin/nginx"; then
        bad "o nginx precisa de permissão para escutar nas portas $HTTP_PORT e $HTTPS_PORT"
        hint "execute: sudo setcap 'cap_net_bind_service=+ep' $prefix/sbin/nginx"
        hint "ou execute: $DEV fix"
        return 1
      fi
    fi
  fi
  "$prefix/sbin/nginx" -c "$DEV_ETC/nginx/nginx.conf" -p "$prefix" \
    || die "o nginx não subiu; veja $DEV_LOG/nginx-error.log"
}

nginx_on_every_interface() {
  local port address
  for port in "$HTTP_PORT" "$HTTPS_PORT"; do
    while read -r _ _ _ address _; do
      [[ "$address" == 127.0.0.1:* || "$address" == "[::1]:"* ]] || return 0
    done < <(ss -ltn "sport = :$port" 2>/dev/null | tail -n +2 || true)
  done
  return 1
}

refresh_nginx() {
  running nginx || return 0
  local prefix
  prefix="$(nginx_prefix)"
  if ! nginx_on_every_interface; then
    "$prefix/sbin/nginx" -c "$DEV_ETC/nginx/nginx.conf" -p "$prefix" -s reload 2>/dev/null || true
    return 0
  fi
  info "nginx saindo da rede para escutar só em 127.0.0.1 — reiniciando"
  kill_process "$(cat "$(pid_file nginx)" 2>/dev/null)" \
    || { bad "não consegui encerrar o nginx para reiniciá-lo"; return 1; }
  rm -f "$(pid_file nginx)"
  start_nginx
}

start_mailpit() {
  running mailpit && return 0
  adopt_orphan mailpit && return 0
  local bin
  bin="$DEV_RUNTIME/mailpit/bin/mailpit"
  [[ -x "$bin" ]] || return 0
  nohup "$bin" \
    --smtp "127.0.0.1:$SMTP_PORT" \
    --listen "127.0.0.1:$MAILPIT_UI_PORT" \
    --database "$DEV_HOME/services/mailpit.db" \
    >"$DEV_LOG/mailpit.log" 2>&1 &
  echo $! > "$(pid_file mailpit)"
}

cmd_start() {
  [[ -d "$DEV_RUNTIME" ]] || die "nada instalado ainda — rode $DEV install"

  local if_needed=0 arg
  for arg in "$@"; do
    case "$arg" in
      --if-needed)  if_needed=1 ;;
      -f|--force)   FORCE=1 ;;
      *) die "start não conhece $arg — só -f" ;;
    esac
  done

  if (( if_needed )); then
    local service_ all_up=1 ver_
    for service_ in mysql nginx mailpit; do running "$service_" || all_up=0; done
    while IFS= read -r ver_; do
      [[ -n "$ver_" ]] || continue
      running "php-fpm-$ver_" || all_up=0
    done < <(active_php_versions)
    ensure_mysql_password >&2
    (( all_up )) && return 0

    if stack_holds_ports; then
      info "outra pilha de desenvolvimento já ocupa as portas — este start sai de lado"
      return 0
    fi
  fi

  if [[ "$FORCE" == 1 ]]; then
    take_over_ports || return 1
  fi

  if [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
    write_configs >/dev/null
  fi

  step "SUBINDO"
  local failed=0 web=1
  start_mysql   && ok "MySQL     127.0.0.1:$MYSQL_PORT"           || failed=1
  if start_fpm; then
    local v_
    while IFS= read -r v_; do
      [[ -n "$v_" ]] || continue
      ok "php-fpm   $v_"
    done < <(active_php_versions)
  else
    failed=1
  fi
  start_mailpit && ok "Mailpit   https://mail.localhost"          || failed=1
  start_nginx   && ok "nginx     portas $HTTP_PORT e $HTTPS_PORT" || { failed=1; web=0; }

  if (( web )) && [[ -f "$DEV_ROOT/lib/schedule.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/schedule.sh"
    local file name count total=0 raised=0
    for file in "$DEV_SITES"/*; do
      [[ -f "$file" ]] || continue
      name="$(basename "$file")"
      load_project "$(cat "$file")" >/dev/null 2>&1 || continue
      count="$(start_site_tasks "$name" "$PROJECT_DIR" "$PROJECT_PHP" schedule)"
      total=$(( total + count ))
      if [[ -f "$DEV_UP/$name" ]]; then
        count="$(start_site_tasks "$name" "$PROJECT_DIR" "$PROJECT_PHP" worker)"
        total=$(( total + count )); raised=$(( raised + 1 ))
      fi
    done
    if (( total > 0 )); then
      local suffix=""
      (( raised > 0 )) && suffix=" · $raised up"
      ok "tarefas   $total em $(ls -1 "$DEV_SITES" 2>/dev/null | wc -l || true) projeto(s)$suffix"
    fi
  fi
  blank
  if (( failed )); then
    bad "nem tudo subiu"
    (( web )) || hint "sem o nginx no ar, as tarefas dos projetos ficaram de fora"
    hint "$DEV fix   mostra o que está no caminho e recupera os serviços"
    blank
    return 1
  fi
  ensure_mysql_password
  hint "$DEV sites   mostra o que está sendo servido"
  blank
}

cmd_stop() {
  step "ENCERRANDO"
  if [[ -f "$DEV_ROOT/lib/schedule.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/schedule.sh"
    local file
    for file in "$DEV_SITES"/*; do
      [[ -f "$file" ]] && stop_site_tasks "$(basename "$file")"
    done
  fi
  if running nginx; then
    local prefix
    prefix="$(nginx_prefix)"
    "$prefix/sbin/nginx" -c "$DEV_ETC/nginx/nginx.conf" -p "$prefix" -s quit 2>/dev/null \
      || kill "$(cat "$(pid_file nginx)" 2>/dev/null)" 2>/dev/null || true
    rm -f "$(pid_file nginx)"
    ok "nginx"
  fi
  local pidfile service ver
  for pidfile in "$DEV_RUN"/php-fpm-*.pid; do
    [[ -f "$pidfile" ]] || continue
    service="$(basename "$pidfile" .pid)"
    ver="${service#php-fpm-}"
    if running "$service"; then
      kill -QUIT "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
      rm -f "$(fpm_socket "$ver")"
      ok "php-fpm $ver"
    else
      rm -f "$pidfile"
    fi
  done
  if running mysql; then
    MYSQL_PWD="$(config_get MYSQL_PASSWORD)" \
      "$(mysql_prefix)/bin/mysqladmin" --socket="$DEV_RUN/mysql.sock" \
      -u "$(config_get MYSQL_USER)" shutdown 2>/dev/null \
      || kill "$(cat "$(pid_file mysql)")" 2>/dev/null || true
    rm -f "$(pid_file mysql)"
    ok "MySQL"
  fi
  if running mailpit; then
    kill "$(cat "$(pid_file mailpit)")" 2>/dev/null || true
    ok "Mailpit"
  fi
  rm -f "$(pid_file mailpit)"
  blank
}

cmd_restart() {
  cmd_stop
  cmd_start "$@"
}

cmd_status() {
  if [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
  fi
  local is_project=0
  if load_project >/dev/null 2>&1; then
    is_project=1
    project_status
  else
    local marker
    if marker="$(looks_like_project "$PWD")"; then
      step "AQUI"
      warn "$(basename "$PWD") tem um $marker, mas não tem dev.conf"
      hint "$DEV init   escreve o dev.conf lendo a aplicação"
      hint "$DEV up     depois, põe no ar"
    fi
  fi

  step "MÁQUINA"
  local installed_php
  installed_php="$(php_version "")"
  label "PHP"   "$installed_php"
  label "Node"  "$(config_get DEFAULT_NODE)"
  label "MySQL" "$(config_get MYSQL_VERSION)"
  label "nginx" "$(config_get NGINX_VERSION)"

  step "SERVIÇOS"
  service_state nginx   "portas $HTTP_PORT e $HTTPS_PORT"
  local ver_stat
  while IFS= read -r ver_stat; do
    [[ -n "$ver_stat" ]] || continue
    service_state "php-fpm-$ver_stat" "socket $(fpm_socket "$ver_stat")"
  done < <(active_php_versions)
  service_state mysql   "127.0.0.1:$MYSQL_PORT"
  service_state mailpit "smtp 127.0.0.1:$SMTP_PORT"

  step "NO NAVEGADOR"
  browser_line Mailpit "https://mail.localhost" \
    "e-mail que suas aplicações enviam" running mailpit
  browser_line Adminer "https://adminer.localhost" \
    "banco: entra sozinho, sem pedir senha" file "$DEV_HOME/adminer/adminer.php"

  if (( is_project )); then
    blank
    hint "$DEV sites   lista os outros projetos"
    blank
    return 0
  fi

  step "PROJETOS"
  local file name found=0
  for file in "$DEV_SITES"/*; do
    [[ -f "$file" ]] || continue
    found=1
    name="$(basename "$file")"
    printf '  %s✔%s  %-14s %shttps://%s.localhost%s   %s%s%s\n' \
      "$C_GREEN" "$C_RESET" "$name" "$C_BLUE" "$name" "$C_RESET" \
      "$C_DIM" "$(cat "$file")" "$C_RESET"
  done
  (( found )) || hint "nenhum ainda — $DEV new <app> <nome>"
  blank
}

project_status() {
  if [[ -f "$DEV_ROOT/lib/project.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/project.sh"
  fi
  local url="https://$PROJECT_NAME.localhost"
  step "PROJETO  $PROJECT_NAME"

  local code
  code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 3 "$url" 2>/dev/null || echo 000)"
  case "$code" in
    2*|3*) printf '  %s✔%s  %-12s %s%s%s   %sHTTP %s%s\n' "$C_GREEN" "$C_RESET" "no ar" \
             "$C_BLUE" "$url" "$C_RESET" "$C_DIM" "$code" "$C_RESET" ;;
    000)   printf '  %s✘%s  %-12s %s   %snão respondeu%s\n' "$C_RED" "$C_RESET" "fora do ar" \
             "$url" "$C_DIM" "$C_RESET"
           hint "$DEV up   põe este projeto no ar" ;;
    *)     printf '  %s▲%s  %-12s %s   %sHTTP %s%s\n' "$C_YELLOW" "$C_RESET" "respondendo" \
             "$url" "$C_DIM" "$code" "$C_RESET"
           hint "$DEV logs   mostra o que quebrou" ;;
  esac

  label "aplicação" "${PROJECT_APP:-PHP puro}"
  label "PHP"       "$(php_version "$PROJECT_PHP")"
  label "docroot"   "$PROJECT_DOCROOT"
  [[ -f "$DEV_QUIET/$PROJECT_NAME" ]] \
    && label "erros" "${C_YELLOW}não aparecem na tela${C_RESET}  ${C_DIM}$DEV errors on${C_RESET}"
  label "diretório" "${PROJECT_DIR/#$HOME/\~}"

  if [[ -n "$PROJECT_DATABASE" ]]; then
    label "banco" "$PROJECT_DATABASE  ${C_DIM}127.0.0.1:$MYSQL_PORT · $(config_get MYSQL_USER)${C_RESET}"
  fi
  blank
}

browser_line() {
  local name="$1" url="$2" purpose="$3" proof="$4" target="${5:-}"
  local exists=1 reason=""
  case "$proof" in
    running) running "$target" || { exists=0; reason="parado"; } ;;
    file) [[ -e "$target" ]] || { exists=0; reason="não instalado — $DEV install"; } ;;
  esac
  (( exists )) && ! running nginx && { exists=0; reason="nginx parado"; }

  if (( exists )); then
    printf '  %s✔%s  %-9s %s%-28s%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$name" \
      "$C_BLUE" "$url" "$C_RESET" "$C_DIM" "$purpose" "$C_RESET"
  else
    printf '  %s○%s  %-9s %s%-28s %s%s\n' "$C_DIM" "$C_RESET" "$name" \
      "$C_DIM" "$url" "$reason" "$C_RESET"
  fi
}

service_state() {
  if running "$1"; then
    printf '  %s✔%s  %-14s %s%s%s\n' "$C_GREEN" "$C_RESET" "$1" "$C_DIM" "$2" "$C_RESET"
  else
    printf '  %s○%s  %-14s %sparado%s\n' "$C_DIM" "$C_RESET" "$1" "$C_DIM" "$C_RESET"
  fi
}
