#!/usr/bin/env bash
# Versões fixadas. Este arquivo vai para o git e garante que todo o time
# execute exatamente o mesmo ambiente.
#
# O PHP e o nginx vêm pré-compilados de runtimes/manifest.sh com sha256 fixado.
# Este arquivo fixa os binários oficiais baixados e portas padrão.

DEV_VERSION="0.1.0-dev"

# Binários oficiais e ferramentas utilitárias
MYSQL_VERSION="8.4.9"        # LTS; https://dev.mysql.com/downloads/mysql/
NODE_VERSION="24.21.0"       # linha LTS; https://nodejs.org/dist/
COMPOSER_VERSION="2.10.3"    # https://getcomposer.org/download/
MAILPIT_VERSION="1.31.3"     # https://github.com/axllent/mailpit/releases
ADMINER_VERSION="6.1.1"      # https://github.com/vrana/adminer/releases
MKCERT_VERSION="1.4.4"       # https://github.com/FiloSottile/mkcert/releases

# Versões de ferramentas e instaladores usados pelos plugins
WPCLI_VERSION="2.12.0"       # Plugin WordPress; https://github.com/wp-cli/wp-cli/releases
WORDPRESS_VERSION=""         # Vazio = versão mais recente estável
MOODLE_VERSION=""            # Vazio = branch estável mais recente
MOODLE_BRANCH="502"          # Branch base de busca do Moodle
LARAVEL_INSTALLER="5.11.0"   # Plugin Laravel; instalador oficial via Composer

# Portas padrão.
# Portas altas para serviços auxiliares evitam colisão com instâncias do sistema.
HTTP_PORT="80"
HTTPS_PORT="443"
MYSQL_PORT="13306"
SMTP_PORT="11025"
MAILPIT_UI_PORT="18025"
