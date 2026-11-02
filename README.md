# Sistema web do bingo

Hospedagem: GitHub Pages. Banco e autenticação: Supabase Free.

## Estado da implementação

Interface direta em vinho e branco. Login, venda em lote, busca, entrada, benefícios, edição de nome, catálogo, pedidos, preparo, entrega, cancelamento com motivo, caixa com pagamentos parciais e reabertura administrativa estão implementados.

Ainda faltam QR/câmera, gestão de usuários pela interface, exportação, configuração completa por evento e validação de uso em celulares com a equipe. Cancelamento após pagamento requer ajuste financeiro ainda não disponível. Não usar no evento antes do ensaio completo.

Testes SQL em `supabase/tests` usam transações revertidas. Não mantêm participantes ou pagamentos fictícios.

## Configuração

1. Em Settings → Pages, selecionar GitHub Actions como origem.
2. Preencher `web/config.js` com a chave **publicável** do projeto Supabase. Nunca usar chave secreta ou service_role.
3. Executar as migrações pendentes no SQL Editor.
4. Criar usuários em Authentication e cadastrar seus UUIDs na tabela team_members. Não abrir cadastro público de voluntários.

O login mantém o token apenas em memória. Recarregar a página exige novo acesso.

Nenhum dado de participantes, planilha ou senha deve ser adicionado ao repositório.
