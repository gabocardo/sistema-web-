create or replace function public.sell_numbered(p_request uuid,p_ticket uuid,p_type text,p_name text,p_method text,p_phone text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tickets;e public.events;r public.sale_requests;payload jsonb;sale_result jsonb;
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão para vender';end if;
if p_type is null or p_type not in ('antecipado','porta') or p_method is null or p_method not in ('Pix','Dinheiro','Cartão') then raise exception 'Venda inválida';end if;

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
