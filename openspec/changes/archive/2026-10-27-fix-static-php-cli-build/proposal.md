# Proposal: Corrigir Download do static-php-cli e Compilação Sob Demanda do PHP

## Why

Ao provisionar um novo projeto Moodle (`dev new moodle ead`), o sistema identifica a necessidade do PHP 8.4 e solicita autorização para compilar a versão sob demanda a partir do código-fonte oficial. No entanto, o processo falha imediatamente com o erro `curl: (22) The requested URL returned error: 404` ao tentar baixar o utilitário `static-php-cli` (`spc`), impedindo o provisionamento do projeto. O script `tools/build-runtimes.sh` referencia uma versão inexistente (`3.6.1`) e assume um binário avulso em vez do arquivo compactado oficial (`.tar.gz`). Além disso, o utilitário de compilação exige a ferramenta `bzip2`, que não constava na lista de dependências de compilação do sistema (`APT_BUILD_DEPS`).

## What Changes

- **Correção da versão e URL do static-php-cli**: Atualizar `SPC_VERSION` em `tools/build-runtimes.sh` para a versão estável oficial `2.8.5` do repositório `crazywhalecc/static-php-cli`.
- **Download e extração do tarball do utilitário spc**: Modificar a função `spc_binary` para baixar o arquivo compactado `spc-linux-x86_64.tar.gz`, extrair o executável `spc`, definir permissões de execução e armazená-lo no cache do sistema (`~/.cache/dev/spc/spc`).
- **Inclusão do bzip2 nas dependências de compilação**: Adicionar `bzip2` à lista centralizada `APT_BUILD_DEPS` em `lib/runtime.sh` e documentação de requisitos em `tools/build-runtimes.sh`, garantindo que o diagnóstico e a instalação automática de ferramentas cubram todas as dependências requeridas pelo `spc`.
- **Ajuste dos parâmetros de linha de comando do spc**: Corrigir a chamada de download do código-fonte para utilizar a flag `--with-php="$series"` em conformidade com a CLI do `spc` (em substituição à flag não suportada `--for-php`), permitindo download e compilação das extensões oficiais.
- **Testes automatizados**: Atualizar os testes BATS em `tests/build_runtimes.bats` para validar o download e descompactação do `spc`, além da presença de `bzip2` em `APT_BUILD_DEPS`.

## Capabilities

### New Capabilities
Nenhuma nova capacidade é criada.

### Modified Capabilities
- `environment-core`: Atualização do requisito `On-Demand Local PHP Runtime Compilation` para especificar a obtenção resiliente do utilitário `static-php-cli` a partir de archives oficiais `.tar.gz` e a inclusão de `bzip2` nas ferramentas mínimas de compilação.

## Impact

- `tools/build-runtimes.sh`: Atualização de versão, mecanismo de download/extração de tarball e parâmetros de invocação da CLI do `spc`.
- `lib/runtime.sh`: Inclusão de `bzip2` em `APT_BUILD_DEPS`.
- `tests/build_runtimes.bats`: Testes de detecção de dependências e resolução do binário `spc`.
- Não afeta os runtimes pré-compilados já distribuídos em `runtimes/php/` nem vhosts existentes em execução.
