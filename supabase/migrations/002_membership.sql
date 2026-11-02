-- A base já foi criada no painel do projeto.
-- Permite ao usuário consultar apenas a própria autorização.
begin;
drop policy if exists own_membership on public.team_members;
create policy own_membership on public.team_members
for select to authenticated using (user_id=auth.uid());
grant select on public.team_members to authenticated;
commit;
