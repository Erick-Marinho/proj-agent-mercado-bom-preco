## Context

Ver `proposal.md` — Why. O que importa para o desenho: `data/raw/` é imutável por contrato e
está versionado; `data/bom_preco.db` é derivado, descartável e não versionado; e a checagem
17 do `verify.sh` já existe e já reprova, esperando por uma tabela `carga_meta` que ainda não
tem quem a escreva. O contrato do consumidor, portanto, veio antes da implementação, e este
desenho é o que o satisfaz.

Volume: ~716 linhas em `produtos.csv` e ~374k em `vendas.csv`. Nada que exija estratégia de
streaming sofisticada, mas grande o bastante para que uma falha no meio do arquivo seja um
cenário real, não hipotético.

## Goals / Non-Goals

**Goals:**

- Que a conclusão da carga seja um fato verificável por consulta, não pela rolagem de tela de
  quem a rodou.
- Que não exista estado intermediário observável: ou o banco está inteiro, ou não está.
- Que o `verify.sh` consiga distinguir banco completo de banco pela metade sem heurística.

**Non-Goals:**

- Desempenho. A carga roda uma vez por ambiente montado, não em laço.
- Detectar banco desatualizado em relação a um dump que mudou — ver a decisão sobre
  `origem_hash` abaixo.
- Esquema das tabelas de dados e regras de limpeza, que são de outro change.

## Decisions

### Transação única, com `concluida_em` como último statement

**Alternativas:** commit por lote, com marca de progresso; ou gravar `concluida_em` no início
da execução e atualizá-la ao final.

**Escolha:** uma transação só, e a marca é a última coisa escrita antes do commit.

**Porquê:** é o que faz a marca significar alguma coisa. Com commit por lote, uma
interrupção deixa banco com dados parciais e sem marca — e a checagem 17 passaria a precisar
distinguir "vazio" de "pela metade" de "completo", cada um com correção diferente. Com marca
gravada no início, existe janela em que a linha diz "concluída" sobre dados que ainda estão
entrando. Sendo o último statement de uma transação única, `concluida_em` preenchido é
equivalente a carga inteira, e o consumidor precisa testar uma coisa só.

O volume permite: 374k linhas em transação única é confortável para o SQLite, e o banco é
recriado do zero, então não há trabalho concorrente a bloquear.

### `carga_meta` como tabela, não só como saída no terminal

**Alternativa:** imprimir o relatório e parar por aí, já que o CLAUDE.md só exige que a carga
"emita relatório de linhas inseridas / corrigidas / descartadas".

**Escolha:** imprimir **e** gravar, com os mesmos números.

**Porquê:** relatório no terminal morre com o terminal. Duas semanas depois, ninguém sabe se
o banco que está no disco veio de uma carga completa ou de uma que alguém interrompeu — e
essa é exatamente a pergunta que o `verify.sh` precisa responder sozinho, sem humano no
circuito. A tabela é a mesma informação, com sobrevida.

### Recriar do zero, sem carga incremental

**Alternativa:** detectar o que já foi carregado e completar.

**Escolha:** apagar e refazer, sempre.

**Porquê:** carga incremental exige saber o que já entrou, o que só é confiável se houver
chave estável por linha — que os dados brutos não têm. E o ganho seria em tempo de execução,
que não é gargalo aqui. Recriar do zero é também o que torna o determinismo testável: rodar
duas vezes tem que dar o mesmo resultado, e isso é trivial de afirmar quando não há estado
anterior a considerar.

Consequência para o `setup.sh`: o passo 5 pode rodar sempre, sem checar nada antes.

### `origem_hash`: considerado e adiado

Registrado como decisão, não como esquecimento.

**A ideia:** uma coluna `origem_hash` em `carga_meta`, guardando o hash de cada arquivo de
`data/raw/` consumido, para o `verify.sh` recomputar e detectar **banco velho** — carga
completa, porém feita antes de o dump mudar.

**Adiado porque** hoje o dump não muda: veio do cliente uma vez, está versionado, e a
checagem 12 do `verify.sh` reprova qualquer modificação local nele. Enquanto isso valer,
comparar `linhas_lidas` com a contagem de linhas do arquivo — que é a condição 4 da checagem
17 — cobre a maior parte do risco.

**Reabrir quando** o dump passar a ser reenviado ou atualizado.

## Risks / Trade-offs

**A condição 4 da checagem 17 só detecta banco velho quando a mudança altera a contagem de
linhas** → alteração que preserve o número de linhas passa despercebida. Aceito
conscientemente: fechar a brecha é a coluna `origem_hash` acima, e a checagem 12 do verify
já reprova modificação local em `data/raw/`, que é o único caminho plausível hoje.

**Transação única sobre 374k linhas mantém a transação aberta durante toda a execução** →
irrelevante aqui, porque o banco é de uso exclusivo da carga e não há leitor concorrente. Se
um dia houver, a decisão precisa ser revista, não contornada com commits parciais — eles
quebram o significado da marca.

**`linhas_corrigidas` é fácil de ler errado** como terceira categoria, somável ao total →
mitigado especificando a invariante `linhas_corrigidas <= linhas_inseridas` no spec e
tratando-a como cenário testável, não como nota de rodapé.

**O esquema das tabelas de dados vem em change posterior**, e é ele que decide o que conta
como linha corrigida ou descartada → os contadores ficam especificados aqui em termos de
significado, e o change seguinte preenche quais transformações concretas caem em cada
categoria. A invariante não muda com isso.

## Open Questions

- O tratamento das ~5,2k linhas de venda com valores negativos (provável devolução ou
  estorno) decide se elas contam como inseridas ou descartadas. Não bloqueia este change: a
  invariante vale de qualquer forma. Pertence ao change do esquema e das regras de limpeza,
  e precisa de decisão registrada em `docs/decisoes/` quando for tratado.
