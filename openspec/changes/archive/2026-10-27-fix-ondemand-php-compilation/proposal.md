# Proposal

## Why

Ao provisionar um novo projeto Moodle (`dev new moodle ead`), o sistema detecta que o Moodle requer PHP 8.4 e solicita autorização para compilar a versão sob demanda a partir do código-fonte oficial. No entanto, o processo falha com o erro `a compilação do PHP 8.4.6 não produziu os binários esperados em /tmp/wdev-runtimes`, interrompendo a criação do projeto.

A falha ocorre devido a múltiplos defeitos no script `tools/build-runtimes.sh`:
1. `spc` é executado a partir do diretório corrente de trabalho (cwd) em vez de navegar para o subdiretório isolado de build (`$work_dir`), fazendo com que arquivos de build não sejam encontrados nos caminhos esperados.
2. O utilitário `static-php-cli` (`spc`) necessita da ferramenta de empacotamento `pkg-config` em seu ambiente interno (`pkgroot/`), a qual deve ser instalada via `spc install-pkg pkg-config`. A chamada anterior tentava baixar `pkg-config` como código-fonte em `spc download`, gerando o erro interno `Cannot find pkg-config executable. Please run doctor to fix this.`.
3. `spc` utiliza por padrão a libc `musl` no Linux caso não seja explicitado `SPC_LIBC=glibc`, falhando em distribuições Ubuntu/WSL2 pela ausência do `musl-wrapper`.
4. A lista `PHP_STANDARD_EXTENSIONS` contém pseudo-extensões e extensões built-in (`date`, `lexbor`, `random`, `uri`) que não são aceitas como argumentos de extensão pelo `spc build`, provocando o erro fatal imediato `Extension [date] not exist !`.
5. Os comandos do `spc` tinham sua saída redirecionada para `>/dev/null 2>&1`, silenciando os diagnósticos e ocultando a causa raiz da falha.
6. A checagem final de binários procurava em `$BUILD_DIR/buildroot` em vez de inspecionar `$work_dir/buildroot`.

Corrigir esses pontos garante que a compilação sob demanda do PHP 8.4 (e qualquer outra versão solicitada) seja executada de ponta a ponta com sucesso, habilitando o provisionamento hermético e idempotente de projetos Moodle e de outras aplicações com versões de PHP distintas da versão base 8.5.

## What Changes

- **Isolamento de Diretório de Compilação**: Navegar (`cd "$work_dir"`) antes de executar os comandos do `spc`, assegurando que `downloads/`, `pkgroot/` e `buildroot/` sejam gerados no diretório isolado do runtime e que os binários produzidos em `$work_dir/buildroot/bin` sejam devidamente localizados e empacotados.
- **Instalação do Pacote Interno do pkg-config**: Executar `spc install-pkg pkg-config` no diretório de trabalho antes da compilação, atendendo aos requisitos internos do `PkgConfigUtil` do `spc`.
- **Configuração Explícita da Libc e Toolchain**: Exportar `SPC_LIBC=glibc` durante a compilação para instruir o `spc` a utilizar `GccNativeToolchain` com o compilador nativo do sistema (`gcc`, `g++`, `make`), eliminando a dependência do `musl-wrapper`.
- **Saneamento e Filtragem de Extensões do PHP**: Filtrar adequadamente as extensões em `PHP_STANDARD_EXTENSIONS` antes de passá-las ao `spc build`, removendo itens built-in ou inválidos (`core`, `standard`, `date`, `lexbor`, `random`, `uri`), garantindo que apenas extensões compiláveis válidas sejam passadas.
- **Download Inteligente de Fontes e Bibliotecas**: Utilizar a flag `--for-extensions` (ou especificação correta de fontes e pre-built libs com `--prefer-pre-built`) no `spc download`, assegurando a obtenção completa das bibliotecas necessárias (como `icu`, `openssl`, `libxml2`, `bzip2`, `zlib`, etc.) sem erros.
- **Visibilidade de Diagnósticos e Logs**: Capturar a saída dos comandos do `spc` em arquivos de log (`$work_dir/build.log` e `$work_dir/download.log`) em vez de descartá-los para `/dev/null`, exibindo mensagens claras e o caminho do log em caso de erro.
- **Testes Automatizados**: Atualizar e adicionar testes no framework BATS (`tests/build_runtimes.bats`) para validar o fluxo de compilação, a filtragem de extensões e a integração correta com o `spc`.

## Capabilities

### New Capabilities
*(Nenhuma nova capacidade é introduzida neste change.)*

### Modified Capabilities
- `environment-core`: Atualização do requisito `On-Demand Local PHP Runtime Compilation` para garantir a execução correta da cadeia de ferramentas do `static-php-cli` (instalação de pacotes auxiliares como `pkg-config`, seleção de libc `glibc` nativa, saneamento de extensões e localização correta dos binários em subdiretórios isolados de build).

## Impact

- **Código Modificado**: `tools/build-runtimes.sh` e `tests/build_runtimes.bats`.
- **APIs / CLI**: Nenhuma quebra de contrato na CLI do `dev`. Comandos `dev new moodle <nome>` e `tools/build-runtimes.sh php 8.4` agora completam a compilação com sucesso sem intervenção manual.
- **Compatibilidade**: Total compatibilidade mantida com WSL2 e Linux baseados em glibc (Ubuntu/Debian). Preserva o formato de empacotamento `.tar.xz`, atualização de `manifest.sh` e hashes `SHA256SUMS`.
