begin;
alter table public.benefit_claims drop constraint benefit_claims_benefit_check;
alter table public.benefit_claims add constraint benefit_claims_benefit_check check(benefit in ('initial_card','final_card','drink','welcome_kit'));
create function public.claim_welcome_kit(p_ticket uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare t public.tickets;
begin
 if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada','cartelas')) then raise exception 'Sem permissão para entrega'; end if;
 select * into t from public.tickets where id=p_ticket for update;
 if not found or t.available or not t.paid then raise exception 'Convite não vendido ou pagamento pendente'; end if;
 insert into public.benefit_claims(ticket_id,benefit,actor) select t.id,b,auth.uid() from unnest(array['initial_card','final_card','welcome_kit']) b on conflict do nothing;
 insert into public.audit_log(actor,action,ticket_id) values(auth.uid(),'welcome_kit',t.id);
 return jsonb_build_object('message','Kit registrado como entregue');
end $$;
revoke all on function public.claim_welcome_kit(uuid) from public;
grant execute on function public.claim_welcome_kit(uuid) to authenticated;
commit;
