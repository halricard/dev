#!/usr/bin/env bash
# Versão da aplicação fixada no dev.conf, para que todo clone receba a mesma
# no dev up. Cada receita diz as chaves (recipe_pin) e qual delas marca o
# projeto como fixado (recipe_pin_key).

# Grava no dev.conf de <dir> as linhas CHAVE=valor da receita carregada.
# Valor vazio apaga a chave. PIN_WRITTEN conta as chaves gravadas.
pin_project() {
  local dir="$1" lines line key value
  PIN_WRITTEN=0
  lines="$(recipe_pin "$dir")" || return 1
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if [[ -n "$value" ]]; then
      project_conf_set "$dir/dev.conf" "$key" "$value"
      ok "dev.conf  $key=\"$value\""
      PIN_WRITTEN=$((PIN_WRITTEN + 1))
    else
      project_conf_unset "$dir/dev.conf" "$key"
    fi
  done <<< "$lines"
}

# O plugin instalado em ~/.dev é anterior à fixação de versão que a receita
# do dev já traz: o dev usa a cópia instalada, então ela precisa ser atualizada.
pin_plugin_outdated() {
  local app="$1"
  plugin_outdated "$app" && grep -q '^recipe_pin()' "$DEV_ROOT/plugins/$app/recipe.sh" 2>/dev/null
}

# No dev up: um projeto ainda sem a versão no dev.conf passa a ter.
pin_if_missing() {
  local dir="$1" key
  if ! declare -F recipe_pin_key >/dev/null; then
    if [[ -n "${PROJECT_APP:-}" ]] && pin_plugin_outdated "$PROJECT_APP"; then
      info "o plugin $PROJECT_APP instalado é anterior à versão fixada no dev.conf"
      hint "atualize com: $DEV plugin update $PROJECT_APP   (depois, $DEV up grava a versão)"
    fi
    return 0
  fi
  key="$(recipe_pin_key)"
  grep -qE "^${key}=\"?[^\"[:space:]]" "$dir/dev.conf" 2>/dev/null && return 0
  info "o dev.conf ainda não fixa a versão da aplicação — gravando a instalada"
  if pin_project "$dir"; then
    hint "faça commit do dev.conf: quem clonar recebe esta versão no $DEV up"
  else
    warn "a versão não foi fixada; tente de novo com $DEV pin"
  fi
}

cmd_pin() {
  require_project
  [[ -n "$PROJECT_APP" ]] || die "o dev.conf não declara APP: não há aplicação para fixar"
  load_recipe "$PROJECT_APP" || die "não conheço a aplicação \"$PROJECT_APP\""
  local title
  title="$(recipe_title 2>/dev/null || printf '%s' "$PROJECT_APP")"

  step "PIN  $PROJECT_NAME ($title)"
  if ! declare -F recipe_pin >/dev/null; then
    if pin_plugin_outdated "$PROJECT_APP"; then
      bad "o plugin $PROJECT_APP instalado é anterior ao dev pin"
      hint "atualize com: $DEV plugin update $PROJECT_APP   e rode $DEV pin de novo"
      blank
      exit 1
    fi
    info "a receita do $title não fixa versão no dev.conf"
    blank
    return 0
  fi
  pin_project "$PROJECT_DIR" || die "a versão do $title não foi fixada"
  if (( PIN_WRITTEN > 0 )); then
    hint "faça commit do dev.conf: quem clonar recebe esta versão no $DEV up"
    hint "depois de atualizar o $title, rode $DEV pin de novo"
  fi
  blank
}
