begin;
do $$
declare u uuid:=gen_random_uuid();tid uuid;pid uuid;iid uuid;req uuid:=gen_random_uuid();sale jsonb;
begin
insert into auth.users(id) values(u);
insert into public.team_members(user_id,role) values(u,'admin');
perform set_config('request.jwt.claim.sub',u::text,true);
sale:=public.sell_tickets(gen_random_uuid(),'00000000-0000-4000-8000-000000002026',1,'TESTE CAIXA','Pix');tid:=(sale->0->>'id')::uuid;
insert into public.products(name,sector,price) values('TESTE PRODUTO','cozinha',12) returning id into pid;
perform public.service_action(req,'order',jsonb_build_object('ticket_id',tid,'product_id',pid,'quantity',2));
perform public.service_action(req,'order',jsonb_build_object('ticket_id',tid,'product_id',pid,'quantity',2));
if (select count(*) from public.items where ticket_id=tid)<>1 then raise exception 'Pedido duplicado'; end if;
select id into iid from public.items where ticket_id=tid;
perform public.service_action(gen_random_uuid(),'pay',jsonb_build_object('ticket_id',tid,'amount',10,'method','Pix'));
if (select closed from public.tickets where id=tid) then raise exception 'Pagamento parcial encerrou comanda'; end if;
req:=gen_random_uuid();
perform public.service_action(req,'pay',jsonb_build_object('ticket_id',tid,'amount',14,'method','Dinheiro'));
perform public.service_action(req,'pay',jsonb_build_object('ticket_id',tid,'amount',14,'method','Dinheiro'));
if (select sum(amount) from public.payments where ticket_id=tid)<>24 then raise exception 'Pagamento duplicado'; end if;
if not (select closed from public.tickets where id=tid) then raise exception 'Comanda não encerrada'; end if;
if (select status from public.items where id=iid)<>'recebido' then raise exception 'Pagamento alterou entrega'; end if;
begin
perform public.service_action(gen_random_uuid(),'order',jsonb_build_object('ticket_id',tid,'product_id',pid,'quantity',1));
raise exception 'TESTE FALHOU: comanda encerrada recebeu item';
exception when others then if sqlerrm<>'Comanda encerrada' then raise; end if; end;
perform public.service_action(gen_random_uuid(),'status',jsonb_build_object('ticket_id',tid,'item_id',iid,'status','entregue'));
if (select status from public.items where id=iid)<>'entregue' then raise exception 'Entrega após pagamento falhou'; end if;
end $$;
rollback;
