
create or replace function app_private.resolve_fms_posting_account_set(p_tenant_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_id uuid;
  v_count integer;
begin
  select id into v_id
  from public.fms_account_set
  where tenant_id = p_tenant_id
    and status = 'active'
    and is_default
  order by enabled_on, id
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  select count(*)::integer into v_count
  from public.fms_account_set
  where tenant_id = p_tenant_id
    and status = 'active';

  if v_count = 1 then
    select id into v_id
    from public.fms_account_set
    where tenant_id = p_tenant_id
      and status = 'active'
    order by enabled_on, id
    limit 1;
    return v_id;
  end if;

  return null;
end;
$function$;

comment on function app_private.resolve_fms_posting_account_set(uuid) is
  'Resolves the default or sole active account set without relying on unsupported UUID aggregate functions.';
;
