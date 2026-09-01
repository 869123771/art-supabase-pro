-- Connect invoice review and carrier statement confirmation to the shared
-- approval engine. Business tables remain authoritative projections and cannot
-- bypass workflow runtime transitions.

create or replace function app_private.trg_validate_workflow_business_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice record;
  v_statement record;
begin
  if new.business_type = 'tms_invoice' then
    select i.status, i.direction, i.invoice_type, i.invoice_no,
           i.total_amount, i.tenant_id
    into v_invoice
    from public.tms_invoice i
    where i.id = new.business_id
      and i.tenant_id = new.tenant_id
    for update;

    if not found then
      raise exception '发票不存在或无权提交审批';
    end if;
    if v_invoice.status <> 'draft' then
      raise exception '当前发票状态不允许提交审批';
    end if;
    if nullif(btrim(coalesce(v_invoice.invoice_no, '')), '') is null then
      raise exception '提交审批前必须填写发票号码';
    end if;

    new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'direction', v_invoice.direction,
        'invoiceType', v_invoice.invoice_type,
        'invoiceNo', v_invoice.invoice_no,
        'totalAmount', v_invoice.total_amount
      );
  elsif new.business_type = 'tms_carrier_statement' then
    select s.status, s.statement_no, s.statement_amount, s.carrier_id,
           s.tenant_id,
           (
             select count(*)
             from public.tms_carrier_statement_item i
             where i.statement_id = s.id and i.is_active
           ) as active_item_count
    into v_statement
    from public.tms_carrier_statement s
    where s.id = new.business_id
      and s.tenant_id = new.tenant_id
    for update;

    if not found then
      raise exception '承运商对账单不存在或无权提交审批';
    end if;
    if v_statement.status <> 'draft' then
      raise exception '当前承运商对账单状态不允许提交审批';
    end if;
    if coalesce(v_statement.active_item_count, 0) = 0 then
      raise exception '承运商对账单没有有效费用明细，不能提交审批';
    end if;

    new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'statementNo', v_statement.statement_no,
        'statementAmount', v_statement.statement_amount,
        'carrierId', v_statement.carrier_id,
        'costCount', v_statement.active_item_count
      );
  end if;

  return new;
end;
$$;
revoke all on function app_private.trg_validate_workflow_business_start()
  from public, anon, authenticated;
drop trigger if exists wf_instance_validate_business_start on public.wf_instance;
create trigger wf_instance_validate_business_start
before insert on public.wf_instance
for each row execute function app_private.trg_validate_workflow_business_start();
create or replace function app_private.trg_require_workflow_for_finance_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
     and (
       new.status = 'pending_review'
       or old.status = 'pending_review'
     )
     and coalesce(pg_catalog.current_setting('app.workflow_engine', true), '') <> 'on' then
    raise exception '%审批状态必须通过审批中心流转',
      case tg_table_name
        when 'tms_invoice' then '发票'
        when 'tms_carrier_statement' then '承运商对账单'
        else '财务单据'
      end;
  end if;

  return new;
end;
$$;
revoke all on function app_private.trg_require_workflow_for_finance_review()
  from public, anon, authenticated;
drop trigger if exists tms_invoice_require_workflow_review on public.tms_invoice;
create trigger tms_invoice_require_workflow_review
before update of status on public.tms_invoice
for each row execute function app_private.trg_require_workflow_for_finance_review();
drop trigger if exists tms_carrier_statement_require_workflow_review
  on public.tms_carrier_statement;
create trigger tms_carrier_statement_require_workflow_review
before update of status on public.tms_carrier_statement
for each row execute function app_private.trg_require_workflow_for_finance_review();
create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice_direction text;
begin
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);

  if p_business_type = 'tms_waybill_cost' then
    update public.tms_waybill_cost
    set audit_status = case p_status
          when 'running' then 'pending_review'
          when 'approved' then 'approved'
          when 'rejected' then 'rejected'
          when 'withdrawn' then 'draft'
          when 'cancelled' then 'draft'
          else audit_status end,
        submitted_at = case when p_status = 'running' then now() else submitted_at end,
        submitted_by = case when p_status = 'running' then p_actor else submitted_by end,
        reviewed_at = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected') then now()
          else reviewed_at end,
        reviewed_by = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected') then p_actor
          else reviewed_by end,
        review_remark = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'cancelled')
            then nullif(btrim(coalesce(p_comment, '')), '')
          else review_remark end
    where id = p_business_id;

    if not found then raise exception '运单费用不存在或已被删除'; end if;
  elsif p_business_type = 'tms_invoice' then
    select i.direction
    into v_invoice_direction
    from public.tms_invoice i
    where i.id = p_business_id;

    if not found then raise exception '发票不存在或已被删除'; end if;

    update public.tms_invoice
    set status = case p_status
          when 'running' then 'pending_review'
          when 'approved' then case
            when v_invoice_direction = 'output' then 'issued'
            else 'certified'
          end
          when 'rejected' then 'draft'
          when 'withdrawn' then 'draft'
          when 'cancelled' then 'draft'
          else status end,
        submitted_at = case when p_status = 'running' then now() else submitted_at end,
        submitted_by = case when p_status = 'running' then p_actor else submitted_by end,
        reviewed_at = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'withdrawn', 'cancelled') then now()
          else reviewed_at end,
        reviewed_by = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'withdrawn', 'cancelled') then p_actor
          else reviewed_by end,
        review_remark = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'withdrawn', 'cancelled')
            then nullif(btrim(coalesce(p_comment, '')), '')
          else review_remark end
    where id = p_business_id;
  elsif p_business_type = 'tms_carrier_statement' then
    update public.tms_carrier_statement
    set status = case p_status
          when 'running' then 'pending_review'
          when 'approved' then 'confirmed'
          when 'rejected' then 'draft'
          when 'withdrawn' then 'draft'
          when 'cancelled' then 'draft'
          else status end,
        review_remark = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'withdrawn', 'cancelled')
            then nullif(btrim(coalesce(p_comment, '')), '')
          else review_remark end
    where id = p_business_id;

    if not found then raise exception '承运商对账单不存在或已被删除'; end if;
  end if;
end;
$$;
revoke all on function app_private.execute_workflow_business_callback(text, uuid, text, text, text)
  from public, anon, authenticated;
-- The legacy invoice lifecycle RPC remains available only for post-approval
-- voiding. Submission and review actions must use workflow RPCs.
create or replace function public.update_tms_invoice_status(
  p_invoice_id uuid,
  p_action text,
  p_remark text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_invoice public.tms_invoice%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, current_user);
begin
  if p_action in ('submit', 'approve', 'reject') then
    raise exception '发票提交与复核必须通过审批中心流转';
  end if;
  if p_action <> 'void' then
    raise exception '不支持的发票状态操作';
  end if;
  if btrim(coalesce(p_remark, '')) = '' then
    raise exception '作废原因不能为空';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text, 932816));
  select * into v_invoice
  from public.tms_invoice
  where id = p_invoice_id
  for update;

  if not found then raise exception '发票不存在或无权访问'; end if;
  if v_invoice.status not in ('issued', 'certified') then
    raise exception '当前发票状态不允许执行该操作';
  end if;

  update public.tms_invoice
  set status = 'voided',
      voided_at = now(),
      voided_by = v_actor,
      void_reason = btrim(p_remark)
  where id = p_invoice_id;

  return 'voided';
end;
$$;
revoke all on function public.update_tms_invoice_status(uuid, text, text)
  from public, anon;
grant execute on function public.update_tms_invoice_status(uuid, text, text)
  to authenticated, service_role;
-- Seed one publish-ready workflow per business type and tenant. Existing custom
-- definitions are preserved and never overwritten.
do $$
declare
  v_tenant record;
  v_definition_id uuid;
  v_version_id uuid;
  v_config jsonb;
begin
  for v_tenant in
    select t.id,
           coalesce((
             select r.role_code
             from public.sys_role r
             where r.tenant_id = t.id and r.enabled
             order by case when r.role_code in ('R_ADMIN', 'YQ_ADMIN') then 0 else 1 end,
                      r.role_code
             limit 1
           ), 'R_ADMIN') as role_code
    from public.sys_tenant t
    where t.tenant_code <> 'platform'
      and t.status = '1'
  loop
    v_config := jsonb_build_object(
      'nodes', jsonb_build_array(jsonb_build_object(
        'key', 'finance_review',
        'name', '财务复核',
        'order', 1,
        'approvalMode', 'any',
        'allowSelfApproval', false,
        'dueHours', 24,
        'reminderBeforeMinutes', 120,
        'escalationEnabled', true,
        'escalateAfterHours', 4,
        'assignee', jsonb_build_object(
          'type', 'roles',
          'roleCodes', jsonb_build_array(v_tenant.role_code)
        ),
        'condition', jsonb_build_object('operator', 'always')
      ))
    );

    if not exists (
      select 1 from public.wf_definition d
      where d.tenant_id = v_tenant.id
        and d.business_type = 'tms_invoice'
    ) then
      insert into public.wf_definition(
        code, name, business_type, description, status,
        published_at, published_by, tenant_id, create_by, update_by
      ) values (
        'tms-invoice-review', '发票复核', 'tms_invoice',
        '发票提交后由财务角色复核，通过后按发票方向进入已开具或已认证。',
        'published', now(), '624944977@qq.com', v_tenant.id,
        '624944977@qq.com', '624944977@qq.com'
      ) returning id into v_definition_id;

      insert into public.wf_version(
        definition_id, version_no, status, config, change_note,
        published_at, published_by, tenant_id, create_by, update_by
      ) values (
        v_definition_id, 1, 'published', v_config, '系统初始化版本',
        now(), '624944977@qq.com', v_tenant.id,
        '624944977@qq.com', '624944977@qq.com'
      ) returning id into v_version_id;

      update public.wf_definition
      set current_version_id = v_version_id
      where id = v_definition_id;
    end if;

    if not exists (
      select 1 from public.wf_definition d
      where d.tenant_id = v_tenant.id
        and d.business_type = 'tms_carrier_statement'
    ) then
      insert into public.wf_definition(
        code, name, business_type, description, status,
        published_at, published_by, tenant_id, create_by, update_by
      ) values (
        'tms-carrier-statement-review', '承运商结算复核',
        'tms_carrier_statement',
        '承运商对账单提交后由财务角色复核，通过后进入可付款结算状态。',
        'published', now(), '624944977@qq.com', v_tenant.id,
        '624944977@qq.com', '624944977@qq.com'
      ) returning id into v_definition_id;

      insert into public.wf_version(
        definition_id, version_no, status, config, change_note,
        published_at, published_by, tenant_id, create_by, update_by
      ) values (
        v_definition_id, 1, 'published', v_config, '系统初始化版本',
        now(), '624944977@qq.com', v_tenant.id,
        '624944977@qq.com', '624944977@qq.com'
      ) returning id into v_version_id;

      update public.wf_definition
      set current_version_id = v_version_id
      where id = v_definition_id;
    end if;
  end loop;
end;
$$;
with rows(value, label, sort, tag_type) as (values
  ('tms_carrier_statement', '承运商结算', 4, 'warning')
), platform as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dict_type as (
  select id from public.sys_dict_type where code = 'workflowBusinessType' limit 1
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, sort, tag_type,
  tenant_id, create_by, update_by
)
select gen_random_uuid(), dict_type.id, 'workflowBusinessType_' || rows.value,
  '1', rows.value, rows.label, rows.sort, rows.tag_type,
  platform.id, '624944977@qq.com', '624944977@qq.com'
from rows cross join platform cross join dict_type
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id = dict_type.id and d.value = rows.value
);
notify pgrst, 'reload schema';
