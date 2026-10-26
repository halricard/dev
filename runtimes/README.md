# O runtime próprio do wdev: o PHP e o nginx que vêm prontos, sem compilação no
# install.
#
# Este diretório é mídia de instalação, e vai para o git de propósito: o clone
# já traz o runtime, e o install só extrai. Quem quiser regerar roda
# tools/build-runtimes.sh numa máquina com as ferramentas de build.

## O que o tarball precisa conter

O do nginx **não é só o binário**. O `nginx.conf` que o wdev gera inclui, por
caminho absoluto, arquivos de dados que vêm na distribuição do nginx:

| Arquivo | Quem usa |
|---|---|
| `conf/mime.types` | o `http {}` do `nginx.conf` gerado |
| `conf/fastcgi_params` | todo vhost com PHP |
| `logs/` (diretório) | o próprio nginx, que abre o error log do prefixo antes de ler a configuração |

Um tarball só com `sbin/nginx` instala sem reclamar e falha na primeira subida,
com `[emerg] open() ".../conf/mime.types" failed`. Aconteceu, e o
`tools/build-runtimes.sh` foi corrigido para empacotar o `conf/` inteiro — menos
o `nginx.conf` oficial, porque quem gera a configuração é o wdev.

## O que tem aqui

| Arquivo | O que é |
|---|---|
| `manifest.sh` | versão, nome do arquivo, sha256 e (opcional) URL de cada runtime. Fonte única da verdade: `wdev versions` e `lib/runtime.sh` leem daqui |
| `SHA256SUMS` | os mesmos hashes, no formato do `sha256sum -c`, para conferir à mão |
| `php/` | tarball do PHP (CLI + FPM) — **34 MB**, 47 extensões, sem SQLite |
| `nginx/` | tarball do nginx — **4,1 MB**, estático |

Os dois vão para o git de propósito: é o que faz o `git clone` já trazer o
ambiente, sem compilar nada. O preço é o tamanho do clone, e ele está explicado
abaixo.

## Como o install usa isto

`lib/runtime.sh` procura o tarball primeiro **aqui**; se ele não estiver, baixa
da URL do manifesto, conferindo o sha256. Depois extrai para
`~/.wdev/runtime/<componente>/<versão>/`, valida que o binário responde e que as
extensões prometidas pelo manifesto estão todas lá — e que o SQLite **não** está
(o wdev não oferece SQLite, e um binário que o trouxesse daria a impressão
contrária).

## Como regerar

```bash
tools/build-runtimes.sh php      # PHP 8.5.x estático, com FPM
tools/build-runtimes.sh nginx    # nginx estático
tools/build-runtimes.sh all      # os dois, e reescreve o manifesto e o SHA256SUMS
```

Requisitos, uma vez só, na máquina que builda (não em quem instala):

```
gcc g++ make autoconf automake libtool bison re2c flex autopoint cmake pkg-config
```

O PHP usa o [static-php-cli](https://static-php.dev) (`spc`), na versão fixada no
próprio script: ele baixa as fontes, monta as bibliotecas como estáticas e linka
um PHP que não depende de biblioteca do sistema. O alvo é **glibc**, e não musl,
para não exigir o toolchain musl instalado em `/usr/local/musl` (que precisa de
root) — o `spc` também quer o `pkg-config` isolado dele, que se instala sem root
com `spc install-pkg pkg-config`.

O build leva uns 20 minutos, e o resultado fica em
`$WDEV_BUILD_DIR/buildroot/bin/` (por padrão `/tmp/wdev-runtimes`): é de lá que
o script colhe `php`, `php-fpm` e o binário do nginx.

Ao subir a versão do PHP: mude `PHP_SERIES` no script, rode com `all`, e abra um
PR com o tarball, o `manifest.sh` e o `SHA256SUMS` novos. **Nada se atualiza
sozinho** — é o número fixado no git que faz a máquina de todo mundo ser a mesma.

## A glibc, e por que ela é a única exigência

O PHP sai **estático em tudo o que é de terceiros**: OpenSSL, ICU, curl, libxml2,
gd, zip, sodium e o resto estão dentro do binário — `ldd` mostra só `libc`,
`libm`, `libstdc++` e `libgcc`. A glibc é o único pedaço que continua vindo do
sistema, e por isso o binário exige uma versão mínima dela (hoje **2.38**: Ubuntu
24.04 é 2.39, Debian 13 é 2.41, Ubuntu 22.04 é 2.35 e **não** roda).

O `manifest.sh` declara essa versão em `PHP_RUNTIME_GLIBC`, e o `install` a
confere antes de extrair — a mensagem diz o que fazer, em vez de "não executa".

Para servir um time em distribuições mais antigas, quem mantém roda o script na
**mais antiga** delas e commita o tarball gerado: o binário construído numa glibc
2.35 roda em qualquer 2.35 ou mais nova.

## Sobre o tamanho

34 MB de PHP comprimido assusta quem esperava os ~10 MB de um PHP linkado contra
as bibliotecas do sistema — e é a mesma troca: aquele depende de `libicu74`,
`libssl3` e companhia existirem na máquina, este não depende de nada.

Quem quiser um clone menor tem uma alavanca só: tirar `intl` da lista
`PHP_EXTENSIONS` do `tools/build-runtimes.sh` e regerar. O ICU é de longe a maior
biblioteca embutida, e o WordPress **não** o exige — o custo é plugin que formata
moeda ou data por locale reclamar. A troca está registrada aqui para não ser
redescoberta no meio de um `git clone` lento.

## Licenças

O PHP é distribuído sob a PHP License 3.01 e o nginx sob a licença BSD de 2
cláusulas; os dois permitem redistribuição do binário. As licenças das
bibliotecas linkadas estaticamente saem em `tools/build-runtimes.sh --licenses`
(o próprio `spc` as lista), e devem acompanhar qualquer redistribuição.
