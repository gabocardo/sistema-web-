begin;
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
    perform public.service_action(gen_random_uuid(),'order',jsonb_build_object('ticket_id',p_ticket,'product_id',product.id,'quantity',quantity));
    total := total + product.price * quantity;
  end loop;
  result_data := jsonb_build_object('total',total,'pedido',p_request);
  update public.sale_requests set result=result_data where id=p_request;
  return result_data;
end $$;
revoke all on function public.submit_cart(uuid,uuid,jsonb) from public;
grant execute on function public.submit_cart(uuid,uuid,jsonb) to authenticated;
commit;
