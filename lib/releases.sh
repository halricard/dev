#!/usr/bin/env bash
# Resolução de URLs de download, nomes de cache e versões fixadas.

COMPONENTS=(mysql node composer mailpit adminer mkcert)
if [[ -n "${PHP_RUNTIME_VERSION:-}" || -n "${NGINX_RUNTIME_VERSION:-}" ]]; then
  COMPONENTS=(php nginx "${COMPONENTS[@]}")
fi

pinned_version() {
  case "$1" in
    php)       printf '%s\n' "${PHP_RUNTIME_VERSION:-}" ;;
    nginx)     printf '%s\n' "${NGINX_RUNTIME_VERSION:-}" ;;
    mysql)     printf '%s\n' "$MYSQL_VERSION" ;;
    node)      printf '%s\n' "$NODE_VERSION" ;;
    composer)  printf '%s\n' "$COMPOSER_VERSION" ;;
    mailpit)   printf '%s\n' "$MAILPIT_VERSION" ;;
    adminer)   printf '%s\n' "$ADMINER_VERSION" ;;
    mkcert)    printf '%s\n' "$MKCERT_VERSION" ;;
    wpcli)     printf '%s\n' "$WPCLI_VERSION" ;;
    # A versão do WordPress e a do Moodle são de cada projeto (dev.conf).
    wordpress) printf '%s\n' "${WORDPRESS_VERSION:-}" ;;
    moodle)    printf '%s\n' "${MOODLE_VERSION:-}" ;;
    chrome|chromedriver) printf '%s\n' "$CHROME_VERSION" ;;
  esac
}

cache_name() {
  local component="$1" version="${2:-$(pinned_version "$1")}"
  case "$component" in
    php)       printf 'php-%s-linux-x86_64.tar.xz\n' "$version" ;;
    nginx)     printf 'nginx-%s-linux-x86_64.tar.xz\n' "$version" ;;
    mysql)     printf 'mysql-%s-linux-glibc2.28-x86_64-minimal.tar.xz\n' "$version" ;;
    node)      printf 'node-v%s-linux-x64.tar.xz\n' "$version" ;;
    composer)  printf 'composer-%s.phar\n' "$version" ;;
    mailpit)   printf 'mailpit-%s-linux-amd64.tar.gz\n' "$version" ;;
    adminer)   printf 'adminer-%s.php\n' "$version" ;;
    mkcert)    printf 'mkcert-v%s-linux-amd64\n' "$version" ;;
    wpcli)     printf 'wp-cli-%s.phar\n' "$version" ;;
    wordpress) printf 'wordpress-%s.tar.gz\n' "${version:-latest}" ;;
    moodle)    printf 'moodle-%s.tgz\n' "${version:-latest}" ;;
    moodlegit) printf 'moodle-git-%s.tar.gz\n' "$version" ;;
    chrome)    printf 'chrome-%s-linux64.zip\n' "$version" ;;
    chromedriver) printf 'chromedriver-%s-linux64.zip\n' "$version" ;;
    wpdevelop) printf 'wordpress-develop-%s.tar.gz\n' "$version" ;;
  esac
}

url_for() {
  local component="$1" version="${2:-$(pinned_version "$1")}"
  case "$component" in
    php)       printf '%s\n' "${PHP_RUNTIME_URL:-}" ;;
    nginx)     printf '%s\n' "${NGINX_RUNTIME_URL:-}" ;;
    mysql)     printf 'https://dev.mysql.com/get/Downloads/MySQL-%s/mysql-%s-linux-glibc2.28-x86_64-minimal.tar.xz\n' "${version%.*}" "$version" ;;
    node)      printf 'https://nodejs.org/dist/v%s/node-v%s-linux-x64.tar.xz\n' "$version" "$version" ;;
    composer)  printf 'https://getcomposer.org/download/%s/composer.phar\n' "$version" ;;
    mailpit)   printf 'https://github.com/axllent/mailpit/releases/download/v%s/mailpit-linux-amd64.tar.gz\n' "$version" ;;
    adminer)   printf 'https://github.com/vrana/adminer/releases/download/v%s/adminer-%s.php\n' "$version" "$version" ;;
    mkcert)    printf 'https://github.com/FiloSottile/mkcert/releases/download/v%s/mkcert-v%s-linux-amd64\n' "$version" "$version" ;;
    wpcli)     printf 'https://github.com/wp-cli/wp-cli/releases/download/v%s/wp-cli-%s.phar\n' "$version" "$version" ;;
    wordpress)
      if [[ -z "$version" ]]; then printf 'https://wordpress.org/latest.tar.gz\n'
      else printf 'https://wordpress.org/wordpress-%s.tar.gz\n' "$version"; fi ;;
    moodle)
      if [[ -z "$version" || "$version" == latest* ]]; then
        local branch="${version#latest-}"
        [[ -z "$branch" || "$branch" == "latest" ]] && branch="$MOODLE_BRANCH"
        printf 'https://download.moodle.org/download.php/direct/stable%s/moodle-latest-%s.tgz\n' "$branch" "$branch"
      else
        # O diretório da branch tem a versão menor com dois dígitos: 4.5 → stable405.
        local major="${version%%.*}" minor="${version#*.}"
        minor="${minor%%.*}"
        printf 'https://download.moodle.org/download.php/direct/stable%s%02d/moodle-%s.tgz\n' "$major" "$((10#$minor))" "$version"
      fi ;;
    moodlegit)
      # Pacote do GitHub para um commit: é como se reproduz uma build semanal.
      printf 'https://github.com/moodle/moodle/archive/%s.tar.gz\n' "$version" ;;
    chrome|chromedriver)
      printf 'https://storage.googleapis.com/chrome-for-testing-public/%s/linux64/%s-linux64.zip\n' "$version" "$component" ;;
    wpdevelop)
      printf 'https://github.com/WordPress/wordpress-develop/archive/refs/tags/%s.tar.gz\n' "$version" ;;
  esac
}

verify_urls() {
  local comp url code ok_all=1
  for comp in "${COMPONENTS[@]}"; do
    url="$(url_for "$comp")"
    [[ -n "$url" ]] || continue
    code="$(curl -sIL -o /dev/null --retry 2 --max-time 15 -w '%{http_code}' "$url" 2>/dev/null || echo 000)"
    if [[ "$code" =~ ^(200|301|302|307|308)$ ]]; then
      continue
    fi
    bad "download de $comp indisponível (HTTP $code): $url"
    ok_all=0
  done
  (( ok_all ))
}

cmd_versions() {
  step "VERSÕES FIXADAS"
  local comp ver
  for comp in "${COMPONENTS[@]}"; do
    ver="$(pinned_version "$comp")"
    printf '  %-12s %s\n' "$comp" "${ver:-(dinâmica)}"
  done
  blank
}
