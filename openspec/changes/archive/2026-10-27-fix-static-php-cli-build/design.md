# Design: Obtenção Resiliente do static-php-cli e Compilação Sob Demanda

## Context

Para compilar versões alternativas do PHP sob demanda (como PHP 8.4 para projetos Moodle), o `dev` utiliza `tools/build-runtimes.sh`, que orquestra o utilitário `static-php-cli` (`spc`). Na implementação atual, a URL de download em `spc_binary()` apontava para uma versão inexistente (`3.6.1`) e para um binário bruto inexistente (`spc-linux-x86_64`), resultando em erro HTTP 404 pelo `curl`. Além disso, o utilitário `spc` exige o utilitário de sistema `bzip2`, que não constava no array centralizado `APT_BUILD_DEPS`.

Ver motivação detalhada em [proposal.md](proposal.md) e requisitos em [specs/environment-core/spec.md](specs/environment-core/spec.md).

## Goals / Non-Goals

**Goals:**
- Fixar a versão oficial estável do `static-php-cli` (`2.8.5`).
- Implementar o fluxo de download, extração do tarball `.tar.gz` e validação do binário `spc` no diretório de cache (`~/.cache/dev/spc/spc`).
- Incluir `bzip2` na lista centralizada `APT_BUILD_DEPS` e em mensagens diagnósticas.
- Ajustar os parâmetros de chamada da CLI do `spc` (`--with-php="$series"`).
- Garantir que testes BATS cubram o download do tarball e a validação de ferramentas sem depender de conexão de rede externa.

**Non-Goals:**
- Compilar previamente o PHP 8.4 para inclusão estática no git (o modelo permanece compilação sob demanda).
- Modificar o pipeline de compilação estática do nginx.
- Alterar as 47 extensões padrão ou reintroduzir suporte a SQLite.

## Decisions

### Decisão 1: Download de Tarball Oficial (.tar.gz) com Validação de Execução
- **Decisão**: Alterar `spc_binary()` para baixar `https://github.com/crazywhalecc/static-php-cli/releases/download/$SPC_VERSION/spc-linux-x86_64.tar.gz`, extrair via `tar -xz` para um arquivo temporário e mover atomicamente para o destino `$cache_dir/spc`.
- **Validação**: Antes de considerar o binário pronto, executar `spc --version` para atestar que o binário é funcional na arquitetura do host.
- **Alternativas consideradas**:
  - *Baixar binário descompactado*: Inviável, pois o repositório oficial do `static-php-cli` distribui apenas arquivos compactados em formato `.tar.gz` para Linux.
  - *Compilar o spc a partir do PHP local*: Inviável sem um ambiente PHP completo de compilação com extensões Phar ativas e dependências do Composer.

### Decisão 2: Inclusão do bzip2 em APT_BUILD_DEPS
- **Decisão**: Adicionar `bzip2` ao array `APT_BUILD_DEPS` em `lib/runtime.sh` e atualizar a lista de requisitos em `tools/build-runtimes.sh`.
- **Justificativa**: O `spc` executa uma rotina interna de verificação (`LinuxToolCheckList`) que falha quando `bzip2` não está instalado no PATH do sistema. Ao centralizar no `APT_BUILD_DEPS`, o `dev install`, `dev doctor` e `tools/build-runtimes.sh check-deps` garantem a presença da ferramenta.
- **Alternativas consideradas**:
  - *Permitir que o spc doctor instale*: Requer interação do usuário via terminal interativo, que falha silenciosamente ou trava em processos automatizados.

### Decisão 3: Parâmetros da CLI do spc
- **Decisão**: No comando `$spc download`, substituir `--for-php="$series"` por `--with-php="$series"`.
- **Justificativa**: A opção reconhecida pela CLI do `spc 2.8.5` para selecionar a série de compilação do PHP no download de fontes é `--with-php`.

## Risks / Trade-offs

- **[Risco] Falha temporária de rede ao baixar o spc no primeiro build**  
  → *Mitigação*: Armazenamento permanente em cache local (`~/.cache/dev/spc/spc`), permitindo reutilização indefinida em builds subsequentes sem novos acessos à internet para o compilador.
- **[Risco] Arquivo corrompido no cache em caso de interrupção abrupta do download**  
  → *Mitigação*: Uso de arquivo temporário (`mktemp`) para download e extração antes de mover para o caminho final; validação com `$cache_dir/spc --version` antes de reutilizar o cache existente.
- **[Risco] Testes BATS tentarem acessar a internet**  
  → *Mitigação*: Mock do comando `curl` e de extração do tarball nos testes automatizados, assegurando velocidade e independência de rede em `./tools/check.sh`.
