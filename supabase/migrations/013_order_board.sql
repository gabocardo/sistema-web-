begin;
alter table public.products add column requires_preparation boolean not null default true;
update public.products set requires_preparation=false where sector='cartelas' or lower(name) ~ '(picol[eé]|[áa]gua|suco|cerveja|refrigerante|coca|guaran[áa])';
alter table public.items add column requires_preparation boolean not null default true, add column status_changed_at timestamptz not null default now();
update public.items i set requires_preparation=p.requires_preparation,status_changed_at=i.created_at from public.products p where p.id=i.product_id;
create function public.stamp_preparation() returns trigger language plpgsql set search_path=public,pg_temp as $$
begin
 if TG_OP='INSERT' then
  select requires_preparation into new.requires_preparation from public.products where id=new.product_id;
  if not new.requires_preparation and new.status='recebido' then new.status:='pronto'; end if;
  new.status_changed_at:=now();
 elsif new.status is distinct from old.status then new.status_changed_at:=now();
 end if;
 return new;
end $$;
create trigger item_preparation before insert or update on public.items for each row execute function public.stamp_preparation();
create function public.set_product_preparation(p_product uuid,p_required boolean) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not exists(select 1 from public.team_members where user_id=auth.uid() and role='admin') then raise exception 'Apenas administração';end if;
 update public.products set requires_preparation=p_required where id=p_product;
 if not found then raise exception 'Produto não encontrado';end if;
 insert into public.audit_log(actor,action,details) values(auth.uid(),'product_preparation',jsonb_build_object('product',p_product,'required',p_required));
end $$;
revoke all on function public.set_product_preparation(uuid,boolean) from public;
grant execute on function public.set_product_preparation(uuid,boolean) to authenticated;
commit;
