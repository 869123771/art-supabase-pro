-- Keep workflow control-plane operations and forced state overrides restricted to
-- the platform-super account. Tenant users retain tenant-scoped read access and
-- may only perform their own runtime actions (submit, approve, reject, withdraw).
create or replace function app_private.can_manage_workflow()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (select app_private.is_platform_super());
$$;
revoke all on function app_private.can_manage_workflow()
  from public, anon, authenticated;
grant execute on function app_private.can_manage_workflow()
  to authenticated, service_role;
-- The shared immutable-record trigger must branch on the table before reading
-- table-specific columns. wf_action has no status column.
create or replace function app_private.trg_protect_workflow_records()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'wf_action' then
    raise exception '审批动作记录不可修改或删除';
  elsif tg_table_name = 'wf_version' and old.status <> 'draft' then
    if tg_op = 'DELETE'
       or new.definition_id is distinct from old.definition_id
       or new.version_no is distinct from old.version_no
       or new.config is distinct from old.config
       or new.tenant_id is distinct from old.tenant_id
       or not (old.status = 'published' and new.status = 'retired') then
      raise exception '已发布或已归档的流程版本不可修改';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
revoke all on function app_private.trg_protect_workflow_records()
  from public, anon, authenticated;
