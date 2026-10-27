# Proposal: Auto-install Build Dependencies for Runtime Compilation

## Why

Ao tentar criar ou adotar projetos que exigem versões adicionais do PHP (como o Moodle exigindo PHP 8.4 quando apenas o 8.5 está instalado), o `dev` oferece compilar o runtime sob demanda. No entanto, se o sistema operacional não possuir previamente a cadeia de ferramentas de compilação (`gcc`, `make`, `autoconf`, etc.), o processo falha abruptamente exigindo intervenção manual externa.

Integrar a detecção e instalação dessas ferramentas no fluxo do `dev install`, `dev doctor` e de forma interativa no próprio construtor de runtimes elimina o atrito de compilação sob demanda em máquinas limpas ou ambientes WSL2 recém-configurados.

## What Changes

- **Detecção e instalação de ferramentas de compilação no `dev install`**: Oferece a instalação da cadeia de ferramentas de compilação oficial (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`, `xz-utils`) durante o provisionamento do sistema.
- **Diagnóstico no `dev doctor`**: Inclui a verificação das ferramentas de compilação na seção de diagnóstico de instalação, apontando ferramentas ausentes e sugerindo comando de reparo.
- **Instalação interativa sob demanda em `tools/build-runtimes.sh`**: Ao iniciar a compilação de um runtime e constatar ferramentas faltantes, questiona o usuário interativamente se deseja instalá-las via `sudo apt` imediatamente, prosseguindo com a compilação após a instalação bem-sucedida em vez de abortar com erro.

## Capabilities

### New Capabilities

*(Nenhuma nova capability; o comportamento aprimora a capability existente do núcleo do ambiente)*

### Modified Capabilities

- `environment-core`:
  - `System Validation and Dependency Verification`: Amplia a verificação e o provisionamento de dependências no `dev install` para incluir o conjunto de ferramentas de compilação do sistema.
  - `Machine Diagnostics and Self-Healing`: Adiciona a validação do conjunto de ferramentas de compilação ao relatório de saúde do `dev doctor`.
  - `On-Demand Local PHP Runtime Compilation`: Adiciona recuperação interativa com prompt para instalação via `sudo apt` quando ferramentas de compilação estiverem ausentes durante a compilação sob demanda.

## Impact

- **Código modificado**:
  - `lib/install.sh`: Definição e oferta de instalação do conjunto `APT_BUILD_DEPS`.
  - `lib/doctor.sh`: Verificação diagnóstica do estado das ferramentas de compilação.
  - `tools/build-runtimes.sh`: Prompt interativo e execução de `sudo apt-get install` quando ferramentas estiverem ausentes em modo interativo.
- **APIs e CLI**: Nenhuma alteração retrocompatível adversa; o fluxo não-interativo/CI mantém suporte com flags ou recusa controlada.
