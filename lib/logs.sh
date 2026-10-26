#!/usr/bin/env bash
# O que quebrou: agregação de erros do nginx, PHP e das aplicações.

log_files() {
  local site="$1" file
  for file in "$DEV_LOG/$site"-*.log; do [[ -f "$file" ]] && printf '%s\n' "$file"; done
  local dir
  dir="$(cat "$DEV_SITES/$site" 2>/dev/null || true)"
  [[ -n "$dir" && -d "$dir" ]] || return 0
  local root
  for root in "$dir" "$dir/app" "$dir/public" "$dir/storage/logs"; do
    for file in "$root"/wp-content/*.log "$root"/wp-content/*/*.log \
                "$root"/wp-content/uploads/*.log "$root"/var/log/*.log "$root"/var/log/*/*.log \
                "$root"/*.log; do
      [[ -f "$file" ]] && printf '%s\n' "$file"
    done
  done
}

known_sites() {
  local file
  for file in "$DEV_SITES"/*; do [[ -f "$file" ]] && basename "$file"; done
}

ERROR_PATTERN='(PHP )?(Fatal error|Parse error|Recoverable fatal error|Warning|Notice|Deprecated)|\[(emerg|alert|crit|error|warn)\]|\.(ERROR|CRITICAL|ALERT|EMERGENCY|WARNING):|Uncaught |Stack trace|exception handler'
SEVERE_PATTERN='(PHP )?(Fatal error|Parse error)|\[(emerg|alert|crit|error)\]|\.(ERROR|CRITICAL|ALERT|EMERGENCY):|Uncaught |exception handler'

strip_stamp() {
  sed -E \
    -e 's/^\[[^]]+\] ?//' \
    -e 's/^[0-9]{4}[-\/][0-9]{2}[-\/][0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}[^ ]* ?//' \
    -e 's/^[0-9]{1,3}(\.[0-9]{1,3}){3} - [^ ]+ \[[^]]+\] ?//' \
    -e 's/^(\[[a-z]+\] )[0-9]+#[0-9]+: (\*[0-9]+ )?/\1/' \
    -e 's/, client: .*$//'
}

cmd_logs() {
  local site="" only_errors=0 lines=25 follow=0 all=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -e|--errors)  only_errors=1 ;;
      -f|--follow)  follow=1 ;;
      -a|--all)     all=1 ;;
      -n|--lines)   lines="${2:-25}"; shift ;;
      -n*)          lines="${1#-n}" ;;
      -*)           die "opção desconhecida: $1" ;;
      *)            site="$1" ;;
    esac
    shift
  done

  local sites=()
  if [[ -n "$site" ]]; then
    [[ -f "$DEV_SITES/$site" ]] \
      || die "não há projeto chamado \"$site\" — veja \`$DEV sites\`"
    sites=("$site")
  elif load_project >/dev/null 2>&1; then
    sites=("$PROJECT_NAME")
  else
    mapfile -t sites < <(known_sites)
  fi
  [[ ${#sites[@]} -gt 0 ]] || { info "nenhum projeto ainda"; return 0; }

  local files=() name
  for name in "${sites[@]}"; do
    mapfile -t -O "${#files[@]}" files < <(log_files "$name")
  done
  [[ ${#files[@]} -gt 0 ]] || { info "nada registrado ainda"; return 0; }

  if (( follow )); then
    if (( ${#sites[@]} > 1 )); then step "ACOMPANHANDO  todos os projetos (${#sites[@]})"
    else step "ACOMPANHANDO  ${sites[0]}"; fi
    hint "Ctrl+C encerra"
    blank
    tail -F -n 20 "${files[@]}" 2>/dev/null
    return 0
  fi

  local pattern="$ERROR_PATTERN"
  (( only_errors )) && pattern="$SEVERE_PATTERN"
  (( all )) && pattern='.'

  if (( ${#sites[@]} > 1 )); then step "LOGS  todos os projetos (${#sites[@]})"
  else step "LOGS  ${sites[0]}"; fi

  local mark=0
  (( ${#sites[@]} > 1 )) && mark=1

  local raw="$DEV_TMP/logs"
  mkdir -p "$DEV_TMP"
  : > "$raw"
  local site_files=()
  for name in "${sites[@]}"; do
    mapfile -t site_files < <(log_files "$name")
    (( ${#site_files[@]} > 0 )) || continue
    grep -hE "$pattern" "${site_files[@]}" 2>/dev/null \
      | strip_stamp \
      | sed -E 's/[[:space:]]+$//' \
      | grep -v '^$' \
      | sed "s|^|$name\t|" >> "$raw" || true
  done

  local out
  out="$(sort "$raw" | uniq -c | sort -rn | head -n "$lines" || true)"

  if [[ -z "$out" ]]; then
    ok "nada a relatar"
    (( only_errors )) && hint "só falhas graves; sem -e aparecem avisos também"
    blank
    return 0
  fi

  local width=0 current
  if (( mark )); then
    for current in "${sites[@]}"; do (( ${#current} > width )) && width=${#current}; done
  fi

  printf '%s\n' "$out" | while read -r count line; do
    local origin="${line%%$'\t'*}" msg="${line#*$'\t'}"
    local color="$C_YELLOW"
    grep -qE "$SEVERE_PATTERN" <<<"$msg" && color="$C_RED"
    if (( mark )); then
      printf '  %s%4s×%s  %s%s%*s%s  %s%s%s\n' "$C_DIM" "$count" "$C_RESET" \
        "$C_CYAN" "$origin" $(( width - ${#origin} + 1 )) "" "$C_RESET" \
        "$color" "${msg:0:130}" "$C_RESET"
    else
      printf '  %s%4s×%s  %s%s%s\n' "$C_DIM" "$count" "$C_RESET" \
        "$color" "${msg:0:150}" "$C_RESET"
    fi
  done

  blank
  hint "-e só falhas graves · -n N quantas linhas · -f acompanha · -a tudo"
  hint "ocorrências idênticas são agrupadas; mensagens que variam contam separado"
  blank
}
