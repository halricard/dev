#!/usr/bin/env bash
# Comandos que precisam rodar de tempos em tempos e workers supervisionados.

KEPT_RUNS=20

# $1 site · $2 tipo (schedule|worker) · $3 número
task_pid()   { printf '%s\n' "$DEV_RUN/$2-$1-$3.pid"; }
task_log()   { printf '%s\n' "$DEV_LOG/$2-$1-$3.log"; }
task_stamp() { printf '%s\n' "$DEV_RUN/$2-$1-$3.runs"; }

file_of_type() {
  case "$2" in
    schedule) printf '%s/dev.schedule\n' "$1" ;;
    worker)   printf '%s/dev.workers\n' "$1" ;;
  esac
}

lines_of_kind() {
  local file
  file="$(file_of_type "$1" "$2")"
  [[ -f "$file" ]] || return 0
  grep -vE '^[[:space:]]*(#|$)' "$file" 2>/dev/null || true
}

cadence() {
  local seconds="$1"
  if   (( seconds % 3600 == 0 )); then printf '%dh\n'    $(( seconds / 3600 ))
  elif (( seconds >= 60 ));       then printf '%dmin\n'  $(( seconds / 60 ))
  else                                  printf '%ds\n'    "$seconds"; fi
}

start_task() {
  local site="$1" type="$2" number="$3" interval="$4" command="$5" dir="$6" path="$7" ini="$8" rc="${9:-$(dirname "$8")}"
  local pid log runs script
  local ceiling=60
  (( interval > ceiling )) && ceiling="$interval"
  pid="$(task_pid "$site" "$type" "$number")"
  log="$(task_log "$site" "$type" "$number")"
  runs="$(task_stamp "$site" "$type" "$number")"
  script="$DEV_RUN/$type-$site-$number.sh"

  mkdir -p "$DEV_RUN" "$DEV_LOG"

  [[ -f "$pid" ]] && kill -0 "$(cat "$pid" 2>/dev/null)" 2>/dev/null && return 0

  local align=0
  [[ "$type" == schedule ]] && align=1

  cat > "$script" <<SCRIPT
#!/usr/bin/env bash
# Gerado pelo dev — supervisiona uma tarefa de "$site".
echo \$\$ > "$pid"
export PATH="$path:\$PATH"
export PHPRC="$rc"
export PHP_INI_SCAN_DIR="$ini"
[ -f "$CA_CRT" ] && export NODE_EXTRA_CA_CERTS="$CA_CRT"
cd "$dir" || exit 1
wait_for=$interval
while :; do
  started=\$(date +%s)
  $command >> "$log" 2>&1
  code=\$?
  printf '%s %s\\n' "\$(date +%s)" "\$code" >> "$runs"
  tail -n $KEPT_RUNS "$runs" > "$runs.tmp" 2>/dev/null && mv "$runs.tmp" "$runs"
  if [ \$code -ne 0 ] && [ \$(( \$(date +%s) - started )) -lt 5 ]; then
    wait_for=\$(( wait_for * 2 )); [ \$wait_for -gt $ceiling ] && wait_for=$ceiling
  else
    wait_for=$interval
    [ $align -eq 1 ] && wait_for=\$(( $interval - \$(date +%s) % $interval ))
  fi
  sleep \$wait_for
done
SCRIPT
  chmod +x "$script"

  rm -f "$pid"
  nohup setsid "$script" >/dev/null 2>&1 &
  local i=0
  while (( i < 50 )); do [[ -s "$pid" ]] && return 0; sleep 0.1; i=$(( i + 1 )); done
  warn "$site: a tarefa $type/$number não subiu — veja $log" >&2
  return 0
}

stop_site_tasks() {
  local site="$1" type="${2:-}" file
  for file in "$DEV_RUN"/{schedule,worker}-"$site"-*.pid; do
    [[ -n "$type" && "$(basename "$file")" != "$type"-* ]] && continue
    [[ -f "$file" ]] || continue
    kill -- -"$(cat "$file" 2>/dev/null)" 2>/dev/null || kill "$(cat "$file" 2>/dev/null)" 2>/dev/null || true
    rm -f "$file" "${file%.pid}.sh"
  done
}

start_site_tasks() {
  local site="$1" dir="$2" php_series="$3" type="${4:-}"
  local node_series path ini rc ver_now
  node_series="$(grep -oP '^NODE="?\K[^"]*' "$dir/dev.conf" 2>/dev/null || true)"
  path="$(project_path_prefix "$php_series" "$node_series")"
  ver_now="$(php_version "$php_series")"
  rc="$DEV_ETC/php/$ver_now"
  ini="$DEV_ETC/php/$ver_now/conf.d"
  local total=0 current number line interval command
  for current in schedule worker; do
    [[ -n "$type" && "$current" != "$type" ]] && continue
    number=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if [[ "$current" == schedule ]]; then
        interval="${line%% *}"; command="${line#* }"
        [[ "$interval" =~ ^[0-9]+$ ]] \
          || { warn "$site: intervalo inválido em \"$line\"" >&2; continue; }
      else
        interval=2; command="$line"
        if [[ "$command" == npm\ * || "$command" == npx\ * ]] \
           && [[ ! -d "$dir/node_modules" ]]; then
          warn "$site: \"$command\" precisa de node_modules" >&2
          hint "$DEV exec npm install" >&2
          continue
        fi
      fi
      number=$(( number + 1 )); total=$(( total + 1 ))
      start_task "$site" "$current" "$number" "$interval" "$command" "$dir" "$path" "$ini" "$rc"
    done < <(lines_of_kind "$dir" "$current")
  done
  printf '%s\n' "$total"
}

write_schedule_file() {
  local dir="$1"
  if declare -F recipe_schedule >/dev/null && [[ ! -f "$dir/dev.schedule" ]]; then
    recipe_schedule "$dir" > "$dir/dev.schedule"
  fi
  if declare -F recipe_workers >/dev/null && [[ ! -f "$dir/dev.workers" ]]; then
    recipe_workers > "$dir/dev.workers"
  fi
}

cmd_schedule() { list_tasks schedule "AGENDAMENTOS" "dev.schedule" "$@"; }
cmd_worker()   { list_tasks worker   "WORKERS"       "dev.workers"  "$@"; }

list_tasks() {
  local type="$1" title="$2" file="$3" site="${4:-}"
  if [[ -f "$DEV_ROOT/lib/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/config.sh"
  fi
  [[ -z "$site" ]] && load_project >/dev/null 2>&1 && site="$PROJECT_NAME"

  step "${title}${site:+ · $site}"
  local site_file name dir found=0
  for site_file in "$DEV_SITES"/*; do
    [[ -f "$site_file" ]] || continue
    name="$(basename "$site_file")"
    [[ -n "$site" && "$name" != "$site" ]] && continue
    dir="$(cat "$site_file")"
    local number=0 line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      number=$(( number + 1 )); found=1
      if [[ "$type" == schedule ]]; then
        report_task "$name" "$type" "$number" "${line%% *}" "${line#* }"
      else
        report_task "$name" "$type" "$number" "" "$line"
      fi
    done < <(lines_of_kind "$dir" "$type")
  done

  if (( found == 0 )); then
    hint "nada aqui — vem do arquivo $file do projeto"
    [[ "$type" == schedule ]] && hint "projetos ganham agendamentos no new ou no primeiro up"
    [[ "$type" == worker ]] && hint "exemplo:  echo 'npm run dev' >> $file"
  elif [[ "$type" == worker && -n "$site" && ! -f "$DEV_UP/$site" ]]; then
    hint "$site não está up — $DEV up sobe os workers dele"
  fi
  blank
}

report_task() {
  local site="$1" type="$2" number="$3" interval="$4" command="$5"
  local pid runs alive=0
  pid="$(task_pid "$site" "$type" "$number")"
  runs="$(task_stamp "$site" "$type" "$number")"
  [[ -f "$pid" ]] && kill -0 "$(cat "$pid" 2>/dev/null)" 2>/dev/null && alive=1

  local since=0
  [[ -f "$pid" ]] && since="$(stat -c %Y "$pid" 2>/dev/null || echo 0)"

  local bar="" failures=0 total=0 last=""
  if [[ -f "$runs" ]]; then
    local stamp code
    while read -r stamp code; do
      (( stamp < since )) && continue
      total=$(( total + 1 )); last="$stamp"
      if [[ "$code" == 0 ]]; then bar+="${C_GREEN}▪${C_RESET}"
      else bar+="${C_RED}▪${C_RESET}"; failures=$(( failures + 1 )); fi
    done < <(tail -n 5 "$runs")
  fi
  local empty=$(( 5 - total ))
  (( empty < 0 )) && empty=0
  bar+="$(printf '%*s' "$empty" '')"

  local mark="$C_GREEN✔$C_RESET"
  (( alive )) || mark="$C_DIM○$C_RESET"
  (( failures > 0 )) && mark="$C_YELLOW▲$C_RESET"

  local note=""
  if   (( ! alive ));        then note="parado"
  elif (( failures > 0 ));   then note="caiu $failures das últimas $total"
  elif (( total == 0 ));     then
    [[ "$type" == worker ]] && note="de pé" || note="ainda não rodou"
  else note="há $(clock $(( $(date +%s) - last )))"; fi

  local when=""
  [[ "$type" == schedule ]] && when="a cada $(cadence "$interval")"

  local text="${site} · ${command}"
  (( ${#text} > 34 )) && text="${text:0:33}…"
  local room=$(( 35 - ${#text} ))
  (( room < 1 )) && room=1

  printf '  %b  %s%*s%s%-12s%s %b  %s%s%s\n' \
    "$mark" "$text" "$room" "" "$C_DIM" "$when" "$C_RESET" \
    "$bar" "$C_DIM" "$note" "$C_RESET"
}
