#!/usr/bin/env bash
#
# verify.sh — confere que o ambiente do Mercado Bom Preço está utilizável.
#
# Implementa openspec/verify-sh.md. Só diagnostica: não instala, não sincroniza,
# não cria o .env e não gera o banco. Toda mutação é do setup.sh.
#
# Exit code:  0 = ambiente utilizável (avisos permitidos)
#             1 = uma falha ou mais
#
# Escrito para o bash 3.2 do macOS: sem arrays associativos, sem ${var,,},
# sem mapfile. Sem `set -e`, que abortaria na primeira falha e mataria o resumo.

set -uo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$RAIZ" || exit 1

BANCO="data/bom_preco.db"
DUMPS="produtos.csv.gz vendas.csv.gz"
FIX_CARGA="rm -f $BANCO && uv run python -m bom_preco.carga"

# ─── Relatório ──────────────────────────────────────────────────────────────
# O número é identidade da checagem, não posição na fila: a 17 sai junto das
# outras de dados, então a numeração aparece fora de ordem de propósito.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    VERM=$'\033[0;31m'; VERD=$'\033[0;32m'; AMAR=$'\033[0;33m'
    CINZA=$'\033[0;90m'; NEG=$'\033[1m'; ZERO=$'\033[0m'
else
    VERM=''; VERD=''; AMAR=''; CINZA=''; NEG=''; ZERO=''
fi

FALHAS_MSG=(); FALHAS_FIX=(); N_FALHAS=0; N_AVISOS=0

secao()  { printf '\n%s%s%s\n' "$NEG" "$1" "$ZERO"; }
ok()     { printf '  %2s  %s✓%s %s\n' "$1" "$VERD" "$ZERO" "$2"; }
pulou()  { printf '  %2s  %s—  %s%s\n' "$1" "$CINZA" "$2" "$ZERO"; }
avisou() { printf '  %2s  %s⚠%s %s\n' "$1" "$AMAR" "$ZERO" "$2"
           N_AVISOS=$((N_AVISOS + 1)); }
falhou() { printf '  %2s  %s✗%s %s\n' "$1" "$VERM" "$ZERO" "$2"
           FALHAS_MSG[$N_FALHAS]="$2"; FALHAS_FIX[$N_FALHAS]="$3"
           N_FALHAS=$((N_FALHAS + 1)); }

# Lê uma chave do .env sem executar o arquivo: é dado, não script.
# Nenhum valor lido daqui é impresso em lugar nenhum.
valor_env() {
    [ -f .env ] || return 0
    sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" .env 2>/dev/null \
        | tail -n 1 \
        | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'$/\1/" -e 's/[[:space:]]*$//'
}

# ─── Ambiente Python ────────────────────────────────────────────────────────

secao "Ambiente Python"

TEM_UV=0; TEM_PY=0; TEM_SYNC=0; PIN=""
[ -f .python-version ] && PIN="$(tr -d '[:space:]' < .python-version)"

# 1 — uv no PATH
if command -v uv >/dev/null 2>&1; then
    ok 1 "uv instalado ($(uv --version 2>/dev/null | head -n 1))"
    TEM_UV=1
else
    falhou 1 "uv não encontrado no PATH" \
              'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi

# 2 — versão do pin disponível ao uv
if [ -z "$PIN" ]; then
    falhou 2 ".python-version ausente ou vazio — o projeto não declara sua versão" \
              'git checkout -- .python-version'
elif [ "$TEM_UV" -eq 0 ]; then
    pulou 2 "Python $PIN disponível ao uv (depende de: uv instalado)"
elif uv python find "$PIN" >/dev/null 2>&1; then
    ok 2 "Python $PIN disponível ao uv"
    TEM_PY=1
else
    falhou 2 "Python $PIN indisponível ao uv" "uv python install $PIN"
fi

# 3 — ambiente sincronizado com o pyproject.toml (sem mutar nada)
#
# O teste do .venv vem antes de propósito: `uv sync --check` devolve 0 mesmo
# quando não existe ambiente virtual nenhum, e sozinho aprovaria o vazio.
# Ele também protege o plano B abaixo, que criaria o .venv se rodasse no vazio.
if [ "$TEM_UV" -eq 0 ] || [ "$TEM_PY" -eq 0 ]; then
    pulou 3 "ambiente sincronizado com o pyproject.toml (depende de: uv e Python $PIN)"
elif [ ! -x .venv/bin/python ]; then
    falhou 3 "ambiente virtual ausente — .venv/ não existe" 'uv sync'
else
    if uv sync --help 2>&1 | grep -q -- '--check'; then
        uv sync --check >/dev/null 2>&1
    else
        uv run --no-sync python -c 'pass' >/dev/null 2>&1
    fi
    if [ $? -eq 0 ]; then
        ok 3 "ambiente sincronizado com o pyproject.toml"
        TEM_SYNC=1
    else
        falhou 3 "ambiente dessincronizado do pyproject.toml" 'uv sync'
    fi
fi

# 4 — interpretador do projeto é o do pin
if [ "$TEM_SYNC" -eq 0 ]; then
    pulou 4 "interpretador do projeto na versão $PIN (depende de: ambiente sincronizado)"
else
    # Direto no interpretador do .venv: `uv run`, mesmo com --no-sync, cria o
    # ambiente virtual quando ele falta, e o verify não pode criar nada.
    VER="$(.venv/bin/python -c \
        'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)"
    case "$PIN" in
        "$VER"|"$VER".*) ok 4 "interpretador do projeto na versão $VER" ;;
        *) falhou 4 "interpretador do projeto é ${VER:-desconhecido}, e o pin é $PIN" \
                     'rm -rf .venv && uv sync' ;;
    esac
fi

# ─── Credenciais ────────────────────────────────────────────────────────────

secao "Credenciais"

TEM_ENV=0; TEM_CHAVE=0; TEM_LANGFUSE=0

# 5 — .env existe
if [ -f .env ]; then
    ok 5 ".env presente"
    TEM_ENV=1
else
    falhou 5 ".env ausente" 'cp .env.example .env   (e preencher)'
fi

# 6 — toda chave do .env.example existe no .env
if [ ! -f .env.example ]; then
    falhou 6 ".env.example ausente — não há com o que comparar o .env" \
              'git checkout -- .env.example'
elif [ "$TEM_ENV" -eq 0 ]; then
    pulou 6 "toda chave do .env.example presente no .env (depende de: .env presente)"
else
    FALTANDO=""
    for CHAVE in $(grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]*[[:space:]]*=' .env.example \
                   | tr -d ' ='); do
        grep -qE "^[[:space:]]*$CHAVE[[:space:]]*=" .env || FALTANDO="$FALTANDO $CHAVE"
    done
    if [ -z "$FALTANDO" ]; then
        ok 6 "toda chave do .env.example presente no .env"
    else
        falhou 6 "chave(s) do .env.example ausente(s) no .env:$FALTANDO" \
                  "acrescentar ao .env, uma por linha:$FALTANDO"
    fi
fi

# Variável exportada tem precedência sobre o .env — permite testar o script
# com uma credencial deliberadamente inválida sem tocar no arquivo.
CHAVE_OPENAI="${OPENAI_API_KEY:-$(valor_env OPENAI_API_KEY)}"
LF_PUB="${LANGFUSE_PUBLIC_KEY:-$(valor_env LANGFUSE_PUBLIC_KEY)}"
LF_SEC="${LANGFUSE_SECRET_KEY:-$(valor_env LANGFUSE_SECRET_KEY)}"
LF_HOST="${LANGFUSE_HOST:-$(valor_env LANGFUSE_HOST)}"

# 7 — OPENAI_API_KEY preenchida
if [ "$TEM_ENV" -eq 0 ]; then
    pulou 7 "OPENAI_API_KEY preenchida (depende de: .env presente)"
elif [ -n "$CHAVE_OPENAI" ]; then
    ok 7 "OPENAI_API_KEY preenchida"
    TEM_CHAVE=1
else
    falhou 7 "OPENAI_API_KEY vazia" 'preencher OPENAI_API_KEY no .env'
fi

# 8 — chaves do Langfuse preenchidas (aviso até a semana 6)
if [ "$TEM_ENV" -eq 0 ]; then
    pulou 8 "chaves do Langfuse preenchidas (depende de: .env presente)"
elif [ -n "$LF_PUB" ] && [ -n "$LF_SEC" ] && [ -n "$LF_HOST" ]; then
    ok 8 "chaves do Langfuse preenchidas"
    TEM_LANGFUSE=1
else
    avisou 8 "chaves do Langfuse vazias — necessárias a partir da semana 6"
fi

# 9 — a credencial responde a uma chamada real.
# Verificar que a variável existe não vale: chave revogada é indistinguível de
# chave válida até alguém tentar usá-la.
if [ "$TEM_CHAVE" -eq 0 ]; then
    pulou 9 "credencial OpenAI responde (depende de: OPENAI_API_KEY preenchida)"
elif ! command -v curl >/dev/null 2>&1; then
    falhou 9 "curl ausente — a credencial não pôde ser testada" 'instalar o curl'
else
    CODIGO="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -H "Authorization: Bearer $CHAVE_OPENAI" \
        https://api.openai.com/v1/models 2>/dev/null)"
    case "$CODIGO" in
        200) ok 9 "credencial OpenAI responde (HTTP 200)" ;;
        401) falhou 9 "OPENAI_API_KEY inválida ou revogada (HTTP 401)" \
                       'gerar nova chave e substituir no .env' ;;
        403) falhou 9 "OPENAI_API_KEY sem permissão para o recurso (HTTP 403)" \
                       'conferir as permissões da chave no painel da OpenAI' ;;
        429) falhou 9 "sem quota ou saldo (HTTP 429) — a chave em si está válida" \
                       'conferir saldo e limites de uso do projeto na OpenAI' ;;
        000|"") falhou 9 "sem resposta da API — a credencial NÃO chegou a ser testada" \
                          'conferir conexão, proxy e firewall e rodar de novo; a chave não é o problema aqui — não mexa nela' ;;
        *) falhou 9 "resposta inesperada da API (HTTP $CODIGO)" \
                     'investigar a resposta antes de mexer no .env' ;;
    esac
fi

# ─── Dados ──────────────────────────────────────────────────────────────────

secao "Dados"

TEM_DUMPS=0; DUMPS_INTEGROS=0

# 10 — dumps presentes
AUSENTES=""
for D in $DUMPS; do
    [ -f "data/raw/$D" ] || AUSENTES="$AUSENTES $D"
done
if [ -z "$AUSENTES" ]; then
    ok 10 "dumps presentes em data/raw/"
    TEM_DUMPS=1
else
    falhou 10 "dump(s) ausente(s) em data/raw/:$AUSENTES" \
               'git checkout -- data/raw/   (os dumps são versionados)'
fi

# 11 — dumps íntegros
if [ "$TEM_DUMPS" -eq 0 ]; then
    pulou 11 "dumps íntegros (depende de: dumps presentes)"
else
    CORROMPIDOS=""
    for D in $DUMPS; do
        gzip -t "data/raw/$D" 2>/dev/null || CORROMPIDOS="$CORROMPIDOS $D"
    done
    if [ -z "$CORROMPIDOS" ]; then
        ok 11 "dumps íntegros (gzip -t)"
        DUMPS_INTEGROS=1
    else
        falhou 11 "dump(s) corrompido(s):$CORROMPIDOS" \
                   'git checkout -- data/raw/; persistindo, o clone veio truncado — clonar de novo'
    fi
fi

# 12 — data/raw/ sem modificação local. O dado bruto é imutável por contrato.
if [ "$TEM_DUMPS" -eq 0 ]; then
    pulou 12 "data/raw/ sem modificação local (depende de: dumps presentes)"
elif ! git rev-parse --git-dir >/dev/null 2>&1; then
    pulou 12 "data/raw/ sem modificação local (depende de: repositório git)"
elif git diff --quiet HEAD -- data/raw/ 2>/dev/null; then
    ok 12 "data/raw/ sem modificação local"
else
    MODIFICADOS="$(git diff --name-only HEAD -- data/raw/ 2>/dev/null | tr '\n' ' ')"
    falhou 12 "data/raw/ modificado localmente: $MODIFICADOS" \
               'git checkout -- data/raw/   (data/raw/ é imutável; limpeza acontece na carga)'
fi

# 17 — banco derivado: existe E registra carga concluída e completa.
# Quatro condições numa linha só porque o banco é descartável e a carga é
# determinística: todo estado inválido tem a mesma correção. A mensagem diz qual falhou.

consulta_db() {
    if command -v sqlite3 >/dev/null 2>&1; then
        sqlite3 "$BANCO" "$1" 2>/dev/null
    else
        .venv/bin/python -c 'import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
linha = con.execute(sys.argv[2]).fetchone()
print("" if linha is None or linha[0] is None else linha[0])' "$BANCO" "$1" 2>/dev/null
    fi
}

motivo_carga_invalida() {
    local n origem lidas inseridas descartadas contagem esperadas

    n="$(consulta_db "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='carga_meta'")"
    if [ "${n:-0}" != "1" ]; then
        echo "tabela carga_meta ausente"; return
    fi

    for origem in $DUMPS; do
        n="$(consulta_db "SELECT COUNT(*) FROM carga_meta WHERE origem='$origem' AND concluida_em IS NOT NULL AND TRIM(concluida_em) <> ''")"
        if [ "${n:-0}" != "1" ]; then
            echo "sem marca de conclusão para $origem — carga interrompida"; return
        fi
    done

    lidas="$(consulta_db "SELECT linhas_lidas FROM carga_meta WHERE origem='vendas.csv.gz'")"
    inseridas="$(consulta_db "SELECT linhas_inseridas FROM carga_meta WHERE origem='vendas.csv.gz'")"
    descartadas="$(consulta_db "SELECT linhas_descartadas FROM carga_meta WHERE origem='vendas.csv.gz'")"
    contagem="$(consulta_db "SELECT COUNT(*) FROM vendas")"

    if [ -z "$contagem" ]; then
        echo "tabela vendas ausente ou ilegível"; return
    fi
    if [ "${inseridas:-x}" != "$contagem" ]; then
        echo "carga_meta declara $inseridas venda(s) inserida(s), a tabela tem $contagem"; return
    fi
    if [ "$((${inseridas:-0} + ${descartadas:-0}))" != "${lidas:-x}" ]; then
        echo "inseridas + descartadas não fecham com linhas_lidas em vendas.csv.gz"; return
    fi

    # linhas de dados do dump, sem o cabeçalho
    esperadas="$(( $(gzip -dc data/raw/vendas.csv.gz 2>/dev/null | wc -l) - 1 ))"
    if [ "${lidas:-x}" != "$esperadas" ]; then
        echo "carga leu $lidas linha(s) de vendas.csv.gz, o dump tem $esperadas — banco de outro dump"; return
    fi
}

if [ "$TEM_DUMPS" -eq 0 ] || [ "$DUMPS_INTEGROS" -eq 0 ]; then
    pulou 17 "carga concluída e completa (depende de: dumps presentes e íntegros)"
elif ! command -v sqlite3 >/dev/null 2>&1 && [ "$TEM_SYNC" -eq 0 ]; then
    pulou 17 "carga concluída e completa (depende de: sqlite3 no PATH ou ambiente Python utilizável)"
elif [ ! -f "$BANCO" ]; then
    falhou 17 "$BANCO ausente — a carga nunca rodou" "$FIX_CARGA"
else
    MOTIVO="$(motivo_carga_invalida)"
    if [ -z "$MOTIVO" ]; then
        ok 17 "carga concluída e completa em $BANCO"
    else
        falhou 17 "carga inválida: $MOTIVO" "$FIX_CARGA"
    fi
fi

# ─── Observabilidade ────────────────────────────────────────────────────────

secao "Observabilidade (necessária a partir da semana 6)"

TEM_DOCKER=0

# 13 — docker no PATH
if command -v docker >/dev/null 2>&1; then
    ok 13 "docker instalado"
    TEM_DOCKER=1
else
    avisou 13 "docker ausente — necessário para o Langfuse self-hosted"
fi

# 14 — plugin compose
if [ "$TEM_DOCKER" -eq 0 ]; then
    pulou 14 "docker compose disponível (depende de: docker instalado)"
elif docker compose version >/dev/null 2>&1; then
    ok 14 "docker compose disponível"
else
    avisou 14 "plugin docker compose ausente"
fi

# 15 — daemon respondendo
if [ "$TEM_DOCKER" -eq 0 ]; then
    pulou 15 "daemon do Docker respondendo (depende de: docker instalado)"
elif docker info >/dev/null 2>&1; then
    ok 15 "daemon do Docker respondendo"
else
    avisou 15 "daemon do Docker não responde — Docker parado"
fi

# 16 — Langfuse. Aviso enquanto as chaves estiverem vazias (a 8 já avisou);
# falha dura assim que forem preenchidas: chave configurada que não responde
# é ambiente quebrado, não trabalho futuro.
if [ "$TEM_LANGFUSE" -eq 0 ]; then
    pulou 16 "Langfuse responde em LANGFUSE_HOST (depende de: chaves do Langfuse preenchidas)"
elif ! command -v curl >/dev/null 2>&1; then
    falhou 16 "curl ausente — o Langfuse não pôde ser testado" 'instalar o curl'
else
    CODIGO_LF="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -u "$LF_PUB:$LF_SEC" "${LF_HOST%/}/api/public/health" 2>/dev/null)"
    case "$CODIGO_LF" in
        200) ok 16 "Langfuse responde em $LF_HOST (HTTP 200)" ;;
        401|403) falhou 16 "Langfuse recusou as chaves (HTTP $CODIGO_LF)" \
                            'conferir LANGFUSE_PUBLIC_KEY e LANGFUSE_SECRET_KEY no .env' ;;
        000|"") falhou 16 "sem resposta de $LF_HOST" \
                           'subir o Langfuse e conferir LANGFUSE_HOST' ;;
        *) falhou 16 "resposta inesperada do Langfuse (HTTP $CODIGO_LF)" \
                      'conferir se LANGFUSE_HOST aponta mesmo para o Langfuse' ;;
    esac
fi

# ─── Resumo ─────────────────────────────────────────────────────────────────

printf '\n'

if [ "$N_FALHAS" -eq 0 ]; then
    printf '%s✓ Ambiente utilizável.%s' "$VERD$NEG" "$ZERO"
    [ "$N_AVISOS" -gt 0 ] && printf ' %s%d aviso(s) — nada que impeça trabalhar.%s' \
        "$AMAR" "$N_AVISOS" "$ZERO"
    printf '\n'
    exit 0
fi

printf '%s══ %d falha(s) ══%s\n\n' "$NEG$VERM" "$N_FALHAS" "$ZERO"
i=0
while [ "$i" -lt "$N_FALHAS" ]; do
    printf '%s✗%s %s\n    %s→ %s%s\n\n' \
        "$VERM" "$ZERO" "${FALHAS_MSG[$i]}" "$CINZA" "${FALHAS_FIX[$i]}" "$ZERO"
    i=$((i + 1))
done
printf '%sAmbiente NÃO utilizável.%s\n' "$NEG$VERM" "$ZERO"
exit 1
