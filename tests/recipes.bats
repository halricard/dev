#!/usr/bin/env bats
# Testes das receitas oficiais de aplicação: WordPress, Laravel e Moodle.

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

@test "receita wordpress implementa metadados, gitignore e schedule" {
  libraries '
    load_recipe wordpress
    [ "$(recipe_title)" = "WordPress" ]
    [ "$(recipe_docroot)" = "." ]
    [ "$(recipe_identity "admin")" = "admin" ]

    ignore="$(recipe_gitignore)"
    [[ "$ignore" == *"!/dev.conf"* ]]
    [[ "$ignore" == *"!/dev.schedule"* ]]
    [[ "$ignore" == *"!/wp-content/plugins/"* ]]

    agenda="$(recipe_schedule)'"'"$TEST_PROJECT"'"')"
    [[ "$agenda" == *"60 php wp-cron.php"* ]]
  '
}

@test "receita laravel implementa metadados, workers, schedule e .env" {
  libraries '
    load_recipe laravel
    [ "$(recipe_title)" = "Laravel" ]
    [ "$(recipe_docroot)" = "public" ]

    workers="$(recipe_workers)"
    [[ "$workers" == *"php artisan queue:listen"* ]]
    [[ "$workers" == *"npm run dev"* ]]

    agenda="$(recipe_schedule)"
    [[ "$agenda" == *"60 php artisan schedule:run"* ]]

    mkdir -p "'"$TEST_PROJECT"'"
    write_env "'"$TEST_PROJECT"'" "meu-laravel" "laradb"
    [ -f "'"$TEST_PROJECT/.env"'" ]
    env_content="$(cat "'"$TEST_PROJECT/.env"'")"
    [[ "$env_content" == *"APP_NAME=meu-laravel"* ]]
    [[ "$env_content" == *"APP_URL=https://meu-laravel.localhost"* ]]
    [[ "$env_content" == *"DB_DATABASE=laradb"* ]]
  '
}

@test "receita moodle implementa metadados, php 8.4, gitignore e schedule" {
  libraries '
    load_recipe moodle
    [ "$(recipe_title)" = "Moodle" ]
    [ "$(recipe_docroot "'"$TEST_PROJECT"'")" = "app" ]
    [ "$(recipe_php)" = "8.4" ]

    ignore="$(recipe_gitignore)"
    [[ "$ignore" == *"!/app/"* ]]
    [[ "$ignore" == *"!/app/public/mod/"* ]]
    [[ "$ignore" == *"!/app/public/local/"* ]]

    agenda="$(recipe_schedule)"
    [[ "$agenda" == *"60 php app/admin/cli/cron.php"* ]]
  '
}
