#!/usr/bin/env bats
# Testes da biblioteca lib/releases.sh e lib/runtime.sh.

load helper

@test "pinned_version devolve versões configuradas" {
  run libraries 'pinned_version node'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$NODE_VERSION" ]]

  run libraries 'pinned_version mysql'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$MYSQL_VERSION" ]]
}

@test "cache_name formata nomes com versões" {
  run libraries 'cache_name node 24.22.1'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "node-v24.22.1-linux-x64.tar.xz" ]]

  run libraries 'cache_name composer 2.10.3'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "composer-2.10.3.phar" ]]
}

@test "url_for gera URLs HTTPS válidas" {
  run libraries 'url_for node 24.22.1'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "https://nodejs.org/dist/v24.22.1/node-v24.22.1-linux-x64.tar.xz" ]]

  run libraries 'url_for composer 2.10.3'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "https://getcomposer.org/download/2.10.3/composer.phar" ]]
}

@test "runtime_version lê versão do manifesto" {
  run libraries 'runtime_version php'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "8.5.12" ]]

  run libraries 'runtime_version nginx'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "1.30.5" ]]
}

@test "runtime_version e runtime_file resolvem series parametrizadas de PHP" {
  run libraries '
    [ "$(runtime_version php 8.4)" = "8.4.27" ]
    [ "$(runtime_version php 8.5)" = "8.5.12" ]
    [ "$(runtime_file php 8.4)" = "php/php-8.4.27-linux-x86_64.tar.xz" ]
    [ "$(runtime_file php 8.5)" = "php/php-8.5.12-linux-x86_64.tar.xz" ]
  '
  [[ "$status" -eq 0 ]]
}

# Monta runtimes/php/php-$1-linux-x86_64.tar.xz com binários falsos que informam
# a versão $2. $3 é o símbolo de glibc gravado no binário.
fake_php_tarball() {
  local version="$1" reported="$2" symbol="${3:-}" pack="$BATS_TEST_TMPDIR/pack"
  export DEV_RUNTIMES_DIR="$BATS_TEST_TMPDIR/runtimes"
  mkdir -p "$DEV_RUNTIMES_DIR/php" "$pack/bin" "$pack/sbin"
  cat > "$pack/bin/php" <<SCRIPT
#!/usr/bin/env bash
# $symbol
case "\$1" in
  -v) echo "PHP $reported (cli)"; echo "with Zend OPcache" ;;
  -m) echo core ;;
  -n) printf '%s' "$reported" ;;
esac
SCRIPT
  printf '#!/usr/bin/env bash\necho "PHP %s (fpm-fcgi)"\n' "$reported" > "$pack/sbin/php-fpm"
  chmod +x "$pack/bin/php" "$pack/sbin/php-fpm"
  tar -cJf "$DEV_RUNTIMES_DIR/php/php-$version-linux-x86_64.tar.xz" -C "$pack" bin sbin
}

FAKE_MANIFEST='PHP_RUNTIME_EXTENSIONS="core"; PHP_RUNTIME_GLIBC=""'

@test "install_runtime aceita tarball cujo binario e a versao do nome" {
  fake_php_tarball 8.4.27 8.4.27
  run libraries "$FAKE_MANIFEST"'
    install_runtime php 8.4
    runtime_installed php 8.4
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"php 8.4.27"* ]]
}

@test "install_runtime recusa tarball rotulado com versao que o binario nao tem" {
  fake_php_tarball 8.4.27 8.4.26
  run libraries "$FAKE_MANIFEST"'
    install_runtime php 8.4 || { echo "status=$?"; test ! -e "$DEV_RUNTIME/php/8.4.27"; exit 3; }
  '
  [ "$status" -eq 3 ]
  [[ "$output" == *"o tarball do PHP 8.4.27 traz o binário 8.4.26"* ]]
}

@test "install_runtime recusa tarball cujo php-fpm e de outra versao" {
  fake_php_tarball 8.4.27 8.4.27
  local pack="$BATS_TEST_TMPDIR/pack"
  printf '#!/usr/bin/env bash\necho "PHP 8.4.26 (fpm-fcgi)"\n' > "$pack/sbin/php-fpm"
  tar -cJf "$DEV_RUNTIMES_DIR/php/php-8.4.27-linux-x86_64.tar.xz" -C "$pack" bin sbin
  run libraries "$FAKE_MANIFEST"'
    install_runtime php 8.4
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"o php-fpm do tarball não é o PHP 8.4.27"* ]]
}

@test "install_runtime recusa binario que exige glibc acima da maquina" {
  fake_php_tarball 8.4.27 8.4.27 GLIBC_99.99
  run libraries "$FAKE_MANIFEST"'
    install_runtime php 8.4
  '
  [ "$status" -ne 0 ]
  [[ "$output" == *"exige glibc 99.99 ou superior"* ]]
}

@test "install_runtime preserva o runtime atual quando o novo e recusado" {
  fake_php_tarball 8.4.27 8.4.26
  run libraries "$FAKE_MANIFEST"'
    mkdir -p "$DEV_RUNTIME/php/8.4.27"
    echo antigo > "$DEV_RUNTIME/php/8.4.27/sentinel"
    install_runtime php 8.4 && exit 9
    test "$(cat "$DEV_RUNTIME/php/8.4.27/sentinel")" = antigo
    test -z "$(find "$DEV_RUNTIME/php" -maxdepth 1 -name ".previous-*")"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"continua no lugar"* ]]
}

@test "install_runtime troca o runtime quando o sha muda e encerra o php-fpm antigo" {
  fake_php_tarball 8.4.27 8.4.27
  run libraries "$FAKE_MANIFEST"'
    mkdir -p "$DEV_RUNTIME/php/8.4.27" "$DEV_RUN"
    echo antigo > "$DEV_RUNTIME/php/8.4.27/sentinel"
    echo sha-antigo > "$DEV_RUNTIME/php/8.4.27/.installed"
    echo 4242 > "$DEV_RUN/php-fpm-8.4.27.pid"
    touch "$DEV_RUN/php-8.4.27.sock"
    kill() { echo "kill $*"; }
    install_runtime php 8.4
    runtime_installed php 8.4
    test ! -e "$DEV_RUNTIME/php/8.4.27/sentinel"
    test ! -e "$DEV_RUN/php-fpm-8.4.27.pid"
    test ! -e "$DEV_RUN/php-8.4.27.sock"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"kill -QUIT 4242"* ]]
  [[ "$output" == *"php-fpm 8.4.27 encerrado"* ]]
}

@test "dev install atualiza serie adicional instalada e ignora a padrao e a sem tarball" {
  fake_php_tarball 8.4.27 8.4.27
  run libraries '
    source "$DEV_ROOT/lib/install.sh"
    mkdir -p "$DEV_RUNTIME/php/8.4.6" "$DEV_RUNTIME/php/8.5.12" "$DEV_RUNTIME/php/8.3.1" "$DEV_RUNTIME/php/.previous-8.2.1"
    install_runtime() { echo "install_runtime $*"; }
    upgrade_extra_php_series
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"install_runtime php 8.4"* ]]
  [[ "$output" != *"install_runtime php 8.5"* ]]
  [[ "$output" != *"install_runtime php 8.2"* ]]
  [[ "$output" == *"PHP 8.3 instalado, mas sem tarball"* ]]
}
