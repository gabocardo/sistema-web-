begin;
alter table public.events add column if not exists door_price numeric(12,2) not null default 35 check(door_price>=0);
alter table public.tickets add column if not exists sale_type text check(sale_type in ('antecipado','porta'));
alter table public.items add column if not exists table_number integer check(table_number between 1 and 9999),
  add column if not exists order_id uuid, add column if not exists operator_name text;
create or replace function public.stamp_order() returns trigger language plpgsql security definer set search_path='' as $$
begin
  new.order_id:=coalesce(nullif(current_setting('bingo.order_id',true),'')::uuid,new.id);
  new.table_number:=nullif(current_setting('bingo.table_number',true),'')::integer;
  select left(coalesce(nullif(trim(raw_user_meta_data->>'name'),''),split_part(email,'@',1)),80) into new.operator_name from auth.users where id=new.actor;
  return new;
end $$;
create or replace trigger bingo_stamp_order before insert on public.items for each row execute function public.stamp_order();
update public.items i set operator_name=left(coalesce(nullif(trim(u.raw_user_meta_data->>'name'),''),split_part(u.email,'@',1)),80) from auth.users u where i.actor=u.id and i.operator_name is null;
create or replace function public.sell_tickets_by_type(p_request uuid,p_event uuid,p_quantity integer,p_name text,p_method text,p_type text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.events;t public.tickets;req public.sale_requests;outcome jsonb:='[]';payload_input jsonb;n integer;
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão para vender'; end if;
if p_quantity is null or p_quantity<1 or p_quantity>50 or p_request is null then raise exception 'Quantidade inválida'; end if;
if p_method is null or p_method not in ('Pix','Dinheiro','Cartão','Pendente') then raise exception 'Forma de pagamento inválida'; end if;
if p_type is null or p_type not in ('antecipado','porta') then raise exception 'Tipo de convite inválido'; end if;
payload_input:=jsonb_build_object('event',p_event,'quantity',p_quantity,'name',p_name,'method',p_method,'type',p_type);
insert into public.sale_requests(id,actor,payload) values(p_request,auth.uid(),payload_input) on conflict do nothing;
select * into req from public.sale_requests where id=p_request for update;
if req.actor<>auth.uid() or req.payload<>payload_input then raise exception 'Operação já utilizada'; end if;
if req.result is not null then return req.result; end if;
select * into e from public.events where id=p_event for share;
if not found then raise exception 'Evento não encontrado'; end if;
for n in 1..p_quantity loop
insert into public.tickets(event_id,code,participant_name,paid,sale_type,price,payment_method,sold_by) values(e.id,upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),nullif(trim(p_name),''),p_method<>'Pendente',p_type,case when p_type='porta' then e.door_price else e.ticket_price end,nullif(p_method,'Pendente'),auth.uid()) returning * into t;
insert into public.audit_log(actor,action,ticket_id,details) values(auth.uid(),'sale',t.id,to_jsonb(t));
outcome:=outcome||jsonb_build_array(to_jsonb(t)-'contact');
end loop;
update public.sale_requests set result=outcome where id=p_request;
return outcome;
end $$;

revoke all on function public.sell_tickets_by_type(uuid,uuid,integer,text,text,text) from public;
grant execute on function public.sell_tickets_by_type(uuid,uuid,integer,text,text,text) to authenticated;

create or replace function public.submit_cart(p_request uuid, p_ticket uuid, p_lines jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  payload_input jsonb := jsonb_build_object('action','cart','ticket',p_ticket,'lines',p_lines);
  previous public.sale_requests;
  product public.products;
  line jsonb;
  quantity integer;
  result_data jsonb;
  total numeric := 0;
begin
  if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','cozinha','cartelas')) then
    raise exception 'Sem permissão para lançar pedidos';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' then raise exception 'Pedido inválido'; end if;
  if jsonb_array_length(p_lines) not between 1 and 100 then raise exception 'Selecione de 1 a 100 produtos'; end if;
  if (select count(distinct item->>'product_id') from jsonb_array_elements(p_lines) item) <> jsonb_array_length(p_lines) then
    raise exception 'Produto repetido ou inválido';
  end if;
  insert into public.sale_requests(id,actor,payload) values(p_request,auth.uid(),payload_input) on conflict do nothing;
  select * into strict previous from public.sale_requests where id=p_request for update;
  if previous.actor<>auth.uid() or previous.payload<>payload_input then raise exception 'Pedido divergente'; end if;
  if previous.result is not null then return previous.result; end if;
  perform 1 from public.tickets where id=p_ticket and not closed for update;
  if not found then raise exception 'Comanda indisponível ou encerrada'; end if;
  for line in select value from jsonb_array_elements(p_lines) order by value->>'product_id' loop
    select * into product from public.products where id=(line->>'product_id')::uuid and active for share;
    if not found or product.price is distinct from (line->>'price')::numeric then
      raise exception 'O catálogo mudou. Atualize o pedido para conferir os preços.';
    end if;
    quantity := (line->>'quantity')::integer;
    if quantity is null or quantity not between 1 and 100 then raise exception 'Quantidade inválida'; end if;
    if product.sector='cozinha' and line->>'table_number' is not null and (line->>'table_number') !~ '^[1-9][0-9]{0,3}$' then raise exception 'Número de mesa inválido'; end if;
    perform set_config('bingo.table_number',case when product.sector='cozinha' then coalesce(line->>'table_number','') else '' end,true);
    perform set_config('bingo.order_id',p_request::text,true);
    perform public.service_action(gen_random_uuid(),'order',jsonb_build_object('ticket_id',p_ticket,'product_id',product.id,'quantity',quantity));
    total := total + product.price * quantity;
  end loop;
  result_data := jsonb_build_object('total',total,'pedido',p_request);
  update public.sale_requests set result=result_data where id=p_request;
  return result_data;
end $$;

commit;
