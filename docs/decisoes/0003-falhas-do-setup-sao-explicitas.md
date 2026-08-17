# 0003 — O `setup.sh` falha alto, e reprova sem o banco

## Problema

Duas perguntas sobre como o setup termina mal.

A primeira: como abortar. `set -e` é o reflexo em Bash, e mata o script no primeiro comando
que retorna diferente de zero — em silêncio, sem dizer qual foi. O usuário vê o prompt
voltar e não sabe o que aconteceu.

A segunda é mais incômoda. O passo 5 roda a carga, e hoje `src/bom_preco/` não existe. O
setup monta os quatro primeiros passos com sucesso e não tem como concluir o quinto. Sair
com `0` ou com `1`?

## Opções

Para abortar:

1. `set -e` no topo.
2. Cada passo trata o próprio erro, com bloco de mensagem nomeando causa e correção.

Para o exit code com a carga impossível:

1. **Sair `0`** — os passos que dependiam do script funcionaram; o que falta é código que
   ninguém escreveu ainda, e não erro de instalação.
2. **Sair `1`** — o ambiente não ficou pronto, seja qual for o motivo.

## Escolha

Tratamento de erro por passo, sem `set -e`. Toda falha aborta na hora com bloco que nomeia
causa e correção, e os passos já concluídos permanecem — o setup nunca faz rollback.

E exit `1` quando falta `src/bom_preco/`, mesmo com quatro passos bem-sucedidos. A mensagem
desse caso é específica: diz que não é erro de instalação, aponta para a capability `carga`
e avisa que o verify vai reprovar na checagem 17 até o módulo existir.

## Porquê

**Sem `set -e`:** o script é a primeira coisa que alguém roda no projeto, muitas vezes antes
de saber o que é `uv`. Cada modo de falha conhecido tem correção diferente — `curl` ausente,
instalador que falhou, `uv` instalado que não apareceu no PATH — e `set -e` colapsa os três
em "o prompt voltou". O custo é tratamento explícito em cada passo; o ganho é que a mensagem
serve para quem chega agora.

**Exit `1` sem o banco:** o contrato do exit code é "o ambiente ficou pronto", e sem banco
ele não ficou. Mentir `0` faria `setup.sh && verify.sh` passar no primeiro comando e
reprovar no segundo — que é o pior lugar para descobrir, porque desloca o diagnóstico para
longe da causa e faz parecer problema do verify. O estado atual do repositório é exatamente
esse caso, e é deliberado que ele reprove.

Especificado na capability `ambiente-setup`. Relacionado: [0002](0002-separacao-entre-setup-e-verify.md),
que estabelece por que o setup não diagnostica.
