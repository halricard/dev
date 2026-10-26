#!/usr/bin/env bash
# Tira do projeto o lixo que o sistema de arquivos do Windows deixa para trás.

JUNK_PATTERNS=(
  '*:Zone.Identifier'
  'Thumbs.db'
  'desktop.ini'
  '.DS_Store'
)

junk_description() {
  case "$1" in
    '*:Zone.Identifier') printf 'resíduo de cópia do Windows\n' ;;
    'Thumbs.db')         printf 'cache de miniaturas do Explorer\n' ;;
    'desktop.ini')       printf 'configuração de pasta do Windows\n' ;;
    '.DS_Store')         printf 'metadado do Finder do macOS\n' ;;
  esac
}

find_junk() {
  find "$1" -type f -name "$2" -not -path '*/.git/*' 2>/dev/null || true
}

count_junk() {
  local dir="$1" pattern count bytes total=0 total_bytes=0
  for pattern in "${JUNK_PATTERNS[@]}"; do
    count="$(find_junk "$dir" "$pattern" | wc -l || true)"
    (( count > 0 )) || continue
    bytes="$(find "$dir" -type f -name "$pattern" -not -path '*/.git/*' -printf '%s\n' 2>/dev/null \
             | awk '{s+=$1} END {print s+0}' || echo 0)"
    total=$(( total + count )); total_bytes=$(( total_bytes + bytes ))
  done
  printf '%s %s\n' "$total" "$total_bytes"
}

cmd_clean() {
  require_project
  local what="${1:-}"; shift || true
  case "$what" in
    "")      clean_list ;;
    trash)   clean_trash "$@" ;;
    *)       die "não sei limpar \"$what\" — hoje só existe: ${DEV_COMMAND:-$DEV clean} trash" ;;
  esac
}

clean_list() {
  step "LIMPAR $PROJECT_NAME"
  local count bytes
  read -r count bytes < <(count_junk "$PROJECT_DIR")
  if (( count == 0 )); then
    ok "nada a limpar"
    blank
    return 0
  fi
  printf '  %s%-8s%s %s%-38s%s %s%d arquivo(s)%s\n' \
    "$C_BOLD" "trash" "$C_RESET" "$C_DIM" "lixo que a cópia do Windows deixou" \
    "$C_RESET" "$C_YELLOW" "$count" "$C_RESET"
  blank
  hint "$DEV clean trash            apaga, perguntando antes"
  hint "$DEV clean trash --plan    só mostra o que apagaria"
  blank
}

clean_trash() {
  local plan=0
  case "${1:-}" in
    --plan) plan=1 ;;
    "")      ;;
    *)       die "uso: ${DEV_COMMAND:-$DEV clean} trash [--plan]" ;;
  esac

  step "LIMPAR $PROJECT_NAME · trash"

  local pattern count bytes total=0 total_bytes=0 found=0
  for pattern in "${JUNK_PATTERNS[@]}"; do
    count="$(find_junk "$PROJECT_DIR" "$pattern" | wc -l || true)"
    (( count > 0 )) || continue
    found=1
    bytes="$(find "$PROJECT_DIR" -type f -name "$pattern" -not -path '*/.git/*' -printf '%s\n' 2>/dev/null \
             | awk '{s+=$1} END {print s+0}' || echo 0)"
    printf '  %s%6d%s  %-22s %s%s%s\n' \
      "$C_YELLOW" "$count" "$C_RESET" "$pattern" "$C_DIM" "$(junk_description "$pattern")" "$C_RESET"
    total=$(( total + count )); total_bytes=$(( total_bytes + bytes ))
  done

  if (( found == 0 )); then
    ok "nada a limpar"
    blank
    return 0
  fi

  blank
  hint "só arquivos desta lista, só dentro de $PROJECT_DIR, nunca o .git"
  hint "vendor, node_modules e caches não entram — são de outro assunto"

  if (( plan )); then
    blank
    info "$total arquivo(s) seriam apagados  ($(human_size "$total_bytes"))"
    blank
    return 0
  fi

  blank
  confirm "apagar $total arquivo(s)?" n || { info "nada foi apagado"; blank; return 0; }

  for pattern in "${JUNK_PATTERNS[@]}"; do
    find "$PROJECT_DIR" -type f -name "$pattern" -not -path '*/.git/*' -delete 2>/dev/null || true
  done
  ok "$total arquivo(s) apagados  ($(human_size "$total_bytes"))"
  blank
}

human_size() {
  local bytes="$1"
  if   (( bytes >= 1048576 )); then printf '%d MB\n' $(( bytes / 1048576 ))
  elif (( bytes >= 1024 ));    then printf '%d KB\n' $(( bytes / 1024 ))
  else                              printf '%d bytes\n' "$bytes"; fi
}
