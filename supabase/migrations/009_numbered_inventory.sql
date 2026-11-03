begin;
lock table public.tickets in access exclusive mode;
alter table public.tickets add column if not exists available boolean not null default false,
 add column if not exists legacy_code text, add column if not exists sold_at timestamptz;
do $$ begin
if (select count(*) from public.tickets)>180 then raise exception 'Mais de 180 convites existentes'; end if;
if exists(select 1 from public.tickets where event_id<>'00000000-0000-4000-8000-000000002026') then raise exception 'Revisar outros eventos';end if;
end $$;
update public.tickets set legacy_code=code,sold_at=created_at where legacy_code is null;
with numbered as(select id,row_number() over(order by created_at,id) as n from public.tickets)
update public.tickets t set code=lpad(n.n::text,4,'0') from numbered n where n.id=t.id;
insert into public.tickets(event_id,code,paid,price,available)
select '00000000-0000-4000-8000-000000002026',lpad(n::text,4,'0'),false,0,true
from generate_series((select count(*)::integer+1 from public.tickets),180)n;
create or replace function public.sell_numbered(p_request uuid,p_ticket uuid,p_type text,p_name text,p_method text,p_phone text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tickets;e public.events;r public.sale_requests;payload jsonb;sale_result jsonb;
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão para vender';end if;
if p_type is null or p_type not in ('antecipado','porta') or p_method is null or p_method not in ('Pendente','Pix','Dinheiro','Cartão') then raise exception 'Venda inválida';end if;
if p_type='porta' and p_method<>'Pendente' then raise exception 'Na porta deve iniciar pendente';end if;
if length(coalesce(p_phone,''))>30 or length(coalesce(p_name,''))>150 then raise exception 'Dados muito longos';end if;
payload:=jsonb_build_object('ticket',p_ticket,'type',p_type,'name',p_name,'method',p_method,'phone',p_phone);
insert into public.sale_requests(id,actor,payload)values(p_request,auth.uid(),payload)on conflict do nothing;
select * into strict r from public.sale_requests where id=p_request for update;
if r.actor<>auth.uid() or r.payload<>payload then raise exception 'Identificador já utilizado';end if;
if r.result is not null then return r.result;end if;
select * into t from public.tickets where id=p_ticket for update;
if not found or not t.available then raise exception 'Convite já vendido ou indisponível. Atualize a lista.';end if;
select * into strict e from public.events where id=t.event_id for share;
update public.tickets set available=false,participant_name=nullif(trim(p_name),''),contact=nullif(trim(p_phone),''),
 sale_type=p_type,price=case when p_type='porta' then e.door_price else e.ticket_price end,
 paid=p_method<>'Pendente',payment_method=nullif(p_method,'Pendente'),sold_by=auth.uid(),sold_at=now()
where id=t.id returning * into t;
insert into public.audit_log(actor,action,ticket_id,details)values(auth.uid(),'sale',t.id,to_jsonb(t));
sale_result:=jsonb_build_array(to_jsonb(t)-'contact');
update public.sale_requests set result=sale_result where id=p_request;
return sale_result;
end $$;
revoke all on function public.sell_numbered(uuid,uuid,text,text,text,text) from public;
grant execute on function public.sell_numbered(uuid,uuid,text,text,text,text) to authenticated;
revoke execute on function public.sell_tickets(uuid,uuid,integer,text,text) from authenticated;
revoke execute on function public.sell_tickets_by_type(uuid,uuid,integer,text,text,text) from authenticated;
create or replace function public.ticket_phone(p_ticket uuid,p_phone text default null)
returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare value text;
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão';end if;
if p_phone is not null then
if length(p_phone)>30 then raise exception 'Telefone muito longo';end if;
update public.tickets set contact=nullif(trim(p_phone),'') where id=p_ticket;
insert into public.audit_log(actor,action,ticket_id)values(auth.uid(),'phone',p_ticket);
end if;
select contact into value from public.tickets where id=p_ticket;
return value;
end $$;
revoke all on function public.ticket_phone(uuid,text) from public;
grant execute on function public.ticket_phone(uuid,text) to authenticated;
create or replace function public.reception_action(p_ticket uuid,p_action text,p_value text default '') returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r text;t public.tickets;stamp timestamptz;
begin
select role into r from public.team_members where user_id=auth.uid();
if r is null then raise exception 'Acesso não autorizado'; end if;
select * into t from public.tickets where id=p_ticket for update;
if not found then raise exception 'Convite não encontrado'; end if;
if t.available then raise exception 'Registre a venda do convite primeiro'; end if; if p_action='entry' then
 if r not in ('admin','entrada') then raise exception 'Sem permissão para entrada'; end if;
 if not t.paid then raise exception 'Pagamento pendente'; end if;
 select entered_at into stamp from public.checkins where ticket_id=t.id;
 if found then return jsonb_build_object('message','Entrada já registrada','at',stamp); end if;
 insert into public.checkins(ticket_id,actor) values(t.id,auth.uid());
elsif p_action='benefit' then
 if not t.paid then raise exception 'Pagamento pendente'; end if;
 if p_value is null or p_value not in ('initial_card','final_card','drink') then raise exception 'Benefício inválido'; end if;
 if r<>'admin' and not (p_value='drink' and r='cozinha') and not (p_value in ('initial_card','final_card') and r in ('entrada','cartelas')) then raise exception 'Sem permissão para esta entrega'; end if;
 select claimed_at into stamp from public.benefit_claims where ticket_id=t.id and benefit=p_value;
 if found then return jsonb_build_object('message','Benefício já retirado','at',stamp); end if;
 insert into public.benefit_claims(ticket_id,benefit,actor) values(t.id,p_value,auth.uid());
elsif p_action='payment' then
 if r not in ('admin','entrada','caixa') then raise exception 'Sem permissão para receber'; end if;
 if t.paid then return jsonb_build_object('message','Convite já pago'); end if;
 if p_value is null or p_value not in ('Pix','Dinheiro','Cartão') then raise exception 'Forma de pagamento inválida'; end if;
 update public.tickets set paid=true,payment_method=p_value where id=t.id;
elsif p_action='name' then
 if r not in ('admin','entrada') then raise exception 'Sem permissão para editar'; end if;
 update public.tickets set participant_name=nullif(trim(p_value),'') where id=t.id;
else raise exception 'Operação desconhecida'; end if;
insert into public.audit_log(actor,action,ticket_id,details) values(auth.uid(),p_action,t.id,jsonb_build_object('before',to_jsonb(t),'value',p_value));
return jsonb_build_object('message','Operação registrada');
end $$;
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
 insert into public.products(id,name,sector,price,round,active) values(coalesce(nullif(p_data->>'id','')::uuid,gen_random_uuid()),trim(p_data->>'name'),p_data->>'sector',(p_data->>'price')::numeric,nullif(p_data->>'round',''),coalesce((p_data->>'active')::boolean,true)) on conflict(id) do update set name=excluded.name,price=excluded.price,sector=excluded.sector,round=excluded.round,active=excluded.active;
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
   if t.closed or exists(select 1 from public.payments where ticket_id=t.id) then raise exception 'Comanda com pagamento: ajuste financeiro necessário'; end if;
   if i.status='cancelado' or (i.status='entregue' and r<>'admin') then raise exception 'Cancelamento não permitido'; end if;
  elsif not ((i.status='recebido' and target in ('em preparo','pronto','entregue')) or (i.status='em preparo' and target in ('pronto','entregue')) or (i.status='pronto' and target='entregue')) then raise exception 'Mudança de situação inválida'; end if;
  update public.items set status=target,reason=case when target='cancelado' then p_data->>'reason' else null end where id=i.id;
 elsif p_action='pay' then
  if r not in ('admin','caixa') then raise exception 'Sem permissão para receber'; end if;
  if t.closed then raise exception 'Comanda encerrada'; end if;
  select coalesce(sum(quantity*price),0) into due from public.items where ticket_id=t.id and status<>'cancelado';
  select coalesce(sum(amount),0) into received from public.payments where ticket_id=t.id;
  due:=due-received;value:=due;
  if due<0 or (p_data->>'amount')::numeric is distinct from due then raise exception 'Valor inválido ou saldo alterado. Atualize a comanda.'; end if;
  if p_data->>'method' is null or p_data->>'method' not in ('Pix','Dinheiro','Cartão') then raise exception 'Forma de pagamento inválida'; end if;
  if value>0 then insert into public.payments(ticket_id,amount,method,actor) values(t.id,value,p_data->>'method',auth.uid()); end if;
  if value=due then update public.tickets set closed=true where id=t.id; end if;
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
