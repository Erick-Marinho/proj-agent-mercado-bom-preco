# Contrato do `scripts/verify.sh`

## Propósito

Responder a uma pergunta só: **este ambiente está utilizável?** O script diagnostica e
reporta. Ele não conserta nada.

## Fora de escopo

Não instala, não roda `uv sync`, não cria `.venv`, não copia o `.env`, não gera o banco.
Toda mutação é do `setup.sh`. Por isso usa `uv sync --check` e `uv run --no-sync`, nunca as
formas que criam ambiente por efeito colateral. Rodar o `verify.sh` duas vezes seguidas
produz o mesmo resultado, e `git status` não muda depois dele.

## Vocabulário do relatório

| Símbolo | Significado | Afeta o exit code |
|---|---|---|
| `✓` ok | a checagem passou | não |
| `✗` falha | o ambiente não serve para trabalhar | **sim** |
| `⚠` aviso | ainda não é necessário, mas vai ser | não |
| `—` pulado | um pré-requisito desta checagem já reprovou | não |

**Regra de granularidade:** uma linha de relatório = uma causa = um comando de correção.
Duas causas com correções diferentes nunca compartilham linha. É o que permite ao usuário
ler o resumo e saber exatamente o que fazer, sem interpretar.

**Regra do pulado:** checagem cujo pré-requisito falhou não é executada e não conta como
falha — o problema já foi reportado uma vez, na sua causa raiz. A linha diz de quem depende.

## Checagens

Ambiente Python:

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 1 | `uv` está no PATH | falha | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| 2 | a versão de `.python-version` está disponível ao `uv` | falha | `uv python install <pin>` |
| 3 | o ambiente está sincronizado com o `pyproject.toml` | falha | `uv sync` |
| 4 | o interpretador do projeto é o da `.python-version` | falha | `rm -rf .venv && uv sync` |

O pin é lido de `.python-version` em tempo de execução. O número da versão não aparece
escrito no script. 2 depende de 1; 3 depende de 1 e 2; 4 depende de 3.

Duas armadilhas do `uv`, descobertas na prática e registradas aqui para quem for mexer:
`uv sync --check` devolve 0 **mesmo sem `.venv` nenhum**, então a 3 confere a existência do
ambiente virtual antes de consultá-lo; e `uv run`, mesmo com `--no-sync`, **cria o `.venv`**
quando ele falta — por isso a 4 lê a versão direto de `.venv/bin/python`, e não via `uv run`.
Um verify que cria ambiente deixa de ser diagnóstico.

Credenciais:

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 5 | o `.env` existe | falha | `cp .env.example .env` e preencher |
| 6 | toda chave do `.env.example` existe no `.env` | falha | acrescentar ao `.env` as chaves faltantes, nomeadas na mensagem |
| 7 | `OPENAI_API_KEY` está preenchida | falha | preencher no `.env` |
| 8 | as três chaves de Langfuse estão preenchidas | **aviso** | necessárias a partir da semana 6 |

A checagem 6 é o que pega a chave que entrou no `.env.example` depois de o dev já ter
criado o `.env` dele. 6, 7 e 8 dependem de 5.

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 9 | a `OPENAI_API_KEY` responde a uma chamada real | falha | **depende do motivo, ver abaixo** |

A chamada é `GET https://api.openai.com/v1/models`, autenticada, com timeout de 15s.
Depende de 7. O veredito sai do código HTTP, e **cada código tem sua própria correção** —
é a diferença entre o usuário consertar o problema e o usuário trocar a chave à toa:

| Código | Mensagem | Correção |
|---|---|---|
| `200` | credencial responde | — |
| `401` | chave inválida ou revogada | gerar nova chave e substituir no `.env` |
| `403` | chave sem permissão para o recurso | conferir as permissões da chave no painel da OpenAI |
| `429` | sem quota ou saldo | conferir saldo e limites de uso do projeto — a chave em si está válida |
| `000` | **sem resposta: a credencial não chegou a ser testada** | conferir conexão, proxy e firewall, e rodar de novo — **não mexer na chave** |
| outro | resposta inesperada, com o código impresso | investigar antes de mexer no `.env` |

`000` é o `curl` dizendo que não houve resposta. É rede, não credencial, e a mensagem tem
que deixar isso explícito: sem isso o usuário gera chave nova achando que resolveu, e o
problema volta na próxima execução.

Dados brutos — três causas independentes, três linhas:

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 10 | `produtos.csv.gz` e `vendas.csv.gz` existem em `data/raw/` | falha | `git checkout -- data/raw/` — os dumps são versionados |
| 11 | os dois passam em `gzip -t` | falha | `git checkout -- data/raw/`; persistindo, o clone veio truncado — clonar de novo |
| 12 | `data/raw/` não tem modificação local | falha | `git checkout -- data/raw/` — `data/raw/` é imutável por contrato; limpeza acontece na carga |

Cada linha nomeia o arquivo específico que falhou. 11 e 12 dependem de 10.

Banco derivado:

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 17 | `data/bom_preco.db` existe e registra uma carga concluída e completa | falha | `rm -f data/bom_preco.db && uv run python -m bom_preco.carga` |

Arquivo existente não prova carga completa. Carga interrompida deixa um banco que responde
consulta com número errado — falha que não quebra nada e mente, que é a pior espécie.

São quatro condições numa linha só, e isso não fere a regra de granularidade: o banco é
derivado e descartável, e a carga é determinística, então **todo estado inválido tem a
mesma correção** — apagar e recarregar. Quatro sintomas, uma causa prática, um comando.
A mensagem nomeia qual condição falhou.

As condições, contra a tabela `carga_meta` especificada em [`carga.md`](carga.md):

1. `data/bom_preco.db` existe e abre;
2. `carga_meta` tem linha para cada arquivo de `data/raw/`, com `concluida_em` preenchido;
3. `linhas_inseridas` da origem `vendas.csv.gz` bate com `SELECT COUNT(*) FROM vendas`;
4. `linhas_lidas` da mesma origem bate com as linhas de dados de `data/raw/vendas.csv.gz`.

Depende de 10 e 11: dump ausente ou corrompido invalida a comparação, não o banco.

A condição 4 só detecta banco velho — carga completa, feita antes de o dump mudar — quando
a mudança altera a contagem de linhas. Alteração que preserve o número de linhas passa
despercebida. Fechar essa brecha exigiria a carga gravar o hash da origem, e isso é uma
**decisão adiada**, registrada em [`carga.md`](carga.md), não uma omissão.

Observabilidade — necessária a partir da semana 6, aviso até lá:

| # | Verifica | Se não | Correção |
|---|---|---|---|
| 13 | `docker` está no PATH | aviso | instalar o Docker |
| 14 | `docker compose` está disponível | aviso | instalar o plugin Compose |
| 15 | o daemon do Docker responde | aviso | iniciar o Docker |
| 16 | o Langfuse responde em `LANGFUSE_HOST` | **falha**, e só quando as chaves estiverem preenchidas | subir o Langfuse e conferir `LANGFUSE_HOST` |

14 e 15 dependem de 13. A 16 é pulada enquanto as chaves de Langfuse estiverem vazias — a
checagem 8 já avisou. Quando estiverem preenchidas, ela deixa de ser opcional: chave
configurada que não responde é ambiente quebrado, não trabalho futuro. A chamada é real,
contra `$LANGFUSE_HOST/api/public/health`, autenticada com o par de chaves.

## Exit code

| Código | Quando |
|---|---|
| `0` | nenhuma falha. Avisos e pulados podem existir — o ambiente está utilizável |
| `1` | uma falha ou mais |

Avisos nunca alteram o exit code. É o que permite a `verify.sh` entrar em CI ou em
`setup.sh && verify.sh` sem reprovar por causa do Docker que ainda não é usado.

## Formato de saída

Durante: uma linha por checagem, numerada, com o símbolo e a descrição. O número é
identidade da checagem, não posição na fila — a 17 roda logo depois da 12, junto das outras
de dados, e a numeração fica fora de ordem no relatório de propósito. Checagem que mude de
lugar mantém o número.

No fim, havendo falhas: `══ N falha(s) ══`, cada uma com sua correção indentada, e
`Ambiente NÃO utilizável.` Sem falhas: `✓ Ambiente utilizável.` mais a contagem de avisos.

## Segredos

Nenhum valor de segredo é impresso, nem truncado, nem mascarado — só o nome da chave e o
veredito. O `.env` é parseado, nunca sourceado: é arquivo de dados, não script.
