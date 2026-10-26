#!/usr/bin/env bats
# Testes do gerenciador de plugins e ciclo de vida de receitas.

load helper

setup() {
  export DEV_ROOT="$ROOT"
  export HOME="$BATS_TEST_TMPDIR/home"
  export DEV_HOME="$BATS_TEST_TMPDIR/sandbox"
  export DEV_CACHE="$BATS_TEST_TMPDIR/cache"
  export DEV_PLUGINS="$DEV_HOME/plugins"
  export NO_COLOR=1
  unset DEV_YES
  TEST_PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$HOME" "$DEV_HOME" "$TEST_PROJECT" "$DEV_PLUGINS/installed"
  STUBS_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUBS_BIN"
  export PATH="$STUBS_BIN:$PATH"

  source "$ROOT/lib/common.sh"
}

@test "plugin list exibe plugins disponíveis e estado de instalação" {
  mkdir -p "$DEV_ROOT/plugins/demo-app"
  cat > "$DEV_ROOT/plugins/demo-app/recipe.sh" << 'EOF'
recipe_title() { echo "Aplicação Demo"; }
EOF

  run libraries '
    source "$DEV_ROOT/lib/plugins.sh"
    cmd_plugin list
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLUGINS DE APLICAÇÃO"* ]]
  [[ "$output" == *"demo-app"* ]]
  [[ "$output" == *"disponível"* ]]

  # Simula instalação
  mkdir -p "$DEV_PLUGINS/installed/demo-app"
  run libraries '
    source "$DEV_ROOT/lib/plugins.sh"
    cmd_plugin list
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"instalado"* ]]

  rm -rf "$DEV_ROOT/plugins/demo-app" "$DEV_PLUGINS/installed/demo-app"
}

@test "plugin install e plugin remove gerenciam arquivos em ~/.dev/plugins/installed" {
  mkdir -p "$DEV_ROOT/plugins/teste-plugin"
  cat > "$DEV_ROOT/plugins/teste-plugin/plugin.sh" << 'EOF'
plugin_install() { touch "$DEV_PLUGINS/installed/teste-plugin/executou-install"; }
plugin_remove() { :; }
EOF
  cat > "$DEV_ROOT/plugins/teste-plugin/recipe.sh" << 'EOF'
recipe_title() { echo "Teste Plugin"; }
EOF

  run libraries '
    source "$DEV_ROOT/lib/plugins.sh"
    cmd_plugin install teste-plugin
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"instalado com sucesso"* ]]
  [ -d "$DEV_PLUGINS/installed/teste-plugin" ]
  [ -f "$DEV_PLUGINS/installed/teste-plugin/executou-install" ]
  [ -f "$DEV_PLUGINS/installed/teste-plugin/.installed" ]

  run libraries '
    source "$DEV_ROOT/lib/plugins.sh"
    cmd_plugin remove teste-plugin
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"removido com sucesso"* ]]
  [ ! -d "$DEV_PLUGINS/installed/teste-plugin" ]

  rm -rf "$DEV_ROOT/plugins/teste-plugin"
}

@test "unload_recipe limpa todos os hooks contratuais" {
  libraries '
    recipe_title() { echo "Hook Anterior"; }
    recipe_docroot() { echo "antigo"; }
    [ "$(declare -F recipe_title)" = "recipe_title" ]

    unload_recipe
    [ -z "$(declare -F recipe_title)" ]
    [ -z "$(declare -F recipe_docroot)" ]
  '
}

@test "dev new bloqueia criação se o plugin não estiver instalado" {
  mkdir -p "$DEV_ROOT/plugins/app-fantasma"
  cat > "$DEV_ROOT/plugins/app-fantasma/recipe.sh" << 'EOF'
recipe_title() { echo "Fantasma"; }
EOF

  run dev_cmd new app-fantasma meu-site
  [ "$status" -ne 0 ]
  [[ "$output" == *"o plugin \"app-fantasma\" ainda não está instalado"* ]]
  [[ "$output" == *"dev plugin install app-fantasma"* ]]

  rm -rf "$DEV_ROOT/plugins/app-fantasma"
}
