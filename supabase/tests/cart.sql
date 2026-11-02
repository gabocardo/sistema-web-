begin;
do $$
declare
  cashier uuid := gen_random_uuid();
  ticket uuid;
  first_product uuid;
  second_product uuid;
  request_id uuid := gen_random_uuid();
  lines jsonb;
  receipt jsonb;
begin
  insert into auth.users(id) values(cashier);
  insert into public.team_members(user_id,role) values(cashier,'admin');
  perform set_config('request.jwt.claim.sub',cashier::text,true);
  ticket := (public.sell_tickets(gen_random_uuid(),'00000000-0000-4000-8000-000000002026',1,'Teste','Pix')->0->>'id')::uuid;
  insert into public.products(name,sector,price) values('A','cozinha',12) returning id into first_product;
  insert into public.products(name,sector,price) values('B','cozinha',4) returning id into second_product;
  lines := jsonb_build_array(jsonb_build_object('product_id',first_product,'quantity',2,'price',12),jsonb_build_object('product_id',second_product,'quantity',1,'price',4));
  begin
    perform public.submit_cart(gen_random_uuid(),ticket,jsonb_set(lines,'{1,price}','5'));
    raise exception 'Preço alterado passou';
  exception when others then
    if sqlerrm not like 'O catálogo mudou%' then raise; end if;
  end;
  if exists(select 1 from public.items where ticket_id=ticket) then raise exception 'Pedido parcial'; end if;
  receipt := public.submit_cart(request_id,ticket,lines);
  perform public.submit_cart(request_id,ticket,lines);
  if (receipt->>'total')::numeric <> 28 or (select count(*) from public.items where ticket_id=ticket)<>2 then
    raise exception 'Total incorreto ou duplicação';
  end if;
end $$;
rollback;
