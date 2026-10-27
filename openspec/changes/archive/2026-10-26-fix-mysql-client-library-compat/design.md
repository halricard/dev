# Design

## Context

O MySQL 8.4.9 é provisionado no `dev` através do binário oficial minimal (`mysql-8.4.9-linux-glibc2.28-x86_64-minimal.tar.xz`). O diretório de binários contém o daemon `mysqld` e utilitários de linha de comando como `mysql`, `mysqldump` e `mysqladmin`.

No Ubuntu 24.04+ (resolute/noble), algumas bibliotecas C foram renomeadas ou não são instaladas por padrão:
- `libaio.so.1` foi sucedida por `libaio1t64`.
- `libncurses.so.6` não vem instalada por padrão (apenas `libncursesw6` / `libncursesw.so.6`).

A função `compatibilize_libs` em `lib/install.sh` foi concebida para criar symlinks em `$prefix/lib-compat` e exportar via `LD_LIBRARY_PATH` (`sandbox_libs`). Porém, ela inspecionava apenas `mysqld` e só executava durante a primeira extração do arquivo tarball. Quando o instalador prossegue para a configuração de senha em `set_mysql_root_password` ([`lib/config.sh`](file:///home/dell/Code/dev/lib/config.sh)), a execução de `mysql` falha com código 127 por ausência de `libncurses.so.6`, mascarando o erro real como "o MySQL não aceita a senha do config nem a senha vazia".

## Goals / Non-Goals

**Goals:**
- Incluir `libncurses6` na lista de dependências mínimas do sistema (`APT_MIN`).
- Atualizar `compatibilize_libs` para verificar e compatibilizar todos os executáveis do MySQL (`mysqld`, `mysql`, `mysqldump`, `mysqladmin`).
- Implementar em `compatibilize_libs` um fallback que mapeie `libncurses.so.6` para `libncursesw.so.6` caso `libncurses.so.6` não esteja no sistema, permitindo funcionamento imediato mesmo antes de um `apt install`.
- Executar `compatibilize_libs` e `sandbox_libs` no `install_mysql` mesmo quando o diretório já estiver presente, reparando instalações existentes em re-execuções de `dev install`.
- Assegurar que `set_mysql_root_password` chame `sandbox_libs` e capture mensagens de erro para diferenciar falha de biblioteca/socket de erro de autenticação (código de erro 1045 do MySQL).
- Adicionar verificação de execução do cliente MySQL no `dev doctor` e reparo no `dev fix`.

**Non-Goals:**
- Compilar o MySQL ou ncurses a partir do código fonte.
- Modificar o plugin de autenticação do MySQL ou configurações de segurança padrão do servidor.

## Decisions

### Decisão 1: Resolução Híbrida para `libncurses.so.6` (APT + Fallback de Link em `lib-compat`)

- **Escolha**: Adicionar `libncurses6` em `APT_MIN` e, simultaneamente, ensinar `compatibilize_libs` a linkar `libncurses.so.6` -> `libncursesw.so.6` caso a biblioteca padrão não seja encontrada no sistema.
- **Justificativa**: Garante que o ambiente funcione imediatamente sem exigir que o usuário re-execute `sudo apt install`, ao mesmo tempo em que define `libncurses6` como padrão oficial para novas instalações.
- **Alternativas consideradas**:
  - *Apenas exigir `libncurses6` no apt*: Obrigaria o usuário a rodar sudo apt install antes de qualquer coisa, mesmo já tendo `libncursesw6` instalada.
  - *Compilar estaticamente o cliente*: Aumentaria complexidade e tamanho de download; o binário minimal oficial da Oracle já atende perfeitamente com os symlinks em `lib-compat`.

### Decisão 2: Inspeção Abrangente de Binários em `compatibilize_libs`

- **Escolha**: Varrer `mysqld`, `mysql`, `mysqldump` e `mysqladmin` (ou todos os executáveis sob `$prefix/bin`) em busca de bibliotecas `not found` via `ldd`.
- **Justificativa**: Evita que futuros subcomandos (como `dev db export` usando `mysqldump`) quebrem silenciosamente por bibliotecas ausentes não detectadas durante a instalação.

### Decisão 3: Tratamento de Erro Transparente em `set_mysql_root_password`

- **Escolha**: Salvar a saída de erro do cliente `mysql` em variável temporária durante o teste de conexão. Se o erro for de biblioteca ausente ou socket inacessível, exibir o motivo real em vez de reportar falha de senha.
- **Justificativa**: Fornece diagnósticos objetivos e acionáveis caso o daemon não esteja pronto ou falte alguma dependência no sistema hospedeiro.

## Risks / Trade-offs

- **[Risco] Incompatibilidade ABI entre ncurses e ncursesw**
  → *Mitigação*: Os símbolos básicos de terminal utilizados pelo cliente `mysql` são compatíveis entre ncurses e ncursesw no GNU/Linux x86_64. Testes confirmaram execução limpa e sem falhas de segmentação. A presença de `libncurses6` em `APT_MIN` assegura a biblioteca canônica a longo prazo.
