# Sistema web do bingo

Hospedagem: GitHub Pages. Banco e autenticação: Supabase Free.

## Estado da implementação

Primeira entrega: interface responsiva de acesso, integração de login por senha, verificação de vínculo da equipe e publicação via GitHub Actions. As telas operacionais ainda não estão implementadas. Não usar no evento nesta fase.

## Configuração

1. Em Settings → Pages, selecionar GitHub Actions como origem.
2. Preencher `web/config.js` com a chave **publicável** do projeto Supabase. Nunca usar chave secreta ou service_role.
3. Executar as migrações pendentes no SQL Editor.
4. Criar usuários em Authentication e cadastrar seus UUIDs na tabela team_members. Não abrir cadastro público de voluntários.

O login mantém o token apenas em memória. Recarregar a página exige novo acesso.

Nenhum dado de participantes, planilha ou senha deve ser adicionado ao repositório.
