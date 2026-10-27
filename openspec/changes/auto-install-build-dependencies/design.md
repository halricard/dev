# Design: Auto-install Build Dependencies for Runtime Compilation

## Context

Ao compilar runtimes sob demanda (como PHP 8.4 para o plugin do Moodle), o script `tools/build-runtimes.sh` exige uma cadeia de 13 ferramentas de compilação (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`, `xz-utils`).
Atualmente:
1. `lib/install.sh` provisiona apenas pacotes básicos de execução (`APT_MIN`), sem incluir ferramentas de compilação.
2. `lib/doctor.sh` não verifica a disponibilidade de ferramentas de compilação.
3. `tools/build-runtimes.sh` emite uma mensagem com `sudo apt update && sudo apt install -y ...` e imediatamente aborta a compilação com código 1, abortando a criação de projetos dependentes no `dev new`.

Veja `proposal.md` para a motivação e `specs/environment-core/spec.md` para os requisitos contratuais.

## Goals / Non-Goals

**Goals:**
- Centralizar ou compartilhar a definição da lista `APT_BUILD_DEPS` de forma consistente entre instalação, diagnóstico e compilação.
- Integrar a checagem e instalação das ferramentas de compilação no fluxo do `dev install`.
- Adicionar verificação diagnóstica clara das ferramentas de compilação no `dev doctor`.
- Adicionar recuperação interativa no `check_build_deps` de `tools/build-runtimes.sh`: caso faltem ferramentas em sessão interativa, questionar o usuário se deseja instalar via `sudo apt` e, após a instalação bem-sucedida, prosseguir diretamente com a compilação.
- Preservar a não-interatividade em ambientes automatizados/CI (abortando com código 1 sem travar em prompts).

**Non-Goals:**
- Distribuir tarballs binários pré-compilados do PHP 8.4 neste momento (o foco deste design é tornar a compilação sob demanda robusta e autossuficiente).
- Suportar outros gerenciadores de pacotes além do `apt` (o projeto tem como alvo estrito Debian, Ubuntu e WSL2).
- Alterar as bibliotecas ou extensões do PHP compiladas pelo `spc`.

## Decisions

### Decisão 1: Lista compartilhada de dependências de compilação (`APT_BUILD_DEPS`)
- **Escolha**: Definir `APT_BUILD_DEPS` de forma que possa ser reaproveitada por `lib/install.sh`, `lib/doctor.sh` e `tools/build-runtimes.sh`.
- **Alternativa considerada**: Duplicar a lista hardcoded nos três arquivos. Descartado pelo risco de divergência futura ao adicionar ou remover dependências do `spc`.

### Decisão 2: Recuperação interativa no `check_build_deps` de `tools/build-runtimes.sh`
- **Escolha**: Em `check_build_deps()`, se `missing_build_deps` retornar ferramentas ausentes:
  1. Se a sessão for interativa (`[[ -t 0 ]]` ou flag interativa do dev) e `sudo` estiver disponível, exibir a lista de ferramentas faltantes e perguntar: `confirm "Deseja instalar as dependências de compilação com sudo apt agora?" s`.
  2. Se o usuário confirmar: executar `sudo apt-get update && sudo apt-get install -y "${missing[@]}"`.
  3. Re-verificar se as dependências foram satisfeitas. Em caso positivo, exibir mensagem de sucesso e retornar 0 para prosseguir com o build.
  4. Se não for interativo, o usuário recusar ou a instalação falhar, exibir as instruções manuais e retornar 1.
- **Alternativa considerada**: Fazer a checagem e instalação exclusivamente dentro de `lib/project.sh`. Descartado porque qualquer chamada a `dev` ou `tools/build-runtimes.sh php 8.4` direta também deve se beneficiar da auto-recuperação.

### Decisão 3: Provisionamento no `dev install`
- **Escolha**: No `lib/install.sh`, incluir a verificação de `APT_BUILD_DEPS` na rotina de verificação de pacotes do sistema (`install_apt`), garantindo que uma máquina recém-provisionada já tenha os compiladores necessários.
- **Alternativa considerada**: Criar um comando separado `dev build-deps`. Descartado porque a filosofia do `dev` é conveniência "sem fricção", alinhada ao feedback do usuário ("isso não deveria ser instalado já no dev install?").

### Decisão 4: Diagnóstico no `dev doctor`
- **Escolha**: Em `cmd_doctor()` de `lib/doctor.sh`, incluir um item `build-tools` na seção `INSTALAÇÃO`.
  - Se todas as ferramentas estiverem presentes: `ok "$(printf '%-10s %s' "build-tools" "ferramentas de compilação presentes")"`.
  - Se faltar alguma: `warn "$(printf '%-10s %s' "build-tools" "ferramentas de compilação ausentes (${#missing[@]})")"` com dica `$DEV install ou sudo apt install ...`.

## Risks / Trade-offs

- **[Risco] Necessidade de privilégio de superusuário (`sudo`)**
  → *Mitigação*: Confirmar interativamente antes de invocar `sudo`. Em caso de recusa ou falha de permissão, o comando termina amigavelmente instruindo o comando que deve ser executado pelo administrador da máquina.

- **[Risco] Tempo adicional no `dev install` em máquinas sem compiladores**
  → *Mitigação*: Pacotes como `gcc` e `make` são leves no cache do Ubuntu/Debian e levam poucos segundos para baixar e descompactar, evitando minutos de bloqueio e depuração posterior quando uma compilação for disparada.

- **[Risco] Execução em ambientes de CI / testes automatizados sem stdin interativo**
  → *Mitigação*: Proteger a chamada de prompt interativo com `[[ -t 0 ]]`, garantindo que testes com redirecionamento de entrada (`< /dev/null`) não fiquem travados aguardando resposta.
