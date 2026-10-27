# Design

## Context

Ao solicitar uma versão do PHP não fornecida no pacote padrão (como o PHP 8.4 para o plugin do Moodle), o `dev` invoca `tools/build-runtimes.sh php <versão>`. Esse script orquestra o utilitário `static-php-cli` (`spc`), obtido em sua versão oficial `2.8.5`.

A tentativa de compilação sob demanda falhava devido a falhas encadeadas no `build_php_runtime()` de `tools/build-runtimes.sh`:
1. Ausência de `cd "$work_dir"` fazia o `spc` executar no diretório atual do usuário ou do repositório, enquanto a verificação de saída buscava em caminhos fixos de `/tmp/wdev-runtimes`.
2. O `spc` requer um binário local de `pkg-config` em `pkgroot/` gerido pelo comando `spc install-pkg pkg-config`. Ao tentar baixá-lo como código-fonte em `spc download`, a compilação abortava com `Cannot find pkg-config executable`.
3. No Linux, `spc` adota `musl` por padrão; sem `SPC_LIBC=glibc`, o `MuslToolchain` falha exigindo `musl-wrapper`.
4. A lista `PHP_STANDARD_EXTENSIONS` incluía tokens que o `spc` rejeita como módulos compiláveis (`date`, `lexbor`, `random`, `uri`, `core`, `standard`), gerando abort com `Extension [date] not exist !`.
5. Redirecionamento `>/dev/null 2>&1` ocultava os erros exatos, dificultando qualquer diagnóstico.

## Goals / Non-Goals

**Goals:**
- Garantir que a compilação sob demanda de qualquer versão solicitada do PHP (como 8.4.6) seja concluída sem falhas usando as ferramentas nativas (`gcc`, `g++`, `make`) da máquina host via `glibc`.
- Executar todas as etapas do `spc` (`install-pkg`, `download`, `build`) dentro do diretório isolado de trabalho `$work_dir` (`/tmp/wdev-runtimes/php-$version`), garantindo idempotência e preservando o diretório de chamada.
- Instalar previamente o pacote interno `pkg-config` requerido pelo `spc`.
- Filtrar rigorosamente as extensões para passar apenas módulos estáticos válidos reconhecidos pelo `spc build`.
- Preservar logs de build em `$work_dir/build.log` e exibi-los ou apontá-los em caso de erro.
- Atualizar a suíte de testes BATS em `tests/build_runtimes.bats` para cobrir o fluxo corrigido.

**Non-Goals:**
- Não alterar as versões do PHP Core (8.5.12) ou ferramentas base pré-instaladas.
- Não introduzir dependência obrigatória de compilação `musl` (o ambiente foi concebido para `glibc` nativo no Ubuntu/WSL2).
- Não alterar a interface de linha de comando pública do `dev`.

## Decisions

### Decisão 1: Execução hermética no diretório de trabalho do runtime
- **Escolha**: Executar os comandos do `spc` dentro de um subshell `(cd "$work_dir" && ...)` ou navegando explicitamente com restauração garantida de diretório.
- **Justificativa**: O `spc` gera e consulta subdiretórios relativos (`downloads/`, `pkgroot/`, `buildroot/`). Isolar o build em `$work_dir` evita poluição do repositório ou do diretório do usuário e garante que `$work_dir/buildroot/bin/php` e `$work_dir/buildroot/bin/php-fpm` existam no caminho esperado pelo empacotador.
- **Alternativa descartada**: Executar no repositório raiz e mover arquivos manualmente. Descartado por poluir a árvore de arquivos e violar contratos de idempotência.

### Decisão 2: Instalação do pacote auxiliar `pkg-config` do `spc`
- **Escolha**: Antes da compilação, executar `"$spc" install-pkg pkg-config` no diretório de trabalho.
- **Justificativa**: A classe `PkgConfigUtil` do `spc` valida especificamente a existência de `pkgroot/x86_64-linux/bin/pkg-config` ou `buildroot/bin/pkg-config`. A chamada `install-pkg` baixa o binário pré-compilado pelo projeto `static-php-cli` em segundos, resolvendo a dependência sem requerer compilação de código-fonte adicional.
- **Alternativa descartada**: Deixar o `spc doctor --auto-fix` tentar resolver interativamente. Descartado porque exige intervenção manual interativa e falha em pipelines automatizados.

### Decisão 3: Configuração explícita de `SPC_LIBC=glibc`
- **Escolha**: Exportar `SPC_LIBC=glibc` durante o processo de build do PHP.
- **Justificativa**: A classe `ToolchainManager` do `spc` seleciona `GccNativeToolchain` quando `SPC_LIBC=glibc` está definido em sistemas glibc (como Ubuntu/WSL2), utilizando o `gcc` e `g++` nativos já verificados por `check_build_deps`. Isso evita a tentativa do `spc` de acionar `MuslToolchain` que falha pela ausência do `musl-wrapper`.
- **Alternativa descartada**: Exigir a instalação do `musl-tools` / `musl-wrapper` no sistema do usuário. Descartado pois o repositório define a interoperabilidade estática com `glibc` nativo.

### Decisão 4: Filtragem e saneamento de extensões para `spc build`
- **Escolha**: Criar uma função de saneamento `filter_spc_extensions()` em `tools/build-runtimes.sh` que recebe a string de extensões e remove palavras-chave que não são nomes de extensões aceitos pelo `spc` (`core`, `standard`, `date`, `lexbor`, `random`, `uri`).
- **Justificativa**: `core`, `standard`, `date`, `random` já são compilados intrinsecamente no núcleo do PHP pelo `spc`. `lexbor` é biblioteca do `dom`. `uri` não existe na versão 8.4. O `spc` aborta com erro fatal se encontrar extensões desconhecidas.
- **Alternativa descartada**: Reduzir a lista `PHP_STANDARD_EXTENSIONS` globalmente. Descartado porque ela também é usada como referência descritiva de recursos suportados no manifesto e no CLI. A filtragem deve ocorrer na interface de envio para a CLI do `spc`.

### Decisão 5: Logs e depuração
- **Escolha**: Redirecionar stdout e stderr para `$work_dir/build.log` e `$work_dir/download.log`, mantendo saída limpa no terminal durante o sucesso e exibindo o final do log ou mensagem de erro se a etapa falhar.
- **Justificativa**: Elimina a ocultação de erros (`>/dev/null 2>&1`), viabilizando suporte e diagnóstico sem poluir a experiência normal do usuário.

## Risks / Trade-offs

- **[Risco] Tempo de compilação da primeira execução de uma versão sob demanda**: A compilação completa do PHP com suas extensões pode levar alguns minutos de CPU.
  - *Mitigação*: Informar ao usuário antes de iniciar, utilizar múltiplos cores (`SPC_CONCURRENCY=$(nproc)`), permitir reutilização de artefatos baixados em cache e empacotar o `.tar.xz` em `runtimes/php/` para que compilações futuras não sejam necessárias.
- **[Risco] Falha de rede no download das fontes do PHP**:
  - *Mitigação*: `spc` possui mecanismos de fallback de mirrors e retentativas; o script preserva o log em caso de falha.
