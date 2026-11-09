begin;
lock table public.tickets,public.items,public.payments in share row exclusive mode;
alter table public.items add column paid_amount numeric(12,2) not null default 0 check(paid_amount>=0 and paid_amount<=price*quantity);
-- Existing full settlements can be attributed without guessing which items were paid.
do $$ begin
if exists(select 1 from public.payments p group by ticket_id having sum(amount)<>(select coalesce(sum(price*quantity),0) from public.items i where i.ticket_id=p.ticket_id and status<>'cancelado')) then raise exception 'Pagamento parcial histórico: conciliar antes de migrar';end if;
end $$;
update public.items i set paid_amount=price*quantity where status<>'cancelado' and exists(select 1 from public.payments p where p.ticket_id=i.ticket_id);
create function public.settle_items(p_request uuid,p_ticket uuid,p_items uuid[],p_method text,p_close boolean,p_expected numeric) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tickets;req public.sale_requests;payload jsonb;outcome jsonb;amount_due numeric;ids uuid[];
begin
 if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','caixa')) then raise exception 'Sem permissão para receber';end if;
 if p_request is null or p_close is null or p_method is null or p_method not in ('Pix','Dinheiro','Cartão') then raise exception 'Pagamento inválido';end if;
 payload:=jsonb_build_object('action','settle_items','ticket',p_ticket,'items',p_items,'method',p_method,'close',p_close,'expected',p_expected);
 insert into public.sale_requests(id,actor,payload)values(p_request,auth.uid(),payload)on conflict do nothing;
 select * into strict req from public.sale_requests where id=p_request for update;
 if req.actor<>auth.uid() or req.payload<>payload then raise exception 'Identificador já utilizado';end if;
 if req.result is not null then return req.result;end if;
 select * into t from public.tickets where id=p_ticket for update;
 if not found or t.available or t.closed then raise exception 'Comanda indisponível ou encerrada';end if;
 if p_close then
  select coalesce(array_agg(id),'{}'::uuid[]) into ids from public.items where ticket_id=t.id and status<>'cancelado' and paid_amount<price*quantity;
 else
  ids:=p_items;
  if coalesce(cardinality(ids),0)=0 or cardinality(ids)<>(select count(distinct x) from unnest(ids)x) then raise exception 'Selecione itens válidos';end if;
  if cardinality(ids)<>(select count(*) from public.items where id=any(ids) and ticket_id=t.id and status<>'cancelado' and paid_amount<price*quantity) then raise exception 'Item já pago ou indisponível. Atualize a comanda.';end if;
 end if;
 select coalesce(sum(price*quantity-paid_amount),0) into amount_due from public.items where id=any(ids);
 if p_expected is distinct from amount_due then raise exception 'Saldo alterado. Atualize a comanda antes de receber.';end if;
 if amount_due>0 then insert into public.payments(ticket_id,amount,method,actor)values(t.id,amount_due,p_method,auth.uid());end if;
 update public.items set paid_amount=price*quantity where id=any(ids);
 if p_close then update public.tickets set closed=true where id=t.id;end if;
 insert into public.audit_log(actor,action,ticket_id,details)values(auth.uid(),'settle_items',t.id,payload||jsonb_build_object('settled_items',ids,'amount',amount_due));
 outcome:=jsonb_build_object('message',case when p_close then 'Comanda encerrada' else 'Itens pagos. Comanda continua aberta.' end,'amount',amount_due);
 update public.sale_requests set result=outcome where id=p_request;
 return outcome;
end $$;
revoke all on function public.settle_items(uuid,uuid,uuid[],text,boolean,numeric) from public;
grant execute on function public.settle_items(uuid,uuid,uuid[],text,boolean,numeric) to authenticated;

create or replace function public.service_action(p_request uuid,p_action text,p_data jsonb) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r text; t public.tickets;p public.products;i public.items;req public.sale_requests;input jsonb;outcome jsonb;due numeric;received numeric;value numeric;target text;
begin
select role into r from public.team_members where user_id=auth.uid();
if r is null then raise exception 'Acesso não autorizado'; end if;
input:=jsonb_build_object('action',p_action,'data',p_data);
insert into public.sale_requests(id,actor,payload) values(p_request,auth.uid(),input) on conflict do nothing;
select * into req from public.sale_requests where id=p_request for update;
if req.actor<>auth.uid() or req.payload<>input then raise exception 'Identificador já utilizado'; end if;
if req.result is not null then return req.result; end if;
if p_action='product' then
 if r<>'admin' then raise exception 'Apenas administração'; end if;
 if nullif(trim(p_data->>'name'),'') is null then raise exception 'Informe o nome'; end if;
 insert into public.products(id,name,sector,price,round,active,requires_preparation) values(coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid()),trim(p_data->>'name'),p_data->>'sector',(p_data->>'price')::numeric,nullif(p_data->>'round',''),coalesce((p_data->>'active')::boolean,true),coalesce((p_data->>'requires_preparation')::boolean,p_data->>'sector'='cozinha')) on conflict(id) do update set name=excluded.name,price=excluded.price,sector=excluded.sector,round=excluded.round,active=excluded.active;
else
 select * into t from public.tickets where id=(p_data->>'ticket_id')::uuid for update;
 if not found then raise exception 'Convite não encontrado'; end if;
 if t.available then raise exception 'Registre a venda do convite primeiro'; end if; if p_action='order' then
  if t.closed then raise exception 'Comanda encerrada'; end if;
  select * into p from public.products where id=(p_data->>'product_id')::uuid and active for share;
  if not found then raise exception 'Produto indisponível'; end if;
  if r<>'admin' and r<>p.sector then raise exception 'Sem permissão para este setor'; end if;
  insert into public.items(ticket_id,product_id,name,sector,round,quantity,price,actor) values(t.id,p.id,p.name,p.sector,p.round,(p_data->>'quantity')::integer,p.price,auth.uid());
 elsif p_action='status' then
  select * into i from public.items where id=(p_data->>'item_id')::uuid and ticket_id=t.id for update;
  if not found then raise exception 'Pedido não encontrado'; end if;
  if r<>'admin' and r<>i.sector then raise exception 'Sem permissão para este setor'; end if;
  target:=p_data->>'status';
  if target='cancelado' then
   if nullif(trim(p_data->>'reason'),'') is null then raise exception 'Informe o motivo'; end if;
   if t.closed or i.paid_amount>0 then raise exception 'Comanda com pagamento: ajuste financeiro necessário'; end if;
   if i.status='cancelado' or (i.status='entregue' and r<>'admin') then raise exception 'Cancelamento não permitido'; end if;
  elsif not ((i.status='recebido' and target in ('em preparo','pronto','entregue')) or (i.status='em preparo' and target in ('pronto','entregue')) or (i.status='pronto' and target='entregue')) then raise exception 'Mudança de situação inválida'; end if;
  update public.items set status=target,reason=case when target='cancelado' then p_data->>'reason' else null end where id=i.id;
 elsif p_action='pay' then
  raise exception 'Atualize o site e utilize o pagamento por itens';
 elsif p_action='reopen' then
  if r<>'admin' then raise exception 'Apenas administração'; end if;
  if nullif(trim(p_data->>'reason'),'') is null then raise exception 'Informe o motivo'; end if;
  update public.tickets set closed=false where id=t.id;
 else raise exception 'Operação desconhecida'; end if;
end if;
insert into public.audit_log(actor,action,ticket_id,details) values(auth.uid(),p_action,t.id,jsonb_build_object('input',p_data,'item_before',to_jsonb(i),'ticket_before',to_jsonb(t)));
outcome:=jsonb_build_object('message','Operação registrada');
update public.sale_requests set result=outcome where id=p_request;
return outcome;
end $$;
commit;
