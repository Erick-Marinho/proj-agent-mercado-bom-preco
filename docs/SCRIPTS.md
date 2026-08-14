# Scripts

Catálogo dos scripts do projeto e o contrato para escrever novos.

Leia este arquivo quando for **criar ou alterar um script**. Para apenas *usar*
os scripts no dia a dia, o `AGENTS.md` e o `README.md` já bastam.

> Este documento não repete o que o cabeçalho de cada script já explica. O
> cabeçalho é a documentação mais resistente a apodrecer que existe — ninguém
> edita o script sem passar por ele. Aqui fica só o que é comum a todos.

## Catálogo

| Script | Papel | Detalhes |
| --- | --- | --- |
| [`scripts/setup.sh`](../scripts/setup.sh) | **guia** | cabeçalho do arquivo |
| [`scripts/verify.sh`](../scripts/verify.sh) | **sensor** | cabeçalho do arquivo |

## O modelo: guias e sensores

Todo script daqui é uma das duas coisas — nunca as duas.

**Guia (feedforward).** Age. Antecipa o que vai dar errado e deixa o ambiente
no estado certo antes que o erro aconteça. Aumenta a chance de acertar de
primeira.

**Sensor (feedback).** Observa. Roda depois e diz o que está fora do lugar,
sem consertar. Permite a autocorreção — de um humano ou de um agente.

Os dois andam em par e um sozinho não funciona: sensor sem guia repete a mesma
reclamação para sempre; guia sem sensor nunca descobre se funcionou.

Por isso a regra vale nos dois sentidos: toda dependência nova de ambiente
ganha **um passo no guia e uma verificação no sensor**. Se o `verify.sh` não
detectou uma quebra que aconteceu na vida real, essa é a deixa para adicionar
a verificação que faltava.

## Contrato para escrever um script

**Um papel só.** Ou age, ou observa. Um sensor que conserta silenciosamente
esconde o problema em vez de mostrá-lo; um guia que só reclama não serve para
configurar máquina nenhuma.

**Autossuficiente.** Só bash e coreutils, sem `source` de biblioteca comum.
Duplicar 15 linhas de helper é mais barato que um script de bootstrap que
depende de algo que ainda não foi instalado. Se um dia surgir uma
`scripts/lib/`, ela não pode ser exigida pelo `setup.sh`.

**Roda de qualquer pasta.** Calcule a raiz a partir do próprio caminho do
script (`BASH_SOURCE`), nunca do diretório de trabalho, e confirme que está no
repositório certo antes de agir.

**Idempotente.** Rodar duas vezes não pode quebrar nem apagar nada. Nunca
sobrescreva arquivo pessoal (`.env` é o caso óbvio); se for realmente preciso
destruir algo, pergunte antes e aceite `--yes` para automação.

**Guias param no primeiro erro** (`set -euo pipefail`): continuar depois de um
passo falho deixa a máquina meio configurada, que é pior que não configurada.

**Sensores nunca param** (`set -uo pipefail`, sem o `-e`): o valor está em
listar todas as falhas de uma vez. Envolva cada verificação em `if` e decida o
código de saída no fim, a partir do contador.

## Contrato das mensagens

É a parte que mais importa, porque a saída do script é o que entra no contexto
de quem vai corrigir — pessoa ou agente.

**Toda falha carrega o conserto.** No `verify.sh` isso é imposto pela forma da
função: `fail` exige três argumentos — o que falhou, o motivo observado e o
comando de correção. Não existe assinatura curta, então é impossível registrar
um sintoma sem a solução.

**A correção precisa ser copiável.** `./scripts/setup.sh` serve; "configure o
ambiente" não serve.

**Diga o que fazer, não o que evitar.** Uma instrução positiva substitui uma
lista infinita de proibições — "use `uv add`" cobre mais terreno que enumerar
cada gerenciador que não deve ser usado.

**Reprovar e avisar são coisas diferentes.** Reprove (saída `1`) o que impede
de trabalhar agora. Avise o que ainda não bloqueia, e diga desde quando vai
bloquear — é o caso do Docker, que só entra na semana 6.

**"Não avaliado" é um terceiro estado.** Quando falta um pré-requisito, marque
a verificação como não avaliada em vez de reprovar: uma causa raiz não deve
virar cascata de falhas derivadas que escondem qual é o problema real.

## Ao adicionar um script

1. Crie em `scripts/`, com `#!/usr/bin/env bash` e `chmod +x`.
2. Escreva o cabeçalho: o que é, como usar, códigos de saída e como estender.
3. Declare o papel — guia ou sensor — e siga o contrato correspondente.
4. Acrescente uma linha no catálogo acima.
5. Teste o caminho de **falha**, não só o de sucesso. Sensor que nunca dispara
   é indistinguível de sensor quebrado.
