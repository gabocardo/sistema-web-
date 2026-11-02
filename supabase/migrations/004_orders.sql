begin;
alter table public.tickets add column if not exists closed boolean not null default false;
create table if not exists public.products(id uuid primary key default gen_random_uuid(),name text not null,sector text not null check(sector in ('cartelas','cozinha')),price numeric(12,2) not null check(price>=0),round text,active boolean not null default true);
create table if not exists public.items(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.tickets,product_id uuid not null references public.products,name text not null,sector text not null,round text,quantity integer not null check(quantity between 1 and 100),price numeric(12,2) not null check(price>=0),status text not null default 'recebido' check(status in ('recebido','em preparo','pronto','entregue','cancelado')),created_at timestamptz not null default now(),actor uuid not null references auth.users,reason text);
create table if not exists public.payments(id uuid primary key default gen_random_uuid(),ticket_id uuid not null references public.tickets,amount numeric(12,2) not null check(amount>0),method text not null,created_at timestamptz not null default now(),actor uuid not null references auth.users);
alter table public.products enable row level security;
alter table public.items enable row level security;
alter table public.payments enable row level security;
insert into public.products(name,sector,price,round) select v.* from (values ('Pizza','cozinha',12,null),('Pernil','cozinha',15,null),('Coca-Cola','cozinha',7,null),('Guaraná','cozinha',7,null),('Água','cozinha',4,null),('Suco de uva','cozinha',6,null),('Cerveja','cozinha',8,null),('Picolé','cozinha',4,null),('Cartela inicial','cartelas',10,'Inicial'),('Cartela extra','cartelas',15,'Extra'),('Cartela final','cartelas',20,'Final')) v(name,sector,price,round) where not exists(select 1 from public.products p where p.name=v.name);
create or replace function public.service_list() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
if not exists(select 1 from public.team_members where user_id=auth.uid()) then raise exception 'Acesso não autorizado'; end if;
return jsonb_build_object('products',(select coalesce(jsonb_agg(p),'[]') from public.products p),'items',(select coalesce(jsonb_agg(i),'[]') from public.items i),'payments',(select coalesce(jsonb_agg(p),'[]') from public.payments p));
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
 if p_action='order' then
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
  due:=due-received;value:=(p_data->>'amount')::numeric;
  if value is null or value<0 or value<>round(value,2) or value>due or (value=0 and due>0) then raise exception 'Valor inválido ou saldo alterado. Atualize a comanda.'; end if;
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
revoke all on function public.service_list() from public;
revoke all on function public.service_action(uuid,text,jsonb) from public;
grant execute on function public.service_list() to authenticated;
grant execute on function public.service_action(uuid,text,jsonb) to authenticated;
commit;
