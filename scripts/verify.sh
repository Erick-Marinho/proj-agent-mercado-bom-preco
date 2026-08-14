#!/usr/bin/env bash
# =============================================================================
#  verify.sh — SENSOR do proj-agent-mercado-bom-preco (controle de feedback)
#
#  O QUE É
#    Este script observa o estado real do ambiente e responde a uma única
#    pergunta: "esta máquina consegue rodar o proj-agent-mercado-bom-preco
#    agora?"
#
#    Ele NÃO conserta nada — quem conserta é o scripts/setup.sh (o guia).
#    Cada falha aqui carrega o motivo observado e o comando exato de correção,
#    para que tanto um humano recém-chegado quanto um agente de codificação
#    consigam se autocorrigir sem precisar de contexto externo (Slack, wiki,
#    a memória de alguém).
#
#  COMO USAR
#    ./scripts/verify.sh              relatório completo
#    ./scripts/verify.sh --quiet      apenas falhas e avisos (CI, hooks, agentes)
#
#  CÓDIGOS DE SAÍDA
#    0  ambiente apto (avisos podem existir)
#    1  ao menos uma verificação falhou
#
#  DOCUMENTO VIVO
#    Toda vez que alguém quebrar o ambiente de um jeito que este script não
#    detectou, adicione a verificação aqui — e a correção correspondente no
#    setup.sh. Sensor sem guia repete o mesmo erro; guia sem sensor nunca
#    descobre se funcionou.
#
#  CONVENÇÃO PARA NOVAS VERIFICAÇÕES
#    ok    "<o que está correto>"
#    fail  "<o que falhou>"       "<motivo observado>"  "<como corrigir>"
#    warn  "<o que chamou atenção>" "<motivo observado>"  "<sugestão>"
#    skip  "<verificação>"        "<por que não deu para avaliar>"
#
#    Regra de ouro: a mensagem de correção deve ser copiável e executável.
#    "configure o ambiente" é ruim; "./scripts/setup.sh" é bom.
#
#  SEM DEPENDÊNCIAS
#    Só bash + coreutils. Este script precisa rodar ANTES de o ambiente existir.
# =============================================================================

# Atenção: a ausência do '-e' aqui é proposital e estrutural.
# Um sensor precisa rodar TODAS as verificações e entregar o quadro completo;
# com 'set -e' o script morreria na primeira falha e o desenvolvedor
# descobriria os problemas um a um, em rodadas sucessivas. Falha de comando
# aqui é dado, não acidente.
set -uo pipefail

# -----------------------------------------------------------------------------
# Contrato do ambiente — a fonte da verdade que este sensor faz cumprir.
# Ao mudar qualquer valor aqui, atualize também .python-version / pyproject.toml
# e o scripts/setup.sh. A divergência entre eles é justamente o que o sensor pega.
# -----------------------------------------------------------------------------
PYTHON_VERSAO_ESPERADA="3.13"
UV_VERSAO_MINIMA="0.9.0"
ARQUIVOS_DADOS=(
  "data/raw/produtos.csv.gz"
  "data/raw/vendas.csv.gz"
)

# -----------------------------------------------------------------------------
# Infra do relatório
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

QUIET=0
for arg in "$@"; do
  case "$arg" in
    --quiet|-q) QUIET=1 ;;
    --help|-h)
      sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "verify.sh: argumento desconhecido: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""
fi

N_OK=0; N_FAIL=0; N_WARN=0; N_SKIP=0

section() {
  [ "$QUIET" -eq 1 ] && return 0
  printf '\n%s▸ %s%s\n' "$C_BOLD$C_BLUE" "$1" "$C_RESET"
}

ok() {
  N_OK=$((N_OK + 1))
  [ "$QUIET" -eq 1 ] && return 0
  printf '  %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"
}

fail() {
  N_FAIL=$((N_FAIL + 1))
  printf '  %s✘ %s%s\n' "$C_RED" "$1" "$C_RESET"
  printf '      %smotivo:%s   %s\n' "$C_DIM" "$C_RESET" "$2"
  printf '      %scorrigir:%s %s\n' "$C_YELLOW" "$C_RESET" "$3"
}

warn() {
  N_WARN=$((N_WARN + 1))
  printf '  %s⚠ %s%s\n' "$C_YELLOW" "$1" "$C_RESET"
  printf '      %smotivo:%s   %s\n' "$C_DIM" "$C_RESET" "$2"
  printf '      %ssugestão:%s %s\n' "$C_DIM" "$C_RESET" "$3"
}

skip() {
  N_SKIP=$((N_SKIP + 1))
  printf '  %s— %s (não avaliado: %s)%s\n' "$C_DIM" "$1" "$2" "$C_RESET"
}

# version_ge A B  →  verdadeiro se A >= B (comparação semântica, não lexical)
version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

[ "$QUIET" -eq 1 ] || printf '%sVerificando ambiente do proj-agent-mercado-bom-preco%s %s(%s)%s\n' \
  "$C_BOLD" "$C_RESET" "$C_DIM" "$REPO_ROOT" "$C_RESET"

# -----------------------------------------------------------------------------
section "Ferramentas base"
# -----------------------------------------------------------------------------
TEM_UV=0

if command -v git >/dev/null 2>&1; then
  ok "git instalado ($(git --version | awk '{print $3}'))"
else
  fail "git não encontrado" \
       "'git' não está no PATH" \
       "instale o git pelo gerenciador de pacotes do seu sistema (ex.: sudo apt install git)"
fi

if command -v uv >/dev/null 2>&1; then
  UV_VERSAO="$(uv --version 2>/dev/null | awk '{print $2}')"
  if version_ge "${UV_VERSAO:-0}" "$UV_VERSAO_MINIMA"; then
    TEM_UV=1
    ok "uv instalado (${UV_VERSAO}, mínimo ${UV_VERSAO_MINIMA})"
  else
    fail "uv desatualizado" \
         "versão instalada ${UV_VERSAO}, o projeto exige >= ${UV_VERSAO_MINIMA}" \
         "uv self update    (ou reinstale: curl -LsSf https://astral.sh/uv/install.sh | sh)"
  fi
else
  fail "uv não encontrado" \
       "'uv' não está no PATH — o projeto usa uv para Python, venv e dependências" \
       "./scripts/setup.sh    (ou instale manualmente: curl -LsSf https://astral.sh/uv/install.sh | sh)"
fi

# -----------------------------------------------------------------------------
section "Versão do Python"
# -----------------------------------------------------------------------------
if [ -f .python-version ]; then
  PIN_ATUAL="$(tr -d '[:space:]' < .python-version)"
  if [ "$PIN_ATUAL" = "$PYTHON_VERSAO_ESPERADA" ]; then
    ok ".python-version fixado em ${PYTHON_VERSAO_ESPERADA}"
  else
    fail ".python-version divergente" \
         "o arquivo pede '${PIN_ATUAL}', mas o contrato do projeto é '${PYTHON_VERSAO_ESPERADA}'" \
         "uv python pin ${PYTHON_VERSAO_ESPERADA}    (se a mudança for intencional, atualize PYTHON_VERSAO_ESPERADA em scripts/verify.sh)"
  fi
else
  fail ".python-version ausente" \
       "sem esse arquivo cada desenvolvedor resolve uma versão diferente de Python" \
       "uv python pin ${PYTHON_VERSAO_ESPERADA}"
fi

if [ -f pyproject.toml ]; then
  REQUIRES_PYTHON="$(grep -E '^[[:space:]]*requires-python[[:space:]]*=' pyproject.toml | head -1 | sed -E 's/.*=[[:space:]]*"([^"]*)".*/\1/')"
  if [ -z "$REQUIRES_PYTHON" ]; then
    fail "pyproject.toml sem requires-python" \
         "nada impede alguém de instalar o projeto em um Python incompatível" \
         "adicione  requires-python = \">=${PYTHON_VERSAO_ESPERADA}\"  na seção [project] do pyproject.toml"
  elif printf '%s' "$REQUIRES_PYTHON" | grep -q "$PYTHON_VERSAO_ESPERADA"; then
    ok "pyproject.toml exige Python '${REQUIRES_PYTHON}'"
  else
    fail "requires-python inconsistente" \
         "pyproject.toml exige '${REQUIRES_PYTHON}', mas o projeto roda em ${PYTHON_VERSAO_ESPERADA}" \
         "ajuste requires-python para \">=${PYTHON_VERSAO_ESPERADA}\" no pyproject.toml"
  fi
else
  fail "pyproject.toml ausente" \
       "é a raiz da definição do projeto e das dependências" \
       "você está no repositório certo? confira 'git status' na raiz do proj-agent-mercado-bom-preco"
fi

if [ "$TEM_UV" -eq 1 ]; then
  if uv python find "$PYTHON_VERSAO_ESPERADA" >/dev/null 2>&1; then
    ok "interpretador Python ${PYTHON_VERSAO_ESPERADA} disponível para o uv"
  else
    fail "Python ${PYTHON_VERSAO_ESPERADA} não disponível" \
         "'uv python find ${PYTHON_VERSAO_ESPERADA}' não localizou nenhum interpretador compatível" \
         "uv python install ${PYTHON_VERSAO_ESPERADA}"
  fi
else
  skip "disponibilidade do Python ${PYTHON_VERSAO_ESPERADA}" "uv indisponível"
fi

# -----------------------------------------------------------------------------
section "Ambiente virtual"
# -----------------------------------------------------------------------------
VENV_PY=".venv/bin/python"
[ -x "$VENV_PY" ] || VENV_PY=".venv/Scripts/python.exe"   # Windows / Git Bash

if [ -x "$VENV_PY" ]; then
  ok ".venv existe"
  VENV_VERSAO="$("$VENV_PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
  if [ "$VENV_VERSAO" = "$PYTHON_VERSAO_ESPERADA" ]; then
    ok ".venv usa Python ${VENV_VERSAO}"
  else
    fail ".venv com Python errado" \
         "o ambiente virtual roda Python '${VENV_VERSAO:-desconhecido}', esperado '${PYTHON_VERSAO_ESPERADA}'" \
         "rm -rf .venv && ./scripts/setup.sh    (recriar é mais barato que remendar)"
  fi
else
  fail ".venv ausente" \
       "não há ambiente virtual em ${REPO_ROOT}/.venv" \
       "./scripts/setup.sh"
fi

# -----------------------------------------------------------------------------
section "Dependências"
# -----------------------------------------------------------------------------
if [ ! -f uv.lock ]; then
  fail "uv.lock ausente" \
       "sem lockfile as instalações deixam de ser reprodutíveis entre máquinas" \
       "uv lock && git add uv.lock"
elif [ "$TEM_UV" -eq 1 ]; then
  ok "uv.lock presente"
  if uv lock --check >/dev/null 2>&1; then
    ok "uv.lock em sincronia com o pyproject.toml"
  else
    fail "uv.lock desatualizado" \
         "o pyproject.toml mudou depois do último 'uv lock'" \
         "uv lock && git add uv.lock"
  fi
  if uv sync --frozen --check >/dev/null 2>&1; then
    ok ".venv em sincronia com o uv.lock"
  else
    fail ".venv fora de sincronia com o lockfile" \
         "há pacotes faltando, sobrando ou em versão diferente da travada no uv.lock" \
         "uv sync --frozen"
  fi
else
  skip "sincronia do lockfile e do .venv" "uv indisponível"
fi

# -----------------------------------------------------------------------------
section "Configuração local (.env)"
# -----------------------------------------------------------------------------
if [ ! -f .env.example ]; then
  fail ".env.example ausente" \
       "sem o modelo versionado ninguém descobre quais variáveis o projeto espera" \
       "recupere o arquivo do repositório: git checkout .env.example"
elif [ ! -f .env ]; then
  fail ".env ausente" \
       "o projeto lê a configuração local do .env, que é pessoal e não vem no clone" \
       "cp .env.example .env    (ou simplesmente ./scripts/setup.sh)"
else
  ok ".env presente"

  # Um .env versionado é vazamento de segredo — trate como falha, não como estilo.
  if git rev-parse --git-dir >/dev/null 2>&1; then
    if git ls-files --error-unmatch .env >/dev/null 2>&1; then
      fail ".env está versionado no git" \
           "o arquivo é rastreado pelo git e pode expor segredos a quem clonar o repositório" \
           "git rm --cached .env && echo '.env' >> .gitignore    (e troque qualquer segredo que já tenha sido commitado)"
    elif git check-ignore -q .env 2>/dev/null; then
      ok ".env ignorado pelo git"
    else
      fail ".env não está no .gitignore" \
           "o arquivo pode ser commitado sem querer, junto com os segredos que tiver dentro" \
           "adicione a linha '.env' ao .gitignore"
    fi
  fi

  # Deriva de configuração: o modelo ganhou chaves que o .env local não tem.
  CHAVES_MODELO="$(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' .env.example 2>/dev/null | tr -d ' =' | sort -u)"
  CHAVES_LOCAIS="$(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' .env         2>/dev/null | tr -d ' =' | sort -u)"
  CHAVES_FALTANDO="$(comm -23 <(printf '%s\n' "$CHAVES_MODELO") <(printf '%s\n' "$CHAVES_LOCAIS") | tr '\n' ' ')"
  if [ -z "${CHAVES_FALTANDO// /}" ]; then
    ok ".env tem todas as chaves do .env.example"
  else
    fail ".env desatualizado em relação ao modelo" \
         "faltam chaves que o .env.example define: ${CHAVES_FALTANDO}" \
         "copie as linhas que faltam do .env.example para o seu .env e preencha os valores"
  fi
fi

# -----------------------------------------------------------------------------
section "Docker"
# -----------------------------------------------------------------------------
# Avisa, não reprova: os serviços em container só entram na semana 6, então a
# ausência do Docker hoje não impede ninguém de trabalhar.
if command -v docker >/dev/null 2>&1; then
  ok "docker instalado ($(docker --version 2>/dev/null | awk '{gsub(/,/,"",$3); print $3}'))"
  if docker info >/dev/null 2>&1; then
    ok "daemon do docker respondendo"
  else
    warn "daemon do docker não responde" \
         "o binário existe, mas 'docker info' falhou — daemon parado ou usuário sem permissão" \
         "inicie o serviço (sudo systemctl start docker) — só será realmente necessário na semana 6"
  fi
else
  warn "docker não instalado" \
       "ainda não é um bloqueio: os serviços em container entram só na semana 6" \
       "instale antes da semana 6: https://docs.docker.com/get-docker/"
fi

# -----------------------------------------------------------------------------
section "Dados brutos"
# -----------------------------------------------------------------------------
for arquivo in "${ARQUIVOS_DADOS[@]}"; do
  if [ ! -f "$arquivo" ]; then
    fail "dado ausente: ${arquivo}" \
         "arquivo não encontrado — os dados brutos não vêm de um download automático" \
         "peça o arquivo a alguém do time e coloque em ${REPO_ROOT}/${arquivo}"
  elif gzip -t "$arquivo" >/dev/null 2>&1; then
    ok "${arquivo} presente e íntegro ($(du -h "$arquivo" | cut -f1))"
  else
    fail "dado corrompido: ${arquivo}" \
         "'gzip -t' não conseguiu validar o arquivo — download incompleto ou truncado" \
         "apague o arquivo e obtenha uma cópia nova: rm ${arquivo}"
  fi
done

# -----------------------------------------------------------------------------
section "Repositório"
# -----------------------------------------------------------------------------
if git rev-parse --git-dir >/dev/null 2>&1; then
  ok "diretório é um repositório git"

  if git check-ignore -q .venv 2>/dev/null; then
    ok ".venv está no .gitignore"
  else
    fail ".venv não está ignorado pelo git" \
         "o ambiente virtual é local de cada máquina e não deve ser versionado" \
         "adicione a linha '.venv' ao .gitignore"
  fi

  for arquivo in "${ARQUIVOS_DADOS[@]}"; do
    [ -f "$arquivo" ] || continue
    if ! git check-ignore -q "$arquivo" 2>/dev/null && ! git ls-files --error-unmatch "$arquivo" >/dev/null 2>&1; then
      warn "dado bruto não ignorado: ${arquivo}" \
           "o arquivo aparece como não rastreado e pode entrar em um commit sem querer ($(du -h "$arquivo" | cut -f1))" \
           "decida o destino dos dados brutos: ignorar em .gitignore, versionar via Git LFS, ou buscar de uma fonte externa no setup.sh"
    fi
  done
else
  fail "não é um repositório git" \
       "'git rev-parse' falhou em ${REPO_ROOT}" \
       "git init    (ou clone o projeto novamente)"
fi

# -----------------------------------------------------------------------------
# Resumo
# -----------------------------------------------------------------------------
printf '\n%s─────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
printf '%s%d ok%s' "$C_GREEN" "$N_OK" "$C_RESET"
[ "$N_WARN" -gt 0 ] && printf '  %s%d aviso(s)%s' "$C_YELLOW" "$N_WARN" "$C_RESET"
[ "$N_SKIP" -gt 0 ] && printf '  %s%d não avaliado(s)%s' "$C_DIM" "$N_SKIP" "$C_RESET"
[ "$N_FAIL" -gt 0 ] && printf '  %s%d falha(s)%s' "$C_RED" "$N_FAIL" "$C_RESET"
printf '\n'

if [ "$N_FAIL" -gt 0 ]; then
  printf '\n%sAmbiente NÃO está apto.%s Corrija os itens acima — a maioria é resolvida por:\n' "$C_RED$C_BOLD" "$C_RESET"
  printf '  ./scripts/setup.sh\n'
  exit 1
fi

printf '\n%sAmbiente apto.%s Para executar: uv run python <arquivo>\n' "$C_GREEN$C_BOLD" "$C_RESET"
exit 0
