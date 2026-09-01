-- Published workflow versions remain immutable, but deleting an entire
-- definition with no workflow history must be allowed to cascade through its
-- versions. The definition delete boundary is restricted to platform-super
-- accounts and already refuses definitions referenced by workflow instances.
create or replace function app_private.trg_protect_workflow_records()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_table_name = 'wf_action' then
    raise exception '审批动作记录不可修改或删除';
  end if;

  if tg_table_name = 'wf_version' then
    if tg_op = 'DELETE' then
      -- During an ON DELETE CASCADE, the parent definition is already absent
      -- from the deleting statement's snapshot. Direct version deletion still
      -- sees the parent and remains blocked.
      if not exists (
        select 1
        from public.wf_definition d
        where d.id = old.definition_id
      ) then
        return old;
      end if;

      if old.status <> 'draft' then
        raise exception '已发布或已归档的流程版本不可修改';
      end if;
    elsif old.status <> 'draft'
      and (
        new.definition_id is distinct from old.definition_id
        or new.version_no is distinct from old.version_no
        or new.config is distinct from old.config
        or new.tenant_id is distinct from old.tenant_id
        or not (old.status = 'published' and new.status = 'retired')
      ) then
      raise exception '已发布或已归档的流程版本不可修改';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

revoke all on function app_private.trg_protect_workflow_records()
  from public, anon, authenticated;;
