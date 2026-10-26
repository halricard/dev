#!/usr/bin/env bash
# Que partes do projeto vão para o git.

project_gitignore() { printf '%s\n' "$PROJECT_DIR/.gitignore"; }

where_yours_live() {
  case "$1" in
    wordpress) printf 'wp-content/plugins\nwp-content/themes\nwp-content/mu-plugins\n' ;;
    moodle)    printf 'local\nmod\ntheme\nblocks\n' ;;
  esac
}

ladder() {
  local path="${1%/}" partial="" part
  local -a parts
  IFS='/' read -ra parts <<< "$path"
  local last=$(( ${#parts[@]} - 1 )) i
  for i in "${!parts[@]}"; do
    part="${parts[i]}"
    partial="$partial/$part"
    printf '!%s/\n' "$partial"
    (( i < last )) && printf '%s/*\n' "$partial"
  done
}

is_freed()   { grep -qxF "!/${1%/}/" "$(project_gitignore)" 2>/dev/null; }
is_passage() { is_freed "$1" && grep -qxF "/${1%/}/*" "$(project_gitignore)" 2>/dev/null; }
is_tracked() { is_freed "$1" && ! is_passage "$1"; }

covered() {
  local path="${1%/}"
  while [[ "$path" == */* || -n "$path" ]]; do
    is_tracked "$path" && return 0
    [[ "$path" == */* ]] || return 1
    path="${path%/*}"
  done
  return 1
}

cmd_track() {
  require_project
  local path="${1:-}"
  local ignore
  ignore="$(project_gitignore)"

  [[ -f "$ignore" ]] || die "não há .gitignore aqui — rode \`$DEV up\` para escrevê-lo"

  [[ -n "$path" ]] || { list_tracked; return 0; }

  path="${path#./}"; path="${path%/}"
  [[ -d "$PROJECT_DIR/$path" ]] || die "não existe: $PROJECT_DIR/$path"
  is_tracked "$path" && { info "$path já está versionado"; return 0; }

  if is_passage "$path"; then
    info "$path é uma ${C_BOLD}passagem${C_RESET}: o git entra nele, mas o conteúdo segue ignorado"
    hint "é assim que você versiona seu código sem levar junto os arquivos base da aplicação"
    blank
    local inside=() dir
    for dir in "$PROJECT_DIR/$path"/*/; do
      [[ -d "$dir" ]] || continue
      local rel="${dir#"$PROJECT_DIR"/}"; rel="${rel%/}"
      covered "$rel" || inside+=("$(basename "$rel")")
    done
    if (( ${#inside[@]} > 0 )); then
      warn "versionar o diretório inteiro levaria também: ${inside[*]:0:6}$( (( ${#inside[@]} > 6 )) && printf ' e mais %d' "$(( ${#inside[@]} - 6 ))" )"
    fi
    hint "para versionar só um: $DEV track $path/<nome>"
    blank
    confirm "versionar tudo que está dentro de $path?" || { info "nada mudou"; return 0; }
    local tmp
    tmp="$(mktemp -p "$DEV_TMP")"
    grep -vxF "/$path/*" "$ignore" > "$tmp" && mv "$tmp" "$ignore"
    ok "$path inteiro passa a ser versionado"
    hint "confira com git status"
    return 0
  fi

  local line new_lines=()
  while IFS= read -r line; do
    grep -qxF "$line" "$ignore" || new_lines+=("$line")
  done < <(ladder "$path")

  {
    printf '\n# %s — acrescentado por `dev track`\n' "$path"
    printf '%s\n' "${new_lines[@]}"
  } >> "$ignore"

  ok "$path passa a ser versionado"
  (( ${#new_lines[@]} > 1 )) && hint "$(( ${#new_lines[@]} - 1 )) linha(s) a mais para liberar o caminho até ele"
  hint "confira com git status"
}

cmd_untrack() {
  require_project
  local path="${1:-}"
  [[ -n "$path" ]] || die "uso: ${DEV_COMMAND:-$DEV untrack} <caminho>"
  path="${path#./}"; path="${path%/}"
  local ignore
  ignore="$(project_gitignore)"
  is_freed "$path" || die "$path não está na lista"

  local tmp
  tmp="$(mktemp -p "$DEV_TMP")"
  grep -vxF "!/$path/" "$ignore" > "$tmp" && mv "$tmp" "$ignore"
  ok "$path deixa de ser versionado"
  hint "o caminho até ele continua liberado, porque outro plugin pode usá-lo"
  warn "se ele já estava no git, saia com git rm -r --cached $path"
}

list_tracked() {
  local ignore
  ignore="$(project_gitignore)"
  step "VERSIONADO EM $PROJECT_NAME"

  local freed=() tracked=() passages=() item
  mapfile -t freed < <(grep -oP '^!/\K.*(?=/$)' "$ignore" 2>/dev/null | sort)
  for item in "${freed[@]}"; do
    if is_passage "$item"; then passages+=("$item"); else tracked+=("$item"); fi
  done
  for item in "${tracked[@]}"; do
    printf '  %s✔%s  %s\n' "$C_GREEN" "$C_RESET" "$item"
  done
  local always
  for always in dev.conf dev.schedule dev.workers; do
    [[ -f "$PROJECT_DIR/$always" ]] && printf '  %s✔%s  %s %s(sempre)%s\n' \
      "$C_GREEN" "$C_RESET" "$always" "$C_DIM" "$C_RESET"
  done

  local outside=() base sub
  while IFS= read -r base; do
    [[ -d "$PROJECT_DIR/$base" ]] || continue
    for sub in "$PROJECT_DIR/$base"/*/; do
      [[ -d "$sub" ]] || continue
      local rel="${sub#"$PROJECT_DIR"/}"; rel="${rel%/}"
      covered "$rel" || outside+=("$rel")
    done
  done < <(where_yours_live "$PROJECT_APP")

  if (( ${#outside[@]} > 0 )); then
    blank
    printf '  %sfora do git%s  %s(o que veio junto com a aplicação)%s\n' \
      "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
    local item_out
    for item_out in "${outside[@]:0:12}"; do
      printf '  %s○%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$item_out" "$C_RESET"
    done
    (( ${#outside[@]} > 12 )) && printf '  %s   … e mais %d%s\n' "$C_DIM" "$(( ${#outside[@]} - 12 ))" "$C_RESET"
  fi

  if (( ${#passages[@]} > 0 )); then
    blank
    printf '  %spassagens%s  %s(o git entra, mas só leva o que você marcar dentro)%s\n' \
      "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
    for item in "${passages[@]}"; do
      printf '  %s→%s  %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$item" "$C_RESET"
    done
  fi

  blank
  hint "$DEV track <caminho>     passa a versionar"
  hint "$DEV untrack <caminho>   para de versionar"
  blank
}
