# ambiente-verificacao Specification

## Purpose

Responder a uma pergunta só: **este ambiente está utilizável?** O `scripts/verify.sh`
diagnostica e reporta; não conserta nada. É o par diagnóstico da capability
`ambiente-setup`, que produz exatamente o que este confere. O raciocínio por trás das
escolhas está em `docs/decisoes/`.

## Requirements

### Requirement: Diagnóstico sem mutação

O verify DEVE apenas observar o ambiente. Ele NÃO DEVE instalar, rodar `uv sync`, criar
`.venv`, copiar o `.env` nem gerar o banco — toda mutação pertence ao `setup.sh`.

#### Scenario: Execução repetida não altera o repositório

- **WHEN** o verify roda duas vezes seguidas
- **THEN** as duas execuções produzem o mesmo resultado
- **AND** `git status` não muda depois de nenhuma delas

#### Scenario: Consulta ao ambiente sem criá-lo

- **WHEN** o verify precisa consultar o ambiente Python
- **THEN** usa `uv sync --check` e `uv run --no-sync`, nunca as formas que criam ambiente
  por efeito colateral

### Requirement: Vocabulário do relatório

Cada checagem DEVE ser reportada como ok (`✓`), falha (`✗`), aviso (`⚠`) ou pulado (`—`).
Somente a falha afeta o exit code.

#### Scenario: Checagem passa

- **WHEN** a condição verificada é satisfeita
- **THEN** a linha recebe `✓`
- **AND** o exit code não é afetado

#### Scenario: Ambiente não serve para trabalhar

- **WHEN** a condição verificada reprova
- **THEN** a linha recebe `✗`
- **AND** a execução termina com exit code `1`

#### Scenario: Requisito ainda não necessário

- **WHEN** a condição reprova, mas o recurso só passa a ser necessário mais adiante
- **THEN** a linha recebe `⚠`
- **AND** o exit code não é afetado

#### Scenario: Pré-requisito já reprovado

- **WHEN** um pré-requisito da checagem já falhou
- **THEN** a checagem não é executada e a linha recebe `—`, nomeando a checagem de que depende
- **AND** não conta como falha, porque a causa raiz já foi reportada na sua própria linha

### Requirement: Uma causa por linha de relatório

Uma linha DEVE corresponder a uma causa e a um comando de correção. Duas causas com
correções diferentes NÃO DEVEM compartilhar linha, para que o usuário leia o resumo e saiba
o que fazer sem interpretar.

#### Scenario: Causas independentes com correções distintas

- **WHEN** duas condições falham por motivos diferentes e exigem correções diferentes
- **THEN** cada uma ocupa sua própria linha, com sua própria correção

#### Scenario: Sintomas distintos com correção única

- **WHEN** várias condições falham e todas têm a mesma correção prática
- **THEN** ocupam uma linha só
- **AND** a mensagem nomeia qual condição falhou

### Requirement: Checagens do ambiente Python

O verify DEVE conferir, nesta ordem de dependência, que `uv` existe (checagem 1), que a
versão pinada está disponível (2), que o ambiente está sincronizado (3) e que o
interpretador é o do pin (4). O pin DEVE ser lido de `.python-version` em tempo de
execução, sem aparecer escrito no script.

#### Scenario: `uv` ausente do PATH

- **WHEN** a checagem 1 não encontra `uv`
- **THEN** falha, com a correção `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **AND** as checagens 2, 3 e 4 são puladas

#### Scenario: Versão pinada indisponível

- **WHEN** a checagem 2 não encontra no `uv` a versão declarada em `.python-version`
- **THEN** falha, com a correção `uv python install <pin>`

#### Scenario: Ambiente dessincronizado do `pyproject.toml`

- **WHEN** a checagem 3 encontra divergência entre `.venv` e o `pyproject.toml`
- **THEN** falha, com a correção `uv sync`

#### Scenario: Ambiente virtual inexistente

- **WHEN** a checagem 3 roda e não há `.venv`
- **THEN** confere a existência do ambiente virtual antes de consultá-lo, e falha
- **AND** não trata como sincronizado, mesmo que `uv sync --check` devolva `0`

#### Scenario: Interpretador diferente do pin

- **WHEN** a checagem 4 lê a versão direto de `.venv/bin/python` e ela diverge do pin
- **THEN** falha, com a correção `rm -rf .venv && uv sync`

### Requirement: Checagens de credenciais

O verify DEVE conferir que o `.env` existe (checagem 5), que ele tem toda chave presente no
`.env.example` (6), que `OPENAI_API_KEY` está preenchida (7) e que as três chaves de
Langfuse estão preenchidas (8). As checagens 6, 7 e 8 dependem da 5.

#### Scenario: `.env` ausente

- **WHEN** a checagem 5 não encontra o `.env`
- **THEN** falha, com a correção `cp .env.example .env` e preencher
- **AND** as checagens 6, 7 e 8 são puladas

#### Scenario: Chave nova no `.env.example` ainda ausente no `.env`

- **WHEN** a checagem 6 encontra no `.env.example` uma chave que não existe no `.env`
- **THEN** falha, nomeando na mensagem as chaves faltantes a acrescentar

#### Scenario: `OPENAI_API_KEY` vazia

- **WHEN** a checagem 7 encontra a chave sem valor
- **THEN** falha, com a correção de preenchê-la no `.env`

#### Scenario: Chaves de Langfuse vazias

- **WHEN** a checagem 8 encontra qualquer das três chaves sem valor
- **THEN** reporta aviso, informando que são necessárias a partir da semana 6
- **AND** o exit code não é afetado

### Requirement: Validação real da credencial OpenAI

A checagem 9 DEVE autenticar contra `GET https://api.openai.com/v1/models` com timeout de
15s e derivar o veredito e a correção do código HTTP obtido. Conferir a existência da
variável de ambiente não satisfaz este requisito. Depende da checagem 7.

#### Scenario: Credencial responde

- **WHEN** a resposta é `200`
- **THEN** a checagem passa

#### Scenario: Chave inválida ou revogada

- **WHEN** a resposta é `401`
- **THEN** falha, com a correção de gerar nova chave e substituir no `.env`

#### Scenario: Chave sem permissão

- **WHEN** a resposta é `403`
- **THEN** falha, com a correção de conferir as permissões da chave no painel da OpenAI

#### Scenario: Sem quota ou saldo

- **WHEN** a resposta é `429`
- **THEN** falha, com a correção de conferir saldo e limites de uso do projeto
- **AND** a mensagem afirma que a chave em si está válida

#### Scenario: Sem resposta da rede

- **WHEN** o `curl` não obtém resposta (código `000`)
- **THEN** falha declarando explicitamente que a credencial não chegou a ser testada
- **AND** a correção manda conferir conexão, proxy e firewall e rodar de novo, e diz para
  não mexer na chave

#### Scenario: Resposta inesperada

- **WHEN** a resposta traz qualquer outro código
- **THEN** falha imprimindo o código obtido, com a correção de investigar antes de mexer no `.env`

### Requirement: Checagens dos dados brutos

O verify DEVE conferir que os dois dumps existem (checagem 10), que passam em `gzip -t` (11)
e que `data/raw/` não tem modificação local (12), reportando cada causa em sua própria
linha e nomeando o arquivo que falhou. As checagens 11 e 12 dependem da 10.

#### Scenario: Dump ausente

- **WHEN** a checagem 10 não encontra `produtos.csv.gz` ou `vendas.csv.gz` em `data/raw/`
- **THEN** falha nomeando o arquivo, com a correção `git checkout -- data/raw/`
- **AND** as checagens 11, 12 e 17 são puladas

#### Scenario: Dump corrompido

- **WHEN** a checagem 11 reprova um arquivo em `gzip -t`
- **THEN** falha nomeando o arquivo, com a correção `git checkout -- data/raw/` e, persistindo,
  clonar de novo porque o clone veio truncado

#### Scenario: Dado bruto modificado localmente

- **WHEN** a checagem 12 encontra modificação local em `data/raw/`
- **THEN** falha, com a correção `git checkout -- data/raw/`
- **AND** a mensagem lembra que `data/raw/` é imutável por contrato e que limpeza acontece na carga

### Requirement: Checagem do banco derivado

A checagem 17 DEVE reprovar banco ausente, corrompido ou de carga incompleta, porque
arquivo existente não prova carga completa — carga interrompida deixa banco que responde
consulta com número errado. As quatro condições ocupam uma linha só porque todo estado
inválido tem a mesma correção. Depende das checagens 10 e 11.

#### Scenario: Todas as condições satisfeitas

- **WHEN** `data/bom_preco.db` existe e abre
- **AND** `carga_meta` tem linha para cada arquivo de `data/raw/`, com `concluida_em` preenchido
- **AND** `linhas_inseridas` da origem `vendas.csv.gz` bate com `SELECT COUNT(*) FROM vendas`
- **AND** `linhas_lidas` da mesma origem bate com as linhas de dados de `data/raw/vendas.csv.gz`
- **THEN** a checagem passa

#### Scenario: Qualquer condição reprovada

- **WHEN** qualquer uma das quatro condições não é satisfeita
- **THEN** falha, com a correção `rm -f data/bom_preco.db && uv run python -m bom_preco.carga`
- **AND** a mensagem nomeia qual condição falhou

#### Scenario: Dump inválido invalida a comparação

- **WHEN** a checagem 10 ou a 11 já reprovou
- **THEN** a checagem 17 é pulada, porque o que está em dúvida é o dump, não o banco

### Requirement: Checagens de observabilidade

O verify DEVE conferir `docker` no PATH (checagem 13), `docker compose` disponível (14) e o
daemon respondendo (15) como avisos, e a resposta do Langfuse (16) como falha condicionada às
chaves estarem preenchidas. As checagens 14 e 15 dependem da 13.

#### Scenario: Docker ausente ou parado

- **WHEN** a checagem 13, 14 ou 15 reprova
- **THEN** reporta aviso, com a correção de instalar o Docker, instalar o plugin Compose ou
  iniciar o Docker, conforme a checagem
- **AND** o exit code não é afetado

#### Scenario: Langfuse ainda não configurado

- **WHEN** as chaves de Langfuse estão vazias
- **THEN** a checagem 16 é pulada, porque a checagem 8 já avisou

#### Scenario: Langfuse configurado que não responde

- **WHEN** as chaves de Langfuse estão preenchidas
- **AND** `GET $LANGFUSE_HOST/api/public/health`, autenticado com o par de chaves, não responde
- **THEN** falha, com a correção de subir o Langfuse e conferir `LANGFUSE_HOST`
- **AND** deixa de ser opcional, porque chave configurada que não responde é ambiente quebrado

### Requirement: Exit code

O verify DEVE sair com `0` quando não houver falha e `1` quando houver uma ou mais. Avisos e
pulados NÃO DEVEM alterar o exit code.

#### Scenario: Ambiente utilizável com pendências futuras

- **WHEN** a execução termina sem falhas, mas com avisos ou pulados
- **THEN** o exit code é `0`
- **AND** `setup.sh && verify.sh` ou um passo de CI não reprovam por causa do Docker ainda não usado

#### Scenario: Uma falha ou mais

- **WHEN** ao menos uma checagem reprova
- **THEN** o exit code é `1`

### Requirement: Formato de saída

O relatório DEVE trazer uma linha por checagem, numerada, com símbolo e descrição, e um
resumo final. O número é identidade da checagem, não posição na fila: checagem que mude de
lugar mantém o número.

#### Scenario: Numeração fora de ordem no relatório

- **WHEN** a checagem 17 roda logo depois da 12, junto das outras de dados
- **THEN** a numeração aparece fora de ordem, de propósito
- **AND** o número da checagem permanece o mesmo

#### Scenario: Resumo com falhas

- **WHEN** a execução termina com falhas
- **THEN** imprime `══ N falha(s) ══`, cada uma com sua correção indentada
- **AND** imprime `Ambiente NÃO utilizável.`

#### Scenario: Resumo sem falhas

- **WHEN** a execução termina sem falhas
- **THEN** imprime `✓ Ambiente utilizável.` e a contagem de avisos

### Requirement: Sigilo dos segredos

O verify NÃO DEVE imprimir valor de segredo, nem truncado, nem mascarado — apenas o nome da
chave e o veredito. O `.env` DEVE ser parseado, nunca sourceado: é arquivo de dados, não script.

#### Scenario: Relatório sobre uma credencial

- **WHEN** qualquer checagem reporta o estado de uma chave
- **THEN** a saída traz o nome da chave e o veredito, e nenhum trecho do valor

#### Scenario: Leitura do `.env`

- **WHEN** o verify precisa ler as variáveis do `.env`
- **THEN** parseia o arquivo, sem executá-lo via `source`
