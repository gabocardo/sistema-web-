create or replace function public.ticket_phones() returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
begin
if not exists(select 1 from public.team_members where user_id=auth.uid() and role in ('admin','entrada')) then raise exception 'Sem permissão';end if;
return (select coalesce(jsonb_object_agg(id,contact),'{}') from public.tickets where contact is not null);
end $$;
revoke all on function public.ticket_phones() from public;
grant execute on function public.ticket_phones() to authenticated;
