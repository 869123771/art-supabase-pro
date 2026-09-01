-- Keep approval delegations single-hop and immutable.
-- A user may receive several delegations, but cannot delegate onward during an
-- overlapping period. This keeps the effective approver and audit chain clear.

create or replace function app_private.trg_guard_workflow_delegation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'UPDATE' then
    if (new.tenant_id, new.delegator_user_id, new.delegate_user_id, new.starts_at, new.ends_at, new.reason)
       is distinct from
       (old.tenant_id, old.delegator_user_id, old.delegate_user_id, old.starts_at, old.ends_at, old.reason) then
      raise exception '已创建的委托主体、时间和原因不可修改；请撤销后重新创建';
    end if;
    return new;
  end if;

  if not exists (
    select 1
    from public.sys_user delegator
    join public.sys_user delegate_user on delegate_user.id = new.delegate_user_id
    where delegator.id = new.delegator_user_id
      and delegator.tenant_id = new.tenant_id
      and delegator.status = '1'
      and delegate_user.tenant_id = new.tenant_id
      and delegate_user.status = '1'
  ) then
    raise exception '委托人或受托人不存在、已停用或不属于当前租户';
  end if;

  if exists (
    select 1
    from public.wf_delegation delegation
    where delegation.tenant_id = new.tenant_id
      and delegation.revoked_at is null
      and tstzrange(delegation.starts_at, delegation.ends_at, '[)')
          && tstzrange(new.starts_at, new.ends_at, '[)')
      and delegation.delegator_user_id = new.delegator_user_id
  ) then
    raise exception '该时间段已存在有效委托，请先调整或撤销原委托';
  end if;

  if exists (
    select 1
    from public.wf_delegation delegation
    where delegation.tenant_id = new.tenant_id
      and delegation.revoked_at is null
      and tstzrange(delegation.starts_at, delegation.ends_at, '[)')
          && tstzrange(new.starts_at, new.ends_at, '[)')
      and (
        delegation.delegate_user_id = new.delegator_user_id
        or delegation.delegator_user_id = new.delegate_user_id
      )
  ) then
    raise exception '委托不允许形成转委托或循环委托，请调整时间或人员';
  end if;

  return new;
end;
$function$;

revoke all on function app_private.trg_guard_workflow_delegation()
  from public, anon, authenticated;
grant execute on function app_private.trg_guard_workflow_delegation()
  to service_role;

create trigger wf_delegation_guard
before insert or update on public.wf_delegation
for each row execute function app_private.trg_guard_workflow_delegation();

comment on function app_private.trg_guard_workflow_delegation() is
  'Enforces same-tenant active users, immutable delegation scope, and single-hop delegation periods.';;
