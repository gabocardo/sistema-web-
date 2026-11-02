-- Testes transacionais: todos os registros de teste são revertidos.
begin;
do $$
declare u uuid:=gen_random_uuid(); request_id uuid:=gen_random_uuid(); sale jsonb; repeated jsonb; ticket uuid; snapshot jsonb;
begin
insert into auth.users(id) values(u);
insert into public.team_members(user_id,role) values(u,'admin');
perform set_config('request.jwt.claim.sub',u::text,true);
sale:=public.sell_tickets(request_id,'00000000-0000-4000-8000-000000002026',2,'TESTE TRANSACIONAL','Pix');
repeated:=public.sell_tickets(request_id,'00000000-0000-4000-8000-000000002026',2,'TESTE TRANSACIONAL','Pix');
if sale<>repeated or jsonb_array_length(sale)<>2 then raise exception 'Falha na idempotência da venda'; end if;
ticket:=(sale->0->>'id')::uuid;
perform public.reception_action(ticket,'entry','');
perform public.reception_action(ticket,'entry','');
if (select count(*) from public.checkins where ticket_id=ticket)<>1 then raise exception 'Entrada duplicada'; end if;
perform public.reception_action(ticket,'benefit','initial_card');
perform public.reception_action(ticket,'benefit','initial_card');
if (select count(*) from public.benefit_claims where ticket_id=ticket)<>1 then raise exception 'Benefícios misturados ou duplicados'; end if;
update public.team_members set role='cozinha' where user_id=u;
begin
 perform public.reception_action(ticket,'name','INDEVIDO');
 raise exception 'TESTE FALHOU: edição autorizada';
exception when others then
 if sqlerrm<>'Sem permissão para editar' then raise; end if;
end;
perform public.reception_action(ticket,'benefit','drink');
update public.team_members set role='admin' where user_id=u;
sale:=public.sell_tickets(gen_random_uuid(),'00000000-0000-4000-8000-000000002026',1,'TESTE PENDENTE','Pendente');
ticket:=(sale->0->>'id')::uuid;
begin
 perform public.reception_action(ticket,'entry','');
 raise exception 'TESTE FALHOU: entrada sem pagamento';
exception when others then
 if sqlerrm<>'Pagamento pendente' then raise; end if;
end;
perform public.reception_action(ticket,'payment','Dinheiro');
perform public.reception_action(ticket,'entry','');
snapshot:=public.reception_list();
if not(snapshot ? 'tickets') then raise exception 'Consulta inválida'; end if;
end $$;
rollback;
