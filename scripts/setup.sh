#!/usr/bin/env bash
# =============================================================================
#  setup.sh — GUIA do proj-agent-mercado-bom-preco (controle de feedforward)
#
#  O QUE É
#    Este script leva uma máquina qualquer do zero até "consegue rodar o
#    proj-agent-mercado-bom-preco". Ele é o caminho oficial de entrada no
#    projeto: um desenvolvedor novo (ou um agente de codificação) não precisa
#    de nenhum conhecimento prévio além de "clone o repositório e rode
#    ./scripts/setup.sh".
#
#    O par dele é o scripts/verify.sh (o sensor), executado ao final para
#    provar que o resultado ficou correto. Guia sem sensor não sabe se
#    funcionou; sensor sem guia só repete a reclamação.
#
#  COMO USAR
#    ./scripts/setup.sh                 interativo (pede confirmação p/ instalar o uv)
#    ./scripts/setup.sh --yes           não interativo (CI, containers, agentes)
#    ./scripts/setup.sh --skip-verify   apenas prepara, sem rodar o sensor no fim
#
#  IDEMPOTENTE
#    Rodar de novo é seguro e barato: cada passo verifica antes de agir.
#    Nada é apagado sem pedido explícito.
#
#  DOCUMENTO VIVO
#    Quando o projeto ganhar uma nova dependência de ambiente (um serviço,
#    uma variável, um binário externo), o passo entra aqui — e a verificação
#    correspondente entra no verify.sh. Se um passo virar conhecimento oral
#    ("ah, você também precisa exportar X"), ele já está no lugar errado.
#
#  SEM DEPENDÊNCIAS
#    Só bash + coreutils + curl. Este script roda ANTES de o ambiente existir.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Contrato do ambiente — mantenha alinhado com scripts/verify.sh
# -----------------------------------------------------------------------------
PYTHON_VERSAO_ESPERADA="3.13"
UV_VERSAO_MINIMA="0.9.0"
UV_INSTALADOR="https://astral.sh/uv/install.sh"

# -----------------------------------------------------------------------------
# Infra
# -----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

ASSUME_YES=0
RODAR_VERIFY=1
for arg in "$@"; do
  case "$arg" in
    --yes|-y)      ASSUME_YES=1 ;;
    --skip-verify) RODAR_VERIFY=0 ;;
    --help|-h)
      sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "setup.sh: argumento desconhecido: $arg (use --help)" >&2
      exit 2
      ;;
  esac
done

# Ambientes automatizados nunca devem travar esperando um "sim".
[ -t 0 ] || ASSUME_YES=1
if [ -n "${CI:-}" ]; then ASSUME_YES=1; fi

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""
fi

PASSO_ATUAL=0
passo() {
  PASSO_ATUAL=$((PASSO_ATUAL + 1))
  printf '\n%s[%d/%d] %s%s\n' "$C_BOLD$C_BLUE" "$PASSO_ATUAL" "$TOTAL_PASSOS" "$1" "$C_RESET"
}
info()  { printf '      %s\n' "$1"; }
feito() { printf '      %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
aviso() { printf '      %s⚠%s  %s\n' "$C_YELLOW" "$C_RESET" "$1"; }
erro()  { printf '\n%s✘ %s%s\n' "$C_RED$C_BOLD" "$1" "$C_RESET"; }

# Aborta com uma mensagem que já contém a próxima ação — nunca só o sintoma.
abortar() {
  erro "$1"
  printf '  %scomo resolver:%s %s\n\n' "$C_YELLOW" "$C_RESET" "$2"
  exit 1
}

confirmar() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local resposta
  printf '      %s%s [s/N]%s ' "$C_YELLOW" "$1" "$C_RESET"
  read -r resposta
  case "$resposta" in [sSyY]*) return 0 ;; *) return 1 ;; esac
}

version_ge() {
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]
}

TOTAL_PASSOS=7

printf '%sConfigurando o ambiente do proj-agent-mercado-bom-preco%s\n' "$C_BOLD" "$C_RESET"
printf '%s%s%s\n' "$C_DIM" "$REPO_ROOT" "$C_RESET"

# -----------------------------------------------------------------------------
passo "Pré-requisitos do sistema"
# -----------------------------------------------------------------------------
# O script sempre opera na raiz do repositório (calculada a partir do próprio
# caminho dele), então rodar de qualquer pasta funciona. Mas se o pyproject.toml
# não estiver lá, não é o proj-agent-mercado-bom-preco — melhor parar do que
# configurar a pasta errada.
if [ ! -f pyproject.toml ]; then
  abortar "pyproject.toml não encontrado em ${REPO_ROOT}." \
          "rode o script de dentro do repositório clonado: cd /caminho/do/proj-agent-mercado-bom-preco && ./scripts/setup.sh"
fi
feito "raiz do projeto encontrada"

if ! command -v git >/dev/null 2>&1; then
  abortar "git não encontrado no PATH." \
          "instale pelo gerenciador de pacotes do sistema (ex.: sudo apt install git) e rode este script de novo"
fi
feito "git $(git --version | awk '{print $3}')"

if ! command -v curl >/dev/null 2>&1; then
  aviso "curl não encontrado — a instalação automática do uv não estará disponível"
fi

# -----------------------------------------------------------------------------
passo "Gerenciador de pacotes (uv)"
# -----------------------------------------------------------------------------
instalar_uv() {
  command -v curl >/dev/null 2>&1 || abortar \
    "curl não está disponível para baixar o instalador do uv." \
    "instale o curl, ou instale o uv por outro caminho: https://docs.astral.sh/uv/getting-started/installation/"

  info "baixando e executando ${UV_INSTALADOR}"
  curl -LsSf "$UV_INSTALADOR" | sh

  # O instalador coloca o binário em ~/.local/bin, que pode não estar no PATH
  # da sessão atual — para este script, resolvemos na hora.
  for candidato in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    if [ -x "$candidato/uv" ]; then
      export PATH="$candidato:$PATH"
      aviso "uv instalado em ${candidato} — se 'uv' não for encontrado em um novo terminal, adicione essa pasta ao seu PATH"
      break
    fi
  done
}

if command -v uv >/dev/null 2>&1; then
  UV_VERSAO="$(uv --version | awk '{print $2}')"
  if version_ge "$UV_VERSAO" "$UV_VERSAO_MINIMA"; then
    feito "uv ${UV_VERSAO} (mínimo ${UV_VERSAO_MINIMA})"
  else
    info "uv ${UV_VERSAO} é anterior ao mínimo exigido (${UV_VERSAO_MINIMA})"
    if confirmar "Atualizar o uv agora?"; then
      uv self update || instalar_uv
      feito "uv atualizado para $(uv --version | awk '{print $2}')"
    else
      abortar "uv ${UV_VERSAO} é antigo demais para este projeto." \
              "uv self update"
    fi
  fi
else
  info "uv não encontrado — é ele que gerencia Python, venv e dependências aqui"
  if confirmar "Instalar o uv a partir de ${UV_INSTALADOR}?"; then
    instalar_uv
  else
    abortar "uv é obrigatório para configurar o projeto." \
            "instale manualmente e rode de novo: curl -LsSf ${UV_INSTALADOR} | sh"
  fi
  command -v uv >/dev/null 2>&1 || abortar \
    "uv foi instalado mas não está no PATH desta sessão." \
    "abra um novo terminal (ou execute: export PATH=\"\$HOME/.local/bin:\$PATH\") e rode ./scripts/setup.sh de novo"
  feito "uv $(uv --version | awk '{print $2}')"
fi

# -----------------------------------------------------------------------------
passo "Python ${PYTHON_VERSAO_ESPERADA}"
# -----------------------------------------------------------------------------
if [ ! -f .python-version ] || [ "$(tr -d '[:space:]' < .python-version)" != "$PYTHON_VERSAO_ESPERADA" ]; then
  info "fixando a versão do projeto em ${PYTHON_VERSAO_ESPERADA}"
  uv python pin "$PYTHON_VERSAO_ESPERADA" >/dev/null
fi
feito ".python-version fixado em ${PYTHON_VERSAO_ESPERADA}"

if uv python find "$PYTHON_VERSAO_ESPERADA" >/dev/null 2>&1; then
  feito "interpretador Python ${PYTHON_VERSAO_ESPERADA} disponível"
else
  info "Python ${PYTHON_VERSAO_ESPERADA} não encontrado — baixando via uv (não interfere no Python do sistema)"
  uv python install "$PYTHON_VERSAO_ESPERADA"
  feito "Python ${PYTHON_VERSAO_ESPERADA} instalado"
fi

# -----------------------------------------------------------------------------
passo "Ambiente virtual e dependências"
# -----------------------------------------------------------------------------
# Se o .venv existente aponta para outra versão de Python, recriar é mais barato
# e mais confiável do que remendar.
VENV_PY=".venv/bin/python"
[ -x "$VENV_PY" ] || VENV_PY=".venv/Scripts/python.exe"
if [ -x "$VENV_PY" ]; then
  VENV_VERSAO="$("$VENV_PY" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo "desconhecida")"
  if [ "$VENV_VERSAO" != "$PYTHON_VERSAO_ESPERADA" ]; then
    aviso ".venv atual usa Python ${VENV_VERSAO}, esperado ${PYTHON_VERSAO_ESPERADA}"
    if confirmar "Apagar o .venv e recriar?"; then
      rm -rf .venv
      feito ".venv antigo removido"
    else
      abortar ".venv está com a versão errada de Python." \
              "rm -rf .venv && ./scripts/setup.sh"
    fi
  fi
fi

info "sincronizando dependências a partir do uv.lock"
uv sync
feito "$(uv run python -c 'import sys; print("Python", sys.version.split()[0])') em .venv"

# -----------------------------------------------------------------------------
passo "Configuração local (.env)"
# -----------------------------------------------------------------------------
# Regra inegociável: o .env é pessoal e pode conter segredos. Este script pode
# CRIAR um .env que não existe, mas nunca sobrescreve, mescla ou apaga um
# existente — perder a configuração local de alguém é um estrago irreversível.
if [ -f .env ]; then
  feito ".env já existe — preservado como está (este script nunca sobrescreve)"
  if [ -f .env.example ]; then
    # Não altera nada: só conta ao desenvolvedor se o modelo ganhou chaves novas.
    # '|| true': grep sem correspondência sai com 1 e o 'set -e' mataria o script.
    CHAVES_MODELO="$(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' .env.example 2>/dev/null | tr -d ' =' | sort -u || true)"
    CHAVES_LOCAIS="$(grep -oE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' .env         2>/dev/null | tr -d ' =' | sort -u || true)"
    FALTANDO="$(comm -23 <(printf '%s\n' "$CHAVES_MODELO") <(printf '%s\n' "$CHAVES_LOCAIS") | tr '\n' ' ')"
    if [ -n "${FALTANDO// /}" ]; then
      aviso "o .env.example tem chaves que seu .env não tem: ${FALTANDO}"
      aviso "adicione-as manualmente ao seu .env (não mexemos no arquivo por você)"
    fi
  fi
elif [ -f .env.example ]; then
  cp .env.example .env
  feito ".env criado a partir do .env.example"
  info "revise os valores em ${REPO_ROOT}/.env antes de usar"
else
  aviso ".env.example não encontrado — nenhum .env foi criado"
fi

# -----------------------------------------------------------------------------
passo "Docker (opcional até a semana 6)"
# -----------------------------------------------------------------------------
# Verificar sim, instalar não: Docker é uma dependência do sistema, com
# implicações de permissão e daemon que não cabem a um script de projeto
# resolver na máquina de outra pessoa.
if command -v docker >/dev/null 2>&1; then
  feito "docker $(docker --version 2>/dev/null | awk '{gsub(/,/,"",$3); print $3}')"
  if docker info >/dev/null 2>&1; then
    feito "daemon do docker respondendo"
  else
    aviso "docker instalado, mas o daemon não responde — inicie o Docker Desktop ou 'sudo systemctl start docker'"
  fi
else
  aviso "docker não encontrado — sem problema agora, será necessário na semana 6"
  info "quando precisar: https://docs.docker.com/get-docker/"
fi

# -----------------------------------------------------------------------------
passo "Dados brutos"
# -----------------------------------------------------------------------------
# Os dados não são baixados automaticamente. Se um dia forem, o download entra
# aqui — e o verify.sh continua sendo quem confere que chegaram inteiros.
DADOS_FALTANDO=0
for arquivo in data/raw/produtos.csv.gz data/raw/vendas.csv.gz; do
  if [ -f "$arquivo" ]; then
    feito "${arquivo} ($(du -h "$arquivo" | cut -f1))"
  else
    aviso "${arquivo} não encontrado"
    DADOS_FALTANDO=1
  fi
done
if [ "$DADOS_FALTANDO" -eq 1 ]; then
  aviso "os dados brutos não vêm do repositório — peça os arquivos a alguém do time e coloque em data/raw/"
fi

# -----------------------------------------------------------------------------
# Fecha o ciclo: o guia termina acionando o sensor.
# -----------------------------------------------------------------------------
if [ "$RODAR_VERIFY" -eq 1 ] && [ -x scripts/verify.sh ]; then
  printf '\n%s─── conferindo o resultado com scripts/verify.sh ───%s\n' "$C_DIM" "$C_RESET"
  exec scripts/verify.sh
fi

printf '\n%sSetup concluído.%s Confira o ambiente com: ./scripts/verify.sh\n' "$C_GREEN$C_BOLD" "$C_RESET"
