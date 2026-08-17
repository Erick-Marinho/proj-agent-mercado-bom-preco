# 0001 — O `uv` não serve para diagnóstico sem cuidado

## Problema

O `verify.sh` precisa responder se o ambiente Python está utilizável **sem criar nada**. As
formas óbvias de perguntar isso ao `uv` mentem, e as duas armadilhas só aparecem na prática:

- `uv sync --check` devolve `0` **mesmo sem `.venv` nenhum**. Perguntado ingenuamente, o
  `uv` responde "sincronizado" sobre um ambiente que não existe.
- `uv run`, mesmo com `--no-sync`, **cria o `.venv`** quando ele falta. Um verify que
  consulta o interpretador por `uv run` monta o ambiente que deveria estar diagnosticando.

Um verify que cria ambiente deixa de ser diagnóstico: ele passa a produzir o estado que
deveria reprovar, e a segunda execução reporta algo diferente da primeira.

## Opções

1. **Confiar nas saídas do `uv`.** Mais curto e mais legível. Reprovado: as duas armadilhas
   acima produzem falso positivo silencioso — o pior desfecho para uma ferramenta cuja única
   função é dizer a verdade sobre o ambiente.
2. **Inspecionar o sistema de arquivos antes de consultar o `uv`.** Mais verboso, e depende
   de detalhes de layout do `.venv`.
3. **Deixar o verify criar o ambiente quando ele falta.** Reprovado de saída: apaga a
   fronteira com o `setup.sh` (ver [0002](0002-separacao-entre-setup-e-verify.md)) e torna o
   resultado dependente da ordem das execuções.

## Escolha

Opção 2. A checagem 3 confere a existência do `.venv` antes de consultar o `uv`, e a
checagem 4 lê a versão direto de `.venv/bin/python`, nunca via `uv run`.

## Porquê

O custo é verbosidade em duas checagens. O ganho é que o verify continua sendo o que ele diz
ser: rodar duas vezes seguidas dá o mesmo resultado, e `git status` não muda depois dele.
Falso positivo aqui é caro de um jeito específico — o usuário recebe "ambiente utilizável" e
descobre o contrário três passos adiante, longe da causa.

Ambas as armadilhas são comportamento do `uv`, não do projeto, e podem mudar de versão.
Quem for mexer nessas duas checagens precisa reproduzir os dois casos — `.venv` ausente com
`--check`, e `uv run --no-sync` sem `.venv` — antes de simplificar.

O comportamento resultante está especificado na capability `ambiente-verificacao`.
