# Tasks

## 1. Centralização da Lista de Ferramentas de Compilação

- [x] 1.1 Centralizar a definição da cadeia de ferramentas `APT_BUILD_DEPS` (`gcc`, `g++`, `make`, `autoconf`, `automake`, `libtool`, `bison`, `re2c`, `flex`, `autopoint`, `cmake`, `pkg-config`, `xz-utils`) e utilitário `missing_build_deps` de forma acessível para `lib/install.sh`, `lib/doctor.sh` e `tools/build-runtimes.sh`, verificando carregamento sem erros
- [x] 1.2 Adicionar testes em `tests/build_runtimes.bats` validando a resolução e detecção das dependências de compilação

## 2. Integração no `dev install`

- [x] 2.1 Incluir verificação e confirmação de instalação para `APT_BUILD_DEPS` em `lib/install.sh` (`install_apt`), garantindo provisionamento completo em máquinas novas
- [x] 2.2 Adicionar e verificar testes unitários para a inclusão das dependências de compilação no fluxo de instalação do `dev`

## 3. Diagnóstico no `dev doctor`

- [x] 3.1 Adicionar checagem diagnóstica das ferramentas de compilação na seção `INSTALAÇÃO` de `lib/doctor.sh`, exibindo linha `build-tools` e recomendações corretivas
- [x] 3.2 Executar `dev doctor` em teste ou ambiente local e verificar que o diagnóstico aponta corretamente a presença ou ausência das ferramentas

## 4. Auto-recuperação Interativa na Compilação Sob Demanda

- [ ] 4.1 Implementar em `tools/build-runtimes.sh` (`check_build_deps`) prompt interativo para instalar as ferramentas faltantes via `sudo apt` com confirmação do usuário e prosseguimento automático do build, mantendo abort com código 1 em sessões não-interativas
- [ ] 4.2 Adicionar testes BATS em `tests/build_runtimes.bats` cobrindo recusa/modo não-interativo e fluxo de confirmação e continuação da compilação

## 5. Validação de Integração e Conformidade

- [ ] 5.1 Executar a suíte completa `./tools/check.sh` e validar que sintaxe, shellchecks e todos os testes BATS passam
- [ ] 5.2 Validar conformidade das especificações OpenSpec através de `openspec validate auto-install-build-dependencies --strict`
