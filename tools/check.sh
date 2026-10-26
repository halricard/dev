#!/usr/bin/env bash
# Verificador do dev. Rode antes de abrir um PR ou commitar.
#
# Sintaxe, armadilhas de bash, nomes proibidos, shellcheck e testes de tests/.
# Em ambiente de CI, ferramentas ausentes contam como falha; localmente, o
# script avisa e segue.

set -uo pipefail
cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." || exit 1

failures=0
in_ci=0; [[ -n "${CI:-}" ]] && in_ci=1

missing() {
  if (( in_ci )); then
    echo "  ✘ $1 — obrigatório no CI"
    failures=$(( failures + 1 ))
  else
    echo "  ○ $1 — pulado"
  fi
}

shopt -s nullglob
files=(dev versions.sh)
[[ -f runtimes/manifest.sh ]] && files+=(runtimes/manifest.sh)
files+=(lib/*.sh plugins/*/*.sh tools/*.sh)
sources=(dev)
[[ -d lib ]] && sources+=(lib/*.sh)
[[ -d plugins ]] && sources+=(plugins/*/*.sh)

syntax_files=("${files[@]}")
for f in tests/*.bash; do
  [[ -f "$f" ]] && syntax_files+=("$f")
done

echo "▸ sintaxe"
for f in "${syntax_files[@]}"; do
  bash -n "$f" || { echo "  ✘ $f"; failures=$(( failures + 1 )); }
done
(( failures == 0 )) && echo "  ✔ ${#syntax_files[@]} arquivos"

echo "▸ local que referencia a si mesmo"
if ! command -v python3 >/dev/null 2>&1; then
  missing "python3 não instalado (sudo apt install python3)"
else
  found="$(python3 - <<'PY'
import re, pathlib

ATRIB = re.compile(r'(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=')
LOCAL = re.compile(r'(?:^|[{;&|]|\bthen\b|\bdo\b)\s*local\s+([^;}]*)')
total = 0
for f in sorted(pathlib.Path(".").rglob("*.sh")) + sorted(pathlib.Path(".").rglob("*.bash")):
    if not f.is_file():
        continue
    for n, line in enumerate(f.read_text().split("\n"), 1):
        if line.lstrip().startswith("#"):
            continue
        for m in LOCAL.finditer(line):
            body = m.group(1)
            for a in ATRIB.finditer(body):
                name = a.group(1)
                after = body[a.end():]
                uses = re.search(r'\$\{?' + re.escape(name) + r'\b', after) \
                    or re.search(r'\$\(\(.*?\b' + re.escape(name) + r'\b', after)
                if uses:
                    print(f"  ✘ {f}:{n}  usa {name} declarado na mesma linha")
                    total += 1
print(f"__TOTAL__{total}")
PY
)"
  total="${found##*__TOTAL__}"
  printf '%s\n' "$found" | grep -v '__TOTAL__' | grep . || true
  if [[ "$total" == "0" ]]; then
    echo "  ✔ nenhum"
  else
    echo "  declare em linhas separadas"
    failures=$(( failures + total ))
  fi
fi

echo "▸ pipeline sem guarda dentro de \$( )"
unguarded="$(grep -rn '\$([^)]*|' "${sources[@]}" 2>/dev/null \
  | grep -v '|| *true\|||  *:\||| *echo\||| *printf\||| *return\|grep -q\|grep -c' || true)"
if [[ -z "$unguarded" ]]; then
  echo "  ✔ nenhum"
else
  printf '%s\n' "$unguarded" | sed 's/^/  ✘ /'
  echo "  acrescente  || true  ao fim do pipeline"
  failures=$(( failures + 1 ))
fi

echo "▸ pipeline solto que pode não casar"
loose="$(grep -rnE '(^|[;{])[[:space:]]*(grep|ls|awk|find|du|df|cat|stat|openssl|sha256sum|tr|curl|tail|head)\b[^|]*\|[[:space:]]*(head|tail|cut|sort|uniq|wc|tr|awk|sed|grep|xargs|gzip)\b' \
  "${sources[@]}" 2>/dev/null \
  | grep -v '|| *true\|||  *:\||| *echo\||| *return\|grep -q' || true)"
if [[ -z "$loose" ]]; then
  echo "  ✔ nenhum"
else
  printf '%s\n' "$loose" | sed 's/^/  ✘ /'
  echo "  acrescente  || true  ao fim do pipeline"
  failures=$(( failures + 1 ))
fi

echo "▸ crase dentro da ajuda"
backticks=""
if [[ -f dev ]]; then
  backticks="$(sed -n '/^usage() {/,/^}/p' dev | grep -n '`' || true)"
fi
if [[ -z "$backticks" ]]; then
  echo "  ✔ nenhuma"
else
  printf '%s\n' "$backticks" | sed 's/^/  ✘ usage(): /'
  echo "  use aspas: a crase executa dentro do heredoc"
  failures=$(( failures + 1 ))
fi

echo "▸ bit de execução"
not_executable=0
for f in dev tools/check.sh tools/test.sh; do
  if [[ -f "$f" ]]; then
    if [[ -x "$f" ]]; then
      echo "  ✔ $f"
    else
      echo "  ✘ $f não é executável  —  chmod +x $f"
      not_executable=$(( not_executable + 1 ))
    fi
  fi
done
failures=$(( failures + not_executable ))

echo "▸ estado no repositório"
stray=""
for f in dev.conf dev.schedule dev.workers .env; do
  [[ -e "$f" ]] && stray+=" $f"
done
if [[ -z "$stray" ]]; then
  echo "  ✔ nenhum arquivo de projeto na raiz"
else
  echo "  ✘ arquivo de projeto na raiz do repositório:$stray"
  failures=$(( failures + 1 ))
fi

if [[ -f runtimes/manifest.sh ]]; then
  echo "▸ runtime do repositório"
  declared="$(bash -c '
    source runtimes/manifest.sh
    for component in php nginx; do
      eval "file=\${${component^^}_RUNTIME_FILE}"
      eval "sha=\${${component^^}_RUNTIME_SHA256}"
      [[ -n "$file" ]] && printf "%s\t%s\t%s\n" "$component" "$file" "$sha"
    done' 2>/dev/null || true)"
  if [[ -z "$declared" ]]; then
    echo "  ○ nenhum declarado ainda"
  else
    while IFS=$'\t' read -r component file sha; do
      [[ -n "$component" ]] || continue
      if [[ ! -f "runtimes/$file" ]]; then
        echo "  ✘ $component declara runtimes/$file, que não está no repositório"
        failures=$(( failures + 1 ))
      elif ! printf '%s  %s\n' "$sha" "runtimes/$file" | sha256sum -c --quiet - >/dev/null 2>&1; then
        echo "  ✘ runtimes/$file não confere com o sha256 do manifesto"
        failures=$(( failures + 1 ))
      else
        echo "  ✔ $component  $(du -h "runtimes/$file" | cut -f1 || true)"
      fi
    done <<<"$declared"
  fi
fi

if [[ -f tools/banned-identifiers.txt ]]; then
  echo "▸ identificadores proibidos"
  legacy_targets=("${files[@]}")
  for f in tests/*.bash tests/*.bats; do
    [[ -f "$f" ]] && legacy_targets+=("$f")
  done
  legacy="$(grep -nE -f tools/banned-identifiers.txt "${legacy_targets[@]}" 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  if [[ -z "$legacy" ]]; then
    echo "  ✔ nenhum"
  else
    printf '%s\n' "$legacy" | sed 's/^/  ✘ /'
    echo "  use o nome em inglês; a regra está no CLAUDE.md"
    failures=$(( failures + 1 ))
  fi
fi

echo "▸ shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  sc_failures=0
  for f in "${files[@]}"; do
    ( ulimit -v 1500000; timeout 60 shellcheck -S warning -e SC2034,SC2120 "$f" ) \
      || sc_failures=$(( sc_failures + 1 ))
  done
  if (( sc_failures == 0 )); then
    echo "  ✔ limpo"
  else
    echo "  ✘ $sc_failures arquivo(s) com aviso"
    failures=$(( failures + sc_failures ))
  fi
else
  missing "shellcheck não instalado (sudo apt install shellcheck)"
fi

echo "▸ testes"
if [[ -d tests && $(find tests -name "*.bats" 2>/dev/null | wc -l) -gt 0 ]]; then
  output="$(tools/test.sh 2>&1)"
  code=$?
  case "$code" in
    0) echo "  ✔ $(grep -c '^ok' <<<"$output" || true) testes" ;;
    2) missing "bats indisponível" ;;
    *) grep -v '^ok' <<<"$output" | sed 's/^/  /'
       failures=$(( failures + 1 )) ;;
  esac
else
  echo "  ○ nenhum teste criado ainda"
fi

echo
if (( failures == 0 )); then
  echo "✔ tudo certo"
else
  echo "✘ $failures problema(s)"
fi
exit $(( failures > 0 ? 1 : 0 ))
