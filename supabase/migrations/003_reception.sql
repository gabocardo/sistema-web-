begin;
alter table public.tickets add column if not exists price numeric(12,2) not null default 30;
alter table public.tickets add column if not exists payment_method text;
alter table public.tickets add column if not exists sold_by uuid references auth.users;
alter table public.audit_log add column if not exists details jsonb not null default '{}';
create table if not exists public.sale_requests(id uuid primary key,actor uuid not null references auth.users,payload jsonb not null,result jsonb);
alter table public.sale_requests enable row level security;
insert into public.events(id,name,starts_at,ticket_price) values('00000000-0000-4000-8000-000000002026','Bingo Chatunai','2026-12-05 17:30:00-03',30) on conflict(id) do nothing;
create or replace function public.reception_list() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
if not exists(select 1 from public.team_members where user_id=auth.uid()) then raise exception 'Acesso não autorizado'; end if;
return jsonb_build_object('events',(select coalesce(jsonb_agg(e),'[]') from public.events e),'tickets',(select coalesce(jsonb_agg(to_jsonb(t)-'contact'),'[]') from public.tickets t),'entries',(select coalesce(jsonb_agg(c),'[]') from public.checkins c),'benefits',(select coalesce(jsonb_agg(b),'[]') from public.benefit_claims b));
end $$;
create or replace function public.sell_tickets(p_request uuid,p_event uuid,p_quantity integer,p_name text,p_method text) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare e public.events;t public.tickets;req public.sale_requests;outcome jsonb:='[]';payload_input jsonb;n integer;
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão para vender'; end if;
if p_quantity is null or p_quantity<1 or p_quantity>50 or p_request is null then raise exception 'Quantidade inválida'; end if;
if p_method is null or p_method not in ('Pix','Dinheiro','Cartão','Pendente') then raise exception 'Forma de pagamento inválida'; end if;
payload_input:=jsonb_build_object('event',p_event,'quantity',p_quantity,'name',p_name,'method',p_method);
insert into public.sale_requests(id,actor,payload) values(p_request,auth.uid(),payload_input) on conflict do nothing;
select * into req from public.sale_requests where id=p_request for update;
if req.actor<>auth.uid() or req.payload<>payload_input then raise exception 'Operação já utilizada'; end if;
if req.result is not null then return req.result; end if;
select * into e from public.events where id=p_event for share;
if not found then raise exception 'Evento não encontrado'; end if;
for n in 1..p_quantity loop
insert into public.tickets(event_id,code,participant_name,paid,price,payment_method,sold_by) values(e.id,upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),nullif(trim(p_name),''),p_method<>'Pendente',e.ticket_price,nullif(p_method,'Pendente'),auth.uid()) returning * into t;
insert into public.audit_log(actor,action,ticket_id,details) values(auth.uid(),'sale',t.id,to_jsonb(t));
outcome:=outcome||jsonb_build_array(to_jsonb(t)-'contact');
end loop;
update public.sale_requests set result=outcome where id=p_request;
return outcome;
end $$;
create or replace function public.reception_action(p_ticket uuid,p_action text,p_value text default '') returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare r text;t public.tickets;stamp timestamptz;
begin
select role into r from public.team_members where user_id=auth.uid();
if r is null then raise exception 'Acesso não autorizado'; end if;
select * into t from public.tickets where id=p_ticket for update;
if not found then raise exception 'Convite não encontrado'; end if;
if p_action='entry' then
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
revoke all on function public.reception_list() from public;
revoke all on function public.sell_tickets(uuid,uuid,integer,text,text) from public;
revoke all on function public.reception_action(uuid,text,text) from public;
grant execute on function public.reception_list() to authenticated;
grant execute on function public.sell_tickets(uuid,uuid,integer,text,text) to authenticated;
grant execute on function public.reception_action(uuid,text,text) to authenticated;
commit;
