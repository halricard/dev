#!/usr/bin/env bash
# dev test: as suítes de teste da aplicação e um usuário de teste temporário.
#
# Cada receita declara as suítes que conhece e sabe prepará-las e rodá-las:
#
#   recipe_test_suites               uma suíte por linha: "nome|descrição"
#   recipe_test_ready <suíte>        sucesso se a suíte já está preparada
#   recipe_test_init <suíte>         prepara a suíte (banco, config, dependências)
#   recipe_test_run <suíte> [args]   roda a suíte; o código de saída é o do teste
#
# E, para o usuário de teste:
#
#   recipe_test_user_create <dir> <usuário> <senha> <admin 0|1>
#       cria ou troca a senha; escreve na saída só o papel dado à conta
#   recipe_test_user_remove <dir> <usuário>
#
# O dev cuida do ambiente: PHP, Node, Composer e MySQL do projeto no PATH,
# o navegador e o endereço de teste https://test.<projeto>.localhost.

# shellcheck source=lib/browser.sh
source "$DEV_ROOT/lib/browser.sh"

TEST_USER="devtest"
TEST_CLEANUP=()

# Encerramentos pendentes (chromedriver, usuário de teste) rodam na saída,
# mesmo quando a suíte falha ou é interrompida.
test_on_exit() { TEST_CLEANUP+=("$1"); }

test_cleanup() {
  local action
  for action in "${TEST_CLEANUP[@]}"; do
    "$action" >/dev/null 2>&1 || true
  done
  TEST_CLEANUP=()
}

trap 'test_cleanup; rm -rf "$DEV_TMP"' EXIT

cmd_test() {
  local suite="${1:-}"; shift || true
  case "$suite" in
    -h|--help|help) test_usage; return 0 ;;
  esac
  # Caminhos dados pelo usuário são relativos a onde ele está, não à raiz.
  TEST_CALLER_DIR="$PWD"
  require_project
  [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP"
  case "$suite" in
    ""|list) test_list ;;
    user)    test_user "$@" ;;
    init)    test_init "$@" ;;
    *)       test_run "$suite" "$@" ;;
  esac
}

test_usage() {
  cat <<TXT

  ${C_BOLD}dev test${C_RESET}  ${C_DIM}suítes de teste da aplicação deste projeto${C_RESET}

    test                  lista as suítes que esta aplicação oferece
    test <suíte> [args]   roda a suíte; prepara antes, se for a primeira vez
    test init <suíte>     prepara de novo (depois de atualizar a aplicação)
    test user             cria um usuário de teste temporário e mostra a senha
    test user --no-admin  o mesmo, sem poderes de administrador
    test user --remove    apaga o usuário de teste (o dev down também apaga)

TXT
}

# ------------------------------------------------------------------- suítes
# Projeto sem aplicação declarada: o PHPUnit do próprio projeto, se houver.
generic_test_suites() {
  [[ -x "$PROJECT_DIR/vendor/bin/phpunit" ]] \
    && printf '%s\n' "phpunit|PHPUnit do projeto (vendor/bin/phpunit)"
  return 0
}

test_suites() {
  if declare -F recipe_test_suites >/dev/null; then
    recipe_test_suites
  else
    generic_test_suites
  fi
}

test_suite_known() {
  local line
  while IFS= read -r line; do
    [[ "${line%%|*}" == "$1" ]] && return 0
  done < <(test_suites)
  return 1
}

test_hook() {
  local hook="$1"; shift
  if declare -F "recipe_$hook" >/dev/null; then
    "recipe_$hook" "$@"
  else
    "generic_$hook" "$@"
  fi
}

generic_test_ready() { return 0; }
generic_test_init()  { return 0; }
generic_test_run()   { vendor/bin/phpunit "${@:2}"; }

test_list() {
  step "TESTES  $PROJECT_NAME"
  local line found=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    found=1
    printf '  %s%-10s%s %s\n' "$C_BOLD" "${line%%|*}" "$C_RESET" "${line#*|}"
  done < <(test_suites)
  if (( ! found )); then
    if [[ -n "$PROJECT_APP" ]] && plugin_outdated "$PROJECT_APP" \
       && grep -q '^recipe_test_suites()' "$DEV_ROOT/plugins/$PROJECT_APP/recipe.sh" 2>/dev/null; then
      info "o plugin $PROJECT_APP instalado é anterior às suítes de teste"
      hint "atualize com: $DEV plugin update $PROJECT_APP"
      blank
      return 0
    fi
    info "${PROJECT_APP:-este projeto} não declara suítes de teste"
    hint "com PHPUnit instalado (vendor/bin/phpunit), a suíte phpunit aparece aqui"
    blank
    return 0
  fi
  blank
  hint "rode com: $DEV test <suíte> [argumentos da ferramenta]"
  hint "usuário temporário para testar no navegador: $DEV test user"
  blank
}

test_require_suite() {
  local suite="$1"
  test_suite_known "$suite" && return 0
  bad "suíte desconhecida: $suite"
  test_list >&2
  exit 1
}

# O ambiente do projeto (PHP, Node, Composer e MySQL no PATH), com os serviços
# de que as suítes dependem de pé.
test_environment() {
  project_environment
  source "$DEV_ROOT/lib/services.sh"
  if [[ -n "$PROJECT_DATABASE" ]]; then
    running mysql || die "o MySQL está parado — rode: $DEV up"
  fi
  cd "$PROJECT_DIR" || exit 1
}

test_init() {
  local suite="${1:-}"
  [[ -n "$suite" ]] || die "uso: ${DEV_COMMAND:-$DEV test} init <suíte>"
  test_require_suite "$suite"
  test_environment
  step "PREPARANDO  $suite"
  test_hook test_init "$suite" || die "a preparação de $suite falhou"
  ok "$suite pronta"
  blank
}

test_run() {
  local suite="$1"; shift
  test_require_suite "$suite"
  test_environment
  if ! test_hook test_ready "$suite" >/dev/null 2>&1; then
    step "PREPARANDO  $suite  (primeira vez)"
    test_hook test_init "$suite" || die "a preparação de $suite falhou"
    ok "$suite pronta"
  fi
  step "TESTE  $suite"
  local rc=0
  test_hook test_run "$suite" "$@" || rc=$?
  blank
  if (( rc == 0 )); then
    ok "$suite passou"
  else
    bad "$suite terminou com código $rc"
  fi
  return "$rc"
}

# Garante o navegador e sobe o chromedriver até o fim do comando.
test_browser() {
  ensure_browser
  start_chromedriver
  test_on_exit stop_chromedriver
}

# Suítes que usam o Playwright do próprio projeto (e2e do WordPress, navegador
# do Pest) abrem o navegador que aquela versão do Playwright fixa — desde o
# Playwright 1.57, também um Chrome for Testing. Cada versão do Playwright só
# garante o build dela, então o dev não troca pelo Chrome que ele mesmo fixa:
# guarda esses builds em ~/.dev/runtime, compartilhados entre projetos, e o
# install não baixa de novo o que já está lá.
playwright_browsers_path() { printf '%s\n' "$DEV_RUNTIME/playwright-browsers"; }

playwright_chromium() {
  local bin=node_modules/.bin/playwright
  [[ -x "$bin" ]] || bin="$PROJECT_DIR/node_modules/.bin/playwright"
  [[ -x "$bin" ]] || die "o Playwright não está no projeto — instale com: $DEV exec npm install"
  with_progress "conferindo o navegador do Playwright do projeto" \
    env PLAYWRIGHT_BROWSERS_PATH="$(playwright_browsers_path)" "$bin" install chromium
}

# O site precisa estar servido para as suítes que abrem o navegador.
test_require_served() {
  site_exists "$PROJECT_NAME" || die "o projeto está fora do ar — rode: $DEV up"
  running nginx || die "o nginx está parado — rode: $DEV up"
}

# ------------------------------------------------------- usuário de teste
test_user_marker() { printf '%s\n' "$DEV_HOME/test-users/$1"; }

test_user_supported() {
  declare -F recipe_test_user_create >/dev/null && declare -F recipe_test_user_remove >/dev/null
}

test_user() {
  local remove=0 admin=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --remove|remove|rm) remove=1 ;;
      --no-admin)         admin=0 ;;
      *) die "uso: ${DEV_COMMAND:-$DEV test} user [--no-admin|--remove]" ;;
    esac
    shift
  done
  test_user_supported \
    || die "${PROJECT_APP:-este projeto} não tem contas de usuário que o dev saiba criar"
  test_environment

  local marker
  marker="$(test_user_marker "$PROJECT_NAME")"
  if (( remove )); then
    test_user_remove
    return 0
  fi

  if [[ ! -f "$marker" ]] && declare -F recipe_has_user >/dev/null \
     && recipe_has_user "$PROJECT_DIR" "$TEST_USER"; then
    die "já existe um usuário \"$TEST_USER\" que não foi criado pelo dev — mantido como está"
  fi

  local password role identity="$TEST_USER"
  password="$(random_password)"
  role="$(recipe_test_user_create "$PROJECT_DIR" "$TEST_USER" "$password" "$admin")" \
    || die "não consegui criar o usuário de teste"
  mkdir -p "$(dirname "$marker")"
  date +%s > "$marker"
  declare -F recipe_identity >/dev/null && identity="$(recipe_identity "$TEST_USER")"

  step "USUÁRIO DE TESTE  $PROJECT_NAME"
  label "login" "${C_BOLD}$identity${C_RESET}"
  label "senha" "${C_BOLD}$password${C_RESET}"
  label "papel" "${role:-usuário de teste}"
  label "site" "$(site_url "$PROJECT_NAME")"
  blank
  hint "conta temporária: some no $DEV down, ou já com: $DEV test user --remove"
  hint "a senha muda a cada $DEV test user; a conta de administrador real fica intocada"
  blank
}

test_user_remove() {
  local marker
  marker="$(test_user_marker "$PROJECT_NAME")"
  if [[ ! -f "$marker" ]]; then
    info "nenhum usuário de teste criado pelo dev em $PROJECT_NAME"
    return 0
  fi
  recipe_test_user_remove "$PROJECT_DIR" "$TEST_USER" \
    || warn "não consegui apagar o usuário $TEST_USER — confira na aplicação"
  rm -f "$marker"
  ok "usuário de teste removido de $PROJECT_NAME"
}

# Chamado pelo dev down: apaga o usuário de teste do site que sai do ar.
test_user_cleanup_site() {
  local name="$1" dir
  [[ -f "$(test_user_marker "$name")" ]] || return 0
  dir="$(cat "$DEV_SITES/$name" 2>/dev/null || true)"
  [[ -n "$dir" && -f "$dir/dev.conf" ]] || { rm -f "$(test_user_marker "$name")"; return 0; }
  (
    load_project "$dir" || exit 0
    [[ -n "$PROJECT_APP" ]] && load_recipe "$PROJECT_APP"
    test_user_supported || exit 0
    project_env "$PROJECT_PHP" "$PROJECT_NODE" || exit 0
    source "$DEV_ROOT/lib/services.sh"
    # Com o MySQL parado o usuário fica; o marcador também, e o próximo down tenta de novo.
    [[ -z "$PROJECT_DATABASE" ]] || running mysql || exit 0
    cd "$PROJECT_DIR" || exit 0
    test_user_remove
  )
}
