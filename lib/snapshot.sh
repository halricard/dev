#!/usr/bin/env bash
# Snapshot: backup completo de arquivos e banco, e comandos do banco (db).

IGNORED_DIRS=(
  node_modules vendor .git/objects
  wp-content/cache wp-content/upgrade wp-content/uploads/cache
  storage/framework/cache
)

snapshot_dir() { printf '%s\n' "$DEV_SNAPSHOTS/$1"; }

snapshot_extra_ignores() {
  grep -oP '^SNAPSHOT_IGNORE="?\K[^"]*' "$PROJECT_DIR/dev.conf" 2>/dev/null || true
}

snapshot_is_excluded() {
  local rel="$1"; shift
  local ignored
  for ignored in "$@"; do
    [[ "$rel" == "$ignored" || "$rel" == "$ignored"/* ]] && return 0
  done
  return 1
}

database_dump() {
  local database="$1" target="$2"
  mysqldump_cli --single-transaction --routines --events "$database" | gzip > "$target"
}

database_restore() {
  local database="$1" dump="$2"
  mysql_cli -e "DROP DATABASE IF EXISTS \`$database\`;
                CREATE DATABASE \`$database\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    || return 1
  gzip -dc "$dump" | mysql_cli "$database"
}

database_import() {
  local database="$1" file="$2"
  mysql_cli -e "DROP DATABASE IF EXISTS \`$database\`;
                CREATE DATABASE \`$database\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" \
    || return 1
  if [[ "$file" == *.gz ]]; then
    gzip -dc "$file" | mysql_cli "$database"
  else
    mysql_cli "$database" < "$file"
  fi
}

cmd_snapshot() {
  require_project
  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  local name="${1:-$(date +%Y%m%d-%H%M)}"
  [[ "$name" =~ ^[a-zA-Z0-9._-]+$ ]] || die "nome inválido: use letras, números, ponto, hífen"

  local target
  target="$(snapshot_dir "$PROJECT_NAME")/$name"
  [[ -d "$target" ]] && die "já existe um snapshot \"$name\" deste projeto"
  mkdir -p "$target"

  local extra_ignores=""
  extra_ignores="$(snapshot_extra_ignores)"
  local declared=()
  read -ra declared <<<"$extra_ignores"
  local extras=() extra
  for extra in "${declared[@]}"; do
    [[ -n "$extra" ]] || continue
    snapshot_is_excluded "$extra" "${IGNORED_DIRS[@]}" && continue
    extras+=("$extra")
  done

  local ignored=("${IGNORED_DIRS[@]}" "${extras[@]}")
  local exclude=() dir
  for dir in "${ignored[@]}"; do
    exclude+=(--exclude="./$dir")
  done

  with_progress "arquivos de $PROJECT_NAME" \
    tar -czf "$target/files.tar.gz" -C "$PROJECT_DIR" "${exclude[@]}" . \
    || { rm -rf "$target"; die "falhou empacotar os arquivos"; }

  if [[ -n "$PROJECT_DATABASE" ]] && running mysql; then
    with_progress "banco $PROJECT_DATABASE" \
      database_dump "$PROJECT_DATABASE" "$target/database.sql.gz" \
      || { rm -rf "$target"; die "falhou exportar o banco"; }
  elif [[ -n "$PROJECT_DATABASE" ]]; then
    warn "sem banco neste snapshot  o MySQL está parado"
    printf 'no-database\n' > "$target/NO-DATABASE"
  fi

  printf '%s\n' "$PROJECT_DIR" > "$target/origin"
  date +%s > "$target/when"

  blank
  ok "snapshot \"$name\"  $(du -sh "$target" | cut -f1 || true)"
  hint "voltar com  $DEV restore $name"
  hint "fora: ${IGNORED_DIRS[*]:0:3}… — refeitos com composer/npm install"
  blank
}

cmd_snapshots() {
  case "${1:-}" in
    rm|remove|delete) shift; snapshot_remove "$@"; return 0 ;;
  esac

  step "SNAPSHOTS"
  local project snap found=0
  for project in "$DEV_SNAPSHOTS"/*; do
    [[ -d "$project" ]] || continue
    for snap in "$project"/*; do
      [[ -d "$snap" ]] || continue
      found=1
      local when mark=""
      when="$(date -d "@$(cat "$snap/when" 2>/dev/null || echo 0)" '+%d/%m %H:%M' 2>/dev/null || true)"
      [[ -f "$snap/NO-DATABASE" ]] && mark=" ${C_YELLOW}sem banco${C_RESET}"
      printf '  %s◆%s  %-28s %s%s · %s%s%b\n' "$C_BLUE" "$C_RESET" \
        "$(basename "$project")/$(basename "$snap")" \
        "$C_DIM" "$when" "$(du -sh "$snap" | cut -f1 || true)" "$C_RESET" "$mark"
    done
  done
  if (( found )); then
    blank
    hint "total $(du -sh "$DEV_SNAPSHOTS" 2>/dev/null | cut -f1 || true) · apagar um:  $DEV snapshots rm <projeto>/<nome>"
  else
    hint "nenhum ainda — $DEV snapshot [nome]"
  fi
  blank
}

snapshot_remove() {
  local wanted="${1:-}" project snap
  [[ -n "$wanted" ]] || die "uso: $DEV snapshots rm <nome>  ou  <projeto>/<nome>"
  if [[ "$wanted" == */* ]]; then
    project="${wanted%%/*}"; snap="${wanted#*/}"
  else
    load_project >/dev/null 2>&1 \
      || die "de fora de um projeto, use <projeto>/<nome> — veja $DEV snapshots"
    project="$PROJECT_NAME"; snap="$wanted"
  fi

  local dir="$DEV_SNAPSHOTS/$project/$snap"
  [[ -d "$dir" ]] || die "não há snapshot \"$snap\" de $project — veja $DEV snapshots"

  blank
  warn "apagar $project/$snap  ($(du -sh "$dir" | cut -f1 || true)) — não dá para desfazer"
  confirm "apagar?" n || { info "nada foi apagado"; blank; return 0; }
  rm -rf "$dir"
  rmdir "$DEV_SNAPSHOTS/$project" 2>/dev/null || true
  ok "$project/$snap apagado"
  blank
}

cmd_restore() {
  require_project
  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  local name="${1:-}" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes|-f|--force) force=1 ;;
      *) name="$1" ;;
    esac
    shift
  done

  [[ -n "$name" ]] || die "uso: $DEV restore <nome>   (veja $DEV snapshots)"
  local origin
  origin="$(snapshot_dir "$PROJECT_NAME")/$name"
  [[ -d "$origin" ]] || die "não há snapshot \"$name\" de $PROJECT_NAME"

  step "VOLTAR $PROJECT_NAME PARA \"$name\""
  printf '  %s✘%s  Arquivos de agora   serão substituídos pelos do snapshot\n' "$C_RED" "$C_RESET"
  if [[ -f "$origin/database.sql.gz" ]]; then
    printf '  %s✘%s  O banco %s será apagado e recriado\n' "$C_RED" "$C_RESET" "$PROJECT_DATABASE"
  else
    printf '  %s▲%s  Este snapshot não tem banco  o de agora fica como está\n' "$C_YELLOW" "$C_RESET"
  fi
  blank

  if (( ! force )) && [[ -z "${DEV_YES:-}" ]]; then
    local word
    read -r -p "  ?  Digite \"$name\" para confirmar: " word || true
    [[ "$word" == "$name" ]] || { info "nada foi restaurado"; return 0; }
  fi

  with_progress "restaurando arquivos" \
    tar -xzf "$origin/files.tar.gz" -C "$PROJECT_DIR" \
    || die "falhou restaurar os arquivos"

  if [[ -f "$origin/database.sql.gz" && -n "$PROJECT_DATABASE" ]]; then
    running mysql || die "o MySQL está parado — rode $DEV start"
    with_progress "restaurando o banco" \
      database_restore "$PROJECT_DATABASE" "$origin/database.sql.gz" \
      || die "falhou restaurar o banco"
  fi

  blank
  ok "$PROJECT_NAME voltou para \"$name\""
  hint "se o projeto usa composer ou npm, rode a instalação: eles ficaram de fora"
  blank
}

cmd_db() {
  local action="${1:-}"; shift || true
  case "$action" in
    query)  db_query "$@" ;;
    export) db_export "$@" ;;
    import) db_import "$@" ;;
    *)      die "uso: $DEV db query \"SELECT …\" | $DEV db export [arquivo.sql.gz] | $DEV db import <arquivo>" ;;
  esac
}

db_query() {
  require_project
  local sql="${1:-}"
  [[ -z "$sql" && ! -t 0 ]] && sql="$(cat)"
  [[ -n "$sql" ]] || die "uso: $DEV db query \"SELECT …\"   (ou a consulta pelo stdin)"
  [[ -n "$PROJECT_DATABASE" ]] \
    || die "este projeto não tem banco — declare DATABASE no dev.conf"

  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  running mysql || die "o MySQL está parado — $DEV up sobe a pilha"
  mysql_cli -B "$PROJECT_DATABASE" -e "$sql"
}

db_export() {
  require_project
  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  [[ -n "$PROJECT_DATABASE" ]] \
    || die "este projeto não tem banco — declare DATABASE no dev.conf"
  running mysql || die "o MySQL está parado — rode $DEV start"

  local target="${1:-$PROJECT_NAME-$(date +%Y%m%d-%H%M).sql.gz}"
  with_progress "exportando $PROJECT_DATABASE" \
    database_dump "$PROJECT_DATABASE" "$target" \
    || die "falhou exportar"
  ok "$target  $(du -h "$target" | cut -f1 || true)"
}

db_import() {
  require_project
  if [[ -f "$DEV_ROOT/lib/services.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/services.sh"
  fi
  local file="${1:-}"
  [[ -f "$file" ]] || die "uso: $DEV db import <arquivo.sql[.gz]>"
  [[ -n "$PROJECT_DATABASE" ]] \
    || die "este projeto não tem banco — declare DATABASE no dev.conf"
  running mysql || die "o MySQL está parado — rode $DEV start"

  warn "o banco $PROJECT_DATABASE vai ser apagado e recriado"
  confirm "continuar?" || { info "nada foi importado"; return 0; }

  with_progress "importando para $PROJECT_DATABASE" \
    database_import "$PROJECT_DATABASE" "$file" \
    || die "falhou importar"
  ok "importado para $PROJECT_DATABASE"
}
