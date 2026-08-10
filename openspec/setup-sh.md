# Contrato do `scripts/setup.sh`

## Propósito

Montar o ambiente do zero, num comando só. O script muta e prepara; não julga o resultado.
É o par mutante do [`verify.sh`](verify-sh.md): **o setup produz exatamente o que o verify
confere.** Quem responde "está utilizável?" é o verify.

Rodar de qualquer diretório funciona — o script se reposiciona na raiz do repositório.

## O que ele produz

Cinco passos, nesta ordem, cada um dependendo do anterior:

| # | Passo | Produz | Se já existe |
|---|---|---|---|
| 1 | `uv` | `uv` no PATH, via instalador oficial | mantém, imprime a versão |
| 2 | Python | a versão de `.python-version` disponível ao `uv` | mantém |
| 3 | Dependências | `.venv` convergido para o `pyproject.toml` (`uv sync`) | converge de novo |
| 4 | `.env` | cópia do `.env.example`, com `chmod 600` | **mantém intacto** |
| 5 | Carga | `data/bom_preco.db` (`uv run python -m bom_preco.carga`) | recria do zero |

O pin de Python é lido de `.python-version` em tempo de execução; a versão não aparece
escrita no script.

**Idempotência:** rodar duas vezes seguidas não quebra e não desfaz nada. Passos 1, 2 e 3
convergem por natureza; o 4 é protegido por contrato; o 5 é seguro porque a carga é
determinística e nada feito à mão mora no banco derivado.

## O que ele deliberadamente NÃO faz

**Não confere nada.** Nenhuma checagem de credencial, nenhum diagnóstico. Um setup que
também verifica duplica a lógica do verify e as duas cópias divergem. A última linha da
saída de sucesso aponta para `./scripts/verify.sh` justamente por isso.

**Não sobrescreve o `.env`.** Um `cp` descuidado aqui apaga credencial que ninguém tem
cópia. Existindo `.env`, ele é mantido como está — inclusive incompleto ou desatualizado.
Chave que faltar é problema do verify (checagem 6), não daqui.

**Não preenche segredo.** O `.env` sai do `.env.example` com os valores vazios. `OPENAI_API_KEY`
é preenchida à mão; o script diz isso e segue.

**Não toca em `data/raw/`.** Dado bruto é imutável por contrato. Limpeza acontece na carga.

**Não sobe o Docker nem o Langfuse.** Observabilidade só é necessária a partir da semana 6,
e o verify já reporta isso como aviso. Subir container que ninguém vai usar ainda é custo
sem contrapartida.

**Não usa `set -e`.** Cada passo trata o próprio erro, com mensagem que serve para quem
chega agora. `set -e` mata o script em silêncio, no pior momento possível: o usuário vê o
prompt voltar sem saber o que falhou.

## Comportamento em cada falha

Toda falha aborta na hora, com bloco de mensagem que nomeia a causa e o comando de correção,
e sai com `1`. Os passos anteriores já concluídos permanecem — o setup nunca faz rollback.

Passo 1 — `uv`:

| Situação | Mensagem e correção |
|---|---|
| `curl` ausente | instalar o `curl` e rodar de novo — sem ele não há como instalar o `uv` |
| instalador falhou | conferir conexão, ou instalar à mão pela doc do `uv` |
| instalou, mas `uv` não aparece | reabrir o terminal, ou `export PATH="$HOME/.local/bin:$PATH"` |

O último caso é o que justifica a função `carregar_path_do_uv`: o instalador escreve no
perfil do shell, o que não afeta a sessão em curso. O script recarrega `~/.local/bin/env` e
`~/.cargo/env` e reinsere os diretórios no PATH antes de desistir. Parar aqui é melhor do
que seguir e falhar de um jeito confuso três passos adiante.

Passo 2 — Python:

| Situação | Mensagem e correção |
|---|---|
| `.python-version` ausente ou vazio | `git checkout -- .python-version` — o projeto não declara sua versão |
| `uv python install` falhou | rodar `uv python install <pin>` à mão para ver o erro completo |

Passo 3 — dependências: `uv sync` falhou → rodar `uv sync` à mão para ver o erro completo.

Passo 4 — `.env`:

| Situação | Mensagem e correção |
|---|---|
| `.env.example` ausente | `git checkout -- .env.example` — não há de onde criar o `.env` |
| `cp` falhou | erro de escrita; a mensagem nomeia o passo |

O `chmod 600` é best-effort: falha nele não aborta, porque sistema de arquivos sem
permissão POSIX não é motivo para reprovar o ambiente inteiro.

Passo 5 — carga. Três desfechos distintos, porque cada um manda o usuário para um lugar
diferente:

| Situação | O que a mensagem diz |
|---|---|
| `src/bom_preco/` não existe | **não é erro de instalação — é código que ainda não foi escrito.** Aponta para [`carga.md`](carga.md) e avisa que o verify vai reprovar na checagem 17 até lá |
| existe, mas o import falha (`No module named`) | aponta para o `pyproject.toml`, que precisa declarar onde o pacote mora — e afirma que `uv` e Python estão bem, os dois passos anteriores terminaram |
| carga falhou por outro motivo | imprime a saída da carga e o comando para repeti-la isoladamente |

A saída da carga é capturada e reimpressa em qualquer desfecho — sucesso ou falha. Erro de
carga sem a saída dela é indepurável.

O primeiro caso é o estado atual do repositório: enquanto `src/bom_preco/` não existir,
**`setup.sh` termina em `1`** mesmo tendo montado os quatro primeiros passos com sucesso. É
deliberado. O contrato do exit code é "o ambiente ficou pronto", e sem banco ele não ficou.
Mentir `0` aqui faria `setup.sh && verify.sh` passar no primeiro comando e reprovar no
segundo, que é o pior lugar para descobrir.

## Exit code

| Código | Quando |
|---|---|
| `0` | os cinco passos concluíram — o ambiente está montado |
| `1` | um passo falhou; a mensagem diz qual e o que fazer |

## Formato de saída

Um bloco por passo, numerado `[n/5]`. Dentro dele: `✓` para o que foi criado, `·` para o que
já existia e foi mantido, e nota indentada em cinza para o que o usuário ainda precisa fazer
à mão. Falha vira `✗` seguido do bloco de correção. Cor sai automaticamente quando a saída
não é um terminal ou quando `NO_COLOR` está definida.

## Restrições de implementação

Bash 3.2, o que o macOS traz — sem `declare -A`, sem `mapfile`, sem `readarray`. Mesma
restrição do [`verify.sh`](verify-sh.md).
