#!/usr/bin/env bash
# Versões do runtime próprio. Gerado por tools/build-runtimes.sh — não edite à
# mão: o sha256 aqui é o que o install confere antes de extrair.

PHP_RUNTIME_VERSION="8.5.12"
PHP_RUNTIME_FILE="php/php-8.5.12-linux-x86_64.tar.xz"
PHP_RUNTIME_SHA256="e5bec4fb337ec0c52c8d5b68ab8a76d51dc9c529b8f32d3be014f5d82da994bb"
PHP_RUNTIME_URL=""
# A glibc com que o binário foi linkado. Ele é estático em tudo o mais — OpenSSL,
# ICU, curl, gd e companhia estão dentro —, então esta é a única exigência da
# distribuição, e o install a confere antes de extrair.
PHP_RUNTIME_GLIBC="2.38"
# Extensões que o binário promete trazer, na forma que o `php -m` devolve. O
# install confere uma a uma, e recusa o runtime que trouxer SQLite — o wdev não
# oferece SQLite. O OPcache fica de fora desta lista de propósito: o 8.5 o
# anuncia como "Zend OPcache", com espaço, e ele tem conferência própria pelo
# `php -v`.
PHP_RUNTIME_EXTENSIONS="bcmath bz2 calendar core ctype curl date dom exif fileinfo filter ftp gd hash iconv intl json lexbor libxml mbstring mysqli mysqlnd openssl pcntl pcre pdo pdo_mysql phar posix random readline reflection session simplexml soap sockets sodium spl standard tokenizer uri xml xmlreader xmlwriter xsl zip zlib"

NGINX_RUNTIME_VERSION="1.30.5"
NGINX_RUNTIME_FILE="nginx/nginx-1.30.5-linux-x86_64.tar.xz"
NGINX_RUNTIME_SHA256="53007b29bc5aa8c11f6014a1e4a6ccd5c4543f5dcf033a34a61194c1fa5d7499"
NGINX_RUNTIME_URL=""
