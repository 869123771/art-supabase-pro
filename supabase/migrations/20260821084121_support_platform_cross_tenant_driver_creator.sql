create or replace function app_private.set_tms_carrier_driver_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_user_tenant_id uuid;
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      select user_row.tenant_id
      into v_current_user_tenant_id
      from public.sys_user user_row
      where user_row.id = v_current_user_id;
    end if;

    if v_current_user_id is not null and v_current_user_tenant_id = new.tenant_id then
      new.created_by_user_id := v_current_user_id;
    elsif app_private.is_platform_super() and tg_table_name = 'tms_driver' then
      -- Cross-tenant platform operations retain the real operator in create_by.
      -- Row ownership stays with the selected carrier's tenant-scoped owner so
      -- the existing composite tenant foreign key and ownership model remain intact.
      select carrier_row.created_by_user_id
      into new.created_by_user_id
      from public.tms_carrier carrier_row
      where carrier_row.id = new.carrier_id
        and carrier_row.tenant_id = new.tenant_id;
    elsif v_current_user_id is null and new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      limit 1;
    end if;

    if new.created_by_user_id is null or not exists (
      select 1 from public.sys_user user_row
      where user_row.id = new.created_by_user_id
        and user_row.tenant_id = new.tenant_id
    ) then
      raise exception 'Authenticated carrier or driver creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Record creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function app_private.set_tms_carrier_driver_creator_identity() from public, anon, authenticated;

;
