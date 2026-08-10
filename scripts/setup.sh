#!/usr/bin/env bash
#
# setup.sh — monta o ambiente do Mercado Bom Preço.
#
# Produz o que o ./scripts/verify.sh confere. Não confere nada: quem julga se o
# ambiente está utilizável é o verify. Aqui só se prepara.
#
# Idempotente: rodar duas vezes seguidas não quebra e não desfaz nada.
# Em especial, um .env existente nunca é sobrescrito.
#
# Exit code:  0 = ambiente montado
#             1 = um passo falhou (a mensagem diz qual e o que fazer)
#
# Mesmas restrições do verify.sh: bash 3.2 do macOS, sem set -e — cada passo
# tem seu próprio tratamento de erro, com mensagem que serve para quem chega agora.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

TOTAL=5

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    VERM=$'\033[0;31m'; VERD=$'\033[0;32m'; CINZA=$'\033[0;90m'
    NEG=$'\033[1m'; ZERO=$'\033[0m'
else
    VERM=''; VERD=''; CINZA=''; NEG=''; ZERO=''
fi

passo()   { printf '\n%s[%d/%d] %s%s\n' "$NEG" "$1" "$TOTAL" "$2" "$ZERO"; }
feito()   { printf '      %s✓%s %s\n' "$VERD" "$ZERO" "$1"; }
mantido() { printf '      %s·%s %s\n' "$CINZA" "$ZERO" "$1"; }
nota()    { printf '        %s%s%s\n' "$CINZA" "$1" "$ZERO"; }

# Aborta com mensagem em bloco. Todo argumento vira uma linha.
abortar() {
    printf '\n%s✗ %s%s\n' "$VERM$NEG" "$1" "$ZERO"
    shift
    for linha in "$@"; do
        if [ -z "$linha" ]; then printf '\n'; else printf '  %s\n' "$linha"; fi
    done
    printf '\n'
    exit 1
}

# ─── 1/5 — uv ───────────────────────────────────────────────────────────────
# O instalador do uv escreve no perfil do shell, o que não afeta esta sessão.
# Por isso, depois de instalar, o PATH é recarregado aqui na marra; se ainda
# assim o uv não aparecer, o script para e manda reabrir o terminal — melhor do
# que seguir e falhar de um jeito confuso três passos adiante.

carregar_path_do_uv() {
    for arquivo_env in "$HOME/.local/bin/env" "$HOME/.cargo/env"; do
        if [ -f "$arquivo_env" ]; then
            set +u; . "$arquivo_env"; set -u
        fi
    done
    for diretorio in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        case ":$PATH:" in
            *":$diretorio:"*) ;;
            *) [ -d "$diretorio" ] && { PATH="$diretorio:$PATH"; export PATH; } ;;
        esac
    done
    hash -r 2>/dev/null
}

passo 1 "uv"
if command -v uv >/dev/null 2>&1; then
    mantido "uv já instalado ($(uv --version 2>/dev/null | head -n 1))"
else
    command -v curl >/dev/null 2>&1 || abortar \
        "curl não encontrado, e ele é necessário para instalar o uv." \
        "Instale o curl e rode ./scripts/setup.sh de novo."

    printf '      instalando o uv...\n'
    if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
        abortar "Falha ao instalar o uv." \
            "Confira sua conexão e tente de novo, ou instale à mão:" \
            "  https://docs.astral.sh/uv/getting-started/installation/"
    fi

    carregar_path_do_uv

    command -v uv >/dev/null 2>&1 || abortar \
        "O uv foi instalado, mas não está visível nesta sessão do terminal." \
        "O instalador alterou o PATH no seu perfil de shell, e essa mudança só" \
        "vale para sessões novas." \
        "" \
        "Faça uma das duas e rode ./scripts/setup.sh de novo:" \
        "  · reabra o terminal; ou" \
        "  · export PATH=\"\$HOME/.local/bin:\$PATH\""

    feito "uv instalado ($(uv --version 2>/dev/null | head -n 1))"
fi

# ─── 2/5 — Python do pin ────────────────────────────────────────────────────

passo 2 "Python"
[ -f .python-version ] || abortar \
    ".python-version não encontrado — o projeto não declara sua versão de Python." \
    "Restaure o arquivo:  git checkout -- .python-version"

PIN="$(tr -d '[:space:]' < .python-version)"
[ -n "$PIN" ] || abortar \
    ".python-version está vazio." \
    "Restaure o arquivo:  git checkout -- .python-version"

if uv python find "$PIN" >/dev/null 2>&1; then
    mantido "Python $PIN já disponível"
else
    printf '      instalando o Python %s...\n' "$PIN"
    uv python install "$PIN" || abortar \
        "Falha ao instalar o Python $PIN." \
        "Rode à mão para ver o erro completo:  uv python install $PIN"
    feito "Python $PIN instalado"
fi

# ─── 3/5 — dependências ─────────────────────────────────────────────────────
# uv sync é idempotente por natureza: converge o .venv para o pyproject.toml.

passo 3 "Dependências"
uv sync || abortar \
    "Falha ao sincronizar as dependências." \
    "Rode à mão para ver o erro completo:  uv sync"
feito "ambiente sincronizado com o pyproject.toml"

# ─── 4/5 — .env ─────────────────────────────────────────────────────────────
# Segredo preenchido à mão nunca é sobrescrito: um cp descuidado aqui apaga
# credencial que ninguém tem cópia.

passo 4 ".env"
if [ -f .env ]; then
    mantido ".env já existe — mantido intacto"
    nota "as chaves não são conferidas aqui; ./scripts/verify.sh faz isso"
elif [ ! -f .env.example ]; then
    abortar ".env.example não encontrado — não há de onde criar o .env." \
        "Restaure o arquivo:  git checkout -- .env.example"
else
    cp .env.example .env || abortar "Falha ao criar o .env a partir do .env.example."
    chmod 600 .env 2>/dev/null
    feito ".env criado a partir do .env.example"
    nota "preencha OPENAI_API_KEY antes de usar o agente — o setup não tem como adivinhá-la"
fi

# ─── 5/5 — carga ────────────────────────────────────────────────────────────
# A carga é determinística e recria o banco do zero, então rodá-la de novo é
# seguro: nada que o usuário tenha feito à mão mora em data/bom_preco.db.

passo 5 "Carga do banco"

if [ ! -d src/bom_preco ]; then
    abortar "O módulo bom_preco ainda não existe neste repositório." \
        "" \
        "O ambiente Python está montado — o que falta é o código. A carga" \
        "(src/bom_preco/carga.py) lê os dumps de data/raw/ e produz" \
        "data/bom_preco.db, e ainda não foi escrita." \
        "" \
        "Isso não é erro de instalação: é trabalho que ainda não foi feito." \
        "O contrato da carga está em openspec/carga.md." \
        "" \
        "Até ela existir, ./scripts/verify.sh reprova na checagem 17 e o" \
        "ambiente segue sem banco. Todo o resto acima já está pronto."
fi

SAIDA_CARGA="$(uv run python -m bom_preco.carga 2>&1)"
RC_CARGA=$?
[ -n "$SAIDA_CARGA" ] && printf '%s\n' "$SAIDA_CARGA"

if [ "$RC_CARGA" -ne 0 ]; then
    if printf '%s' "$SAIDA_CARGA" | grep -q "No module named"; then
        abortar "src/bom_preco/ existe, mas o Python não consegue importá-lo." \
            "" \
            "O diretório está lá e mesmo assim o import falha — o que aponta para" \
            "o pyproject.toml, que precisa declarar onde o pacote mora para o" \
            "uv sync instalá-lo no ambiente." \
            "" \
            "Não é problema de instalação do uv nem do Python: os dois passos" \
            "anteriores terminaram bem."
    fi
    abortar "A carga falhou." \
        "A saída dela está acima." \
        "Para repetir isoladamente:  uv run python -m bom_preco.carga"
fi
feito "banco gerado em data/bom_preco.db"

# ─── Fim ────────────────────────────────────────────────────────────────────

printf '\n%s✓ Ambiente montado.%s\n' "$VERD$NEG" "$ZERO"
printf '%sConfira com:  ./scripts/verify.sh%s\n\n' "$CINZA" "$ZERO"
