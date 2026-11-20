#!/usr/bin/env bats
# Testes da versão fixada no dev.conf: dev pin, recipe_pin e o download da versão fixada.

load helper

SHA_NEWER="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_PARENT="pppppppppppppppppppppppppppppppppppppppp"
SHA_WEEKLY="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SHA_RELEASE="cccccccccccccccccccccccccccccccccccccccc"

# O núcleo do Moodle 5.1+ em $TEST_PROJECT/app, com o version.php dado.
moodle_core() {
  mkdir -p "$TEST_PROJECT/app/public/lib"
  touch "$TEST_PROJECT/app/public/lib/setup.php"
  version_php "$1" "$2" "${3:-503}" > "$TEST_PROJECT/app/public/version.php"
}

version_php() {
  printf "<?php\n\$version  = %s;              // 20261005      = branching date\n" "$1"
  printf "\$release  = '%s';    // Human-friendly version name\n" "$2"
  printf "\$branch   = '%s';                      // This version's branch.\n" "$3"
}

# Um GitHub falso: a lista de commits de cada ref em $FAKE_GITHUB/api-<ref>.json
# (ou o código HTTP em api-<ref>.code) e o version.php de cada commit em raw-<sha>.
fake_github() {
  export FAKE_GITHUB="$BATS_TEST_TMPDIR/github"
  mkdir -p "$FAKE_GITHUB"
  cat > "$STUBS_BIN/curl" <<'STUB'
#!/usr/bin/env bash
out="" url="" write=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift ;;
    -w) write="$2"; shift ;;
    -H|--max-time) shift ;;
    http*) url="$1" ;;
  esac
  shift
done
printf 'curl %s\n' "$url" >> "$FAKE_GITHUB/calls"
code=404 source=""
case "$url" in
  https://api.github.com/repos/moodle/moodle/commits\?*)
    ref="${url#*sha=}"; ref="${ref%%&*}"
    if [[ -f "$FAKE_GITHUB/api-$ref.code" ]]; then code="$(cat "$FAKE_GITHUB/api-$ref.code")"
    elif [[ -f "$FAKE_GITHUB/api-$ref.json" ]]; then code=200; source="$FAKE_GITHUB/api-$ref.json"; fi ;;
  https://raw.githubusercontent.com/moodle/moodle/*)
    sha="${url#https://raw.githubusercontent.com/moodle/moodle/}"; sha="${sha%%/*}"
    [[ -f "$FAKE_GITHUB/raw-$sha" ]] && { code=200; source="$FAKE_GITHUB/raw-$sha"; } ;;
esac
[[ -n "$source" && -n "$out" ]] && cp "$source" "$out"
[[ -n "$write" ]] && printf '%s' "$code"
[[ -z "$write" && "$code" != 200 ]] && exit 22
exit 0
STUB
  chmod +x "$STUBS_BIN/curl"
}

# A lista como a API a devolve: cada commit traz shas aninhados (tree, parents).
commits_json() {
  local first=1 sha
  printf '[\n'
  for sha in "$@"; do
    (( first )) || printf ',\n'
    first=0
    cat <<JSON
  {
    "sha": "$sha",
    "commit": {
      "message": "weekly release",
      "tree": { "sha": "1111111111111111111111111111111111111111" }
    },
    "parents": [
      { "sha": "$SHA_PARENT", "url": "https://api.github.com/repos/moodle/moodle/commits/$SHA_PARENT" }
    ]
  }
JSON
  done
  printf ']\n'
}

pin() { in_project 'load_recipe moodle; recipe_pin "$PWD"'; }

@test "url_for monta o diretório da branch do Moodle com dois dígitos e o pacote de um commit" {
  run libraries '
    [ "$(url_for moodle 5.3.1)" = "https://download.moodle.org/download.php/direct/stable503/moodle-5.3.1.tgz" ]
    [ "$(url_for moodle 4.5.1)" = "https://download.moodle.org/download.php/direct/stable405/moodle-4.5.1.tgz" ]
    [ "$(url_for moodle 5.0)" = "https://download.moodle.org/download.php/direct/stable500/moodle-5.0.tgz" ]
    [ "$(url_for moodle latest-503)" = "https://download.moodle.org/download.php/direct/stable503/moodle-latest-503.tgz" ]
    [ "$(url_for moodlegit '"$SHA_WEEKLY"')" = "https://github.com/moodle/moodle/archive/'"$SHA_WEEKLY"'.tar.gz" ]
    [ "$(cache_name moodlegit '"$SHA_WEEKLY"')" = "moodle-git-'"$SHA_WEEKLY"'.tar.gz" ]
  '
  [ "$status" -eq 0 ]
}

@test "json_array_field lê só o campo dos objetos de primeiro nível, indentado ou numa linha" {
  commits_json "$SHA_NEWER" "$SHA_WEEKLY" > "$BATS_TEST_TMPDIR/list.json"
  run libraries 'json_array_field sha < "'"$BATS_TEST_TMPDIR/list.json"'"'
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n%s' "$SHA_NEWER" "$SHA_WEEKLY")" ]

  tr -d '\n ' < "$BATS_TEST_TMPDIR/list.json" > "$BATS_TEST_TMPDIR/flat.json"
  run libraries 'json_array_field sha < "'"$BATS_TEST_TMPDIR/flat.json"'"'
  [ "$output" = "$(printf '%s\n%s' "$SHA_NEWER" "$SHA_WEEKLY")" ]

  cat > "$BATS_TEST_TMPDIR/escaped.json" <<'JSON'
[{"sha": "a\"b", "x": "sha"}, {"x": {"sha": "nao"}, "sha": null}]
JSON
  run libraries 'json_array_field sha < "'"$BATS_TEST_TMPDIR/escaped.json"'"'
  [ "$output" = 'a"b' ]
}

@test "project_conf_set acrescenta numa linha própria e project_conf_unset apaga" {
  printf 'PROJECT="x"' > "$TEST_PROJECT/dev.conf"
  run libraries '
    project_conf_set "'"$TEST_PROJECT"'/dev.conf" MOODLE_VERSION 5.3.1+
    project_conf_set "'"$TEST_PROJECT"'/dev.conf" MOODLE_VERSION 5.3.2
    project_conf_set "'"$TEST_PROJECT"'/dev.conf" MOODLE_COMMIT abc
    project_conf_unset "'"$TEST_PROJECT"'/dev.conf" MOODLE_COMMIT
    project_conf_unset "'"$TEST_PROJECT"'/dev.conf" NAO_EXISTE
  '
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_PROJECT/dev.conf")" = "$(printf 'PROJECT="x"\nMOODLE_VERSION="5.3.2"')" ]
}

@test "recipe_pin do Moodle numa release grava a versão e apaga o commit, sem consultar o GitHub" {
  fake_github
  moodle_core 2026100501.00 "5.3.1 (Build: 20261112)"
  run pin
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'MOODLE_VERSION=5.3.1\nMOODLE_COMMIT=')" ]
  [ ! -f "$FAKE_GITHUB/calls" ]
}

@test "recipe_pin do Moodle numa build semanal acha o commit com o mesmo version e release" {
  fake_github
  local release="5.3.1+ (Build: 20261117)"
  moodle_core 2026100501.01 "$release"
  commits_json "$SHA_NEWER" "$SHA_WEEKLY" "$SHA_RELEASE" > "$FAKE_GITHUB/api-MOODLE_503_STABLE.json"
  # Um commit posterior subiu o version; o pai dele, fora da lista de primeiro
  # nível, tem o mesmo version.php da build e não pode ser escolhido.
  version_php 2026100501.02 "$release" > "$FAKE_GITHUB/raw-$SHA_NEWER"
  version_php 2026100501.01 "$release" > "$FAKE_GITHUB/raw-$SHA_PARENT"
  version_php 2026100501.01 "$release" > "$FAKE_GITHUB/raw-$SHA_WEEKLY"
  version_php 2026100501.00 "5.3.1 (Build: 20261112)" > "$FAKE_GITHUB/raw-$SHA_RELEASE"

  run pin
  [ "$status" -eq 0 ]
  [[ "$output" == *"MOODLE_VERSION=5.3.1+"* ]]
  [[ "$output" == *"MOODLE_COMMIT=$SHA_WEEKLY"* ]]
  grep -q "sha=MOODLE_503_STABLE&path=public/version.php&since=2026-10-27T00:00:00Z&until=2026-11-25T00:00:00Z" "$FAKE_GITHUB/calls"
  ! grep -q "$SHA_PARENT" "$FAKE_GITHUB/calls"
  ! grep -q "$SHA_RELEASE" "$FAKE_GITHUB/calls"
}

@test "recipe_pin do Moodle em desenvolvimento procura na main quando a branch estável não existe" {
  fake_github
  moodle_core 2026112000.00 "5.4dev (Build: 20261120)" 504
  echo 404 > "$FAKE_GITHUB/api-MOODLE_504_STABLE.code"
  commits_json "$SHA_WEEKLY" > "$FAKE_GITHUB/api-main.json"
  version_php 2026112000.00 "5.4dev (Build: 20261120)" 504 > "$FAKE_GITHUB/raw-$SHA_WEEKLY"

  run pin
  [ "$status" -eq 0 ]
  [[ "$output" == *"MOODLE_VERSION=5.4dev"* ]]
  [[ "$output" == *"MOODLE_COMMIT=$SHA_WEEKLY"* ]]
}

@test "recipe_pin do Moodle explica o limite do GitHub e o núcleo sem commit igual" {
  fake_github
  moodle_core 2026100501.01 "5.3.1+ (Build: 20261117)"
  echo 403 > "$FAKE_GITHUB/api-MOODLE_503_STABLE.code"
  run pin
  [ "$status" -ne 0 ]
  [[ "$output" == *"limite de 60 por hora"* ]]
  [[ "$output" != *"MOODLE_COMMIT="* ]]

  rm "$FAKE_GITHUB/api-MOODLE_503_STABLE.code"
  commits_json "$SHA_NEWER" > "$FAKE_GITHUB/api-MOODLE_503_STABLE.json"
  version_php 2026100501.02 "5.3.1+ (Build: 20261117)" > "$FAKE_GITHUB/raw-$SHA_NEWER"
  run pin
  [ "$status" -ne 0 ]
  [[ "$output" == *"não achei no GitHub o commit do Moodle 5.3.1+"* ]]
  [[ "$output" == *'MOODLE_VERSION="5.3.1"'* ]]
}

@test "recipe_install do Moodle baixa o commit, a release ou a build da branch, conforme o dev.conf" {
  run libraries '
    load_recipe moodle
    download() { printf "download %s\n" "$1" >&2; printf "/x.tgz\n"; }
    download_fresh() { printf "fresh %s\n" "$1" >&2; printf "/x.tgz\n"; }
    MOODLE_VERSION="5.3.1+" MOODLE_COMMIT="'"$SHA_WEEKLY"'" moodle_tarball 2>&1
    MOODLE_VERSION="5.3.1" MOODLE_COMMIT="" moodle_tarball 2>&1
    MOODLE_VERSION="" MOODLE_COMMIT="" moodle_tarball 2>&1
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"download https://github.com/moodle/moodle/archive/$SHA_WEEKLY.tar.gz"* ]]
  [[ "$output" == *"download https://download.moodle.org/download.php/direct/stable503/moodle-5.3.1.tgz"* ]]
  [[ "$output" == *"fresh https://download.moodle.org/download.php/direct/stable503/moodle-latest-503.tgz"* ]]
}

@test "recipe_install do Moodle recusa uma build semanal sem o commit" {
  run libraries '
    load_recipe moodle
    download() { echo "não devia baixar"; }
    MOODLE_VERSION="5.3.1+" MOODLE_COMMIT="" moodle_tarball
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"não é uma release"* ]]
  [[ "$output" == *"dev pin"* ]]
  [[ "$output" != *"não devia baixar"* ]]
}

@test "recipe_pin do WordPress grava a versão publicada e recusa a nightly" {
  mkdir -p "$TEST_PROJECT/wp-includes"
  touch "$TEST_PROJECT/wp-settings.php"
  printf "<?php\n\$wp_version = '6.8.3';\n" > "$TEST_PROJECT/wp-includes/version.php"
  run in_project 'load_recipe wordpress; recipe_pin "$PWD"'
  [ "$status" -eq 0 ]
  [ "$output" = "WORDPRESS_VERSION=6.8.3" ]

  printf "<?php\n\$wp_version = '6.9-alpha-61000';\n" > "$TEST_PROJECT/wp-includes/version.php"
  run in_project 'load_recipe wordpress; recipe_pin "$PWD"'
  [ "$status" -ne 0 ]
  [[ "$output" == *"nightly"* ]]
}

@test "dev pin grava a versão no dev.conf e regrava depois de uma atualização" {
  project_conf APP=moodle
  printf 'MOODLE_VERSION="5.3.1+"\nMOODLE_COMMIT="%s"\n' "$SHA_WEEKLY" >> "$TEST_PROJECT/dev.conf"
  moodle_core 2026100502.00 "5.3.2 (Build: 20261210)"
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; cmd_pin'
  [ "$status" -eq 0 ]
  [[ "$output" == *'dev.conf  MOODLE_VERSION="5.3.2"'* ]]
  [[ "$output" == *"faça commit do dev.conf"* ]]
  grep -qx 'MOODLE_VERSION="5.3.2"' "$TEST_PROJECT/dev.conf"
  ! grep -q MOODLE_COMMIT "$TEST_PROJECT/dev.conf"
  grep -qx 'PROJECT="test-site"' "$TEST_PROJECT/dev.conf"
}

@test "dev pin no Laravel não grava nada e aponta o composer.lock" {
  project_conf APP=laravel
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; cmd_pin'
  [ "$status" -eq 0 ]
  [[ "$output" == *"não há composer.lock"* ]]
  [[ "$output" != *"faça commit do dev.conf"* ]]
  ! grep -q VERSION "$TEST_PROJECT/dev.conf"
}

@test "pin_if_missing grava só quando o dev.conf ainda não tem a versão" {
  project_conf APP=moodle
  moodle_core 2026100501.00 "5.3.1 (Build: 20261112)"
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; load_recipe moodle; pin_if_missing "$PWD"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"ainda não fixa a versão"* ]]
  grep -qx 'MOODLE_VERSION="5.3.1"' "$TEST_PROJECT/dev.conf"

  moodle_core 2026100502.00 "5.3.2 (Build: 20261210)"
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; load_recipe moodle; pin_if_missing "$PWD"'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -qx 'MOODLE_VERSION="5.3.1"' "$TEST_PROJECT/dev.conf"
}

@test "pin_if_missing avisa sem derrubar o dev up quando não consegue fixar" {
  project_conf APP=moodle
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; load_recipe moodle; pin_if_missing "$PWD"; echo seguiu'
  [ "$status" -eq 0 ]
  [[ "$output" == *"a versão não foi fixada"* ]]
  [[ "$output" == *"seguiu"* ]]
}

@test "dev pin e dev up apontam o plugin instalado anterior ao dev pin" {
  project_conf APP=moodle
  mkdir -p "$DEV_HOME/plugins/installed/moodle"
  printf 'recipe_title() { printf "Moodle\\n"; }\n' > "$DEV_HOME/plugins/installed/moodle/recipe.sh"
  run in_project 'source "$DEV_ROOT/lib/pin.sh"; cmd_pin'
  [ "$status" -ne 0 ]
  [[ "$output" == *"anterior ao dev pin"* ]]
  [[ "$output" == *"dev plugin update moodle"* ]]

  run in_project 'source "$DEV_ROOT/lib/pin.sh"; load_project; load_recipe moodle; pin_if_missing "$PWD"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"dev plugin update moodle"* ]]
}
