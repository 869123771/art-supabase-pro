begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(94);

-- Structural and authorization contract.
select has_table('public', 'wf_definition', 'workflow definition table exists');
select has_table('public', 'wf_version', 'workflow version table exists');
select has_table('public', 'wf_instance', 'workflow instance table exists');
select has_table('public', 'wf_task', 'workflow task table exists');
select has_table('public', 'wf_action', 'workflow action table exists');
select has_table('public', 'wf_task_reminder_event', 'workflow reminder ledger exists');
select has_table('public', 'wf_delegation', 'workflow delegation table exists');

create temp table reimbursement_workflow_guard_probe(status text);
create trigger reimbursement_workflow_guard_probe_trigger
before update on reimbursement_workflow_guard_probe
for each row execute function app_private.trg_guard_tms_expense_workflow_state();
insert into reimbursement_workflow_guard_probe(status) values ('draft');
select throws_ok(
  $$update reimbursement_workflow_guard_probe set status='pending_review'$$,
  'P0001',
  '费用审批状态必须通过审批中心或出纳支付流程流转',
  'shared expense workflow guard reads status-based records safely'
);
drop table reimbursement_workflow_guard_probe;

create temp table tms_in_transit_expense(report_status text);
create trigger in_transit_expense_workflow_guard_probe_trigger
before update on tms_in_transit_expense
for each row execute function app_private.trg_guard_tms_expense_workflow_state();
insert into tms_in_transit_expense(report_status) values ('draft');
select throws_ok(
  $$update tms_in_transit_expense set report_status='pending_review'$$,
  'P0001',
  '费用审批状态必须通过审批中心或出纳支付流程流转',
  'shared expense workflow guard reads report-status records safely'
);
drop table tms_in_transit_expense;

select ok(
  (select relrowsecurity from pg_class where oid='public.wf_delegation'::regclass),
  'workflow delegations enforce RLS'
);
select has_column(
  'public', 'wf_task', 'original_assignee_user_id',
  'workflow tasks preserve the original approval seat'
);
select has_column(
  'public', 'wf_task', 'assignment_source',
  'workflow tasks record how the effective assignee was selected'
);
select has_column(
  'public', 'wf_task', 'delegation_id',
  'workflow tasks link back to their delegation'
);

select ok(
  not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname in (
        'wf_definition', 'wf_version', 'wf_instance', 'wf_task', 'wf_action',
        'wf_task_reminder_event'
      )
      and not c.relrowsecurity
  ),
  'RLS is enabled on every exposed workflow table'
);

select ok(
  not has_function_privilege(
    'anon', 'public.start_workflow(text,uuid,text,jsonb,text)', 'execute'
  ),
  'anonymous users cannot start workflows'
);
select ok(
  not has_function_privilege(
    'anon', 'public.act_workflow_task(uuid,text,text,text)', 'execute'
  ),
  'anonymous users cannot act on workflow tasks'
);
select ok(
  not has_function_privilege(
    'anon', 'public.cancel_workflow_instance(uuid,text,text)', 'execute'
  ),
  'anonymous users cannot cancel workflow instances'
);
select ok(
  not has_function_privilege(
    'anon', 'public.create_workflow_delegation(uuid,timestamptz,timestamptz,text)', 'execute'
  ),
  'anonymous users cannot create workflow delegations'
);
select ok(
  not has_function_privilege(
    'anon', 'public.revoke_workflow_delegation(uuid,text)', 'execute'
  ),
  'anonymous users cannot revoke workflow delegations'
);
select ok(
  not has_function_privilege(
    'anon', 'public.transfer_workflow_task(uuid,uuid,text,text)', 'execute'
  ),
  'anonymous users cannot transfer workflow tasks'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.start_workflow(text,uuid,text,jsonb,text)', 'execute'
  ),
  'authenticated users can call the workflow start boundary'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.act_workflow_task(uuid,text,text,text)', 'execute'
  ),
  'authenticated users can call the task action boundary'
);
select ok(
  has_function_privilege(
    'authenticated',
    'public.create_workflow_delegation(uuid,timestamptz,timestamptz,text)',
    'execute'
  ),
  'authenticated users can create their own workflow delegations'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.transfer_workflow_task(uuid,uuid,text,text)', 'execute'
  ),
  'authenticated users can call the audited task transfer boundary'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.get_workflow_operational_analytics(integer)', 'execute'
  ),
  'authenticated users can read tenant-safe workflow analytics'
);
select ok(
  not has_function_privilege(
    'anon', 'public.get_workflow_business_snapshot(uuid)', 'execute'
  ),
  'anonymous users cannot read workflow business snapshots'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.get_workflow_business_snapshot(uuid)', 'execute'
  ),
  'authenticated users can call the guarded business snapshot boundary'
);
select ok(
  not (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'get_workflow_business_snapshot'
  ),
  'the exposed business snapshot wrapper is security invoker'
);
select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'app_private'
      and p.proname = 'get_workflow_business_snapshot'
  ),
  'the elevated business snapshot implementation stays private'
);
select ok(
  not has_function_privilege(
    'authenticated', 'app_private.process_workflow_task_reminders(integer)', 'execute'
  ),
  'authenticated users cannot invoke the private scheduler'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_instance_one_running_business_idx'
  ),
  'one-running-instance partial unique index exists'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_action_idempotency_idx'
  ),
  'workflow action idempotency index exists'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_delegation_delegate_user_id_idx'
  ),
  'workflow delegation delegate lookup is indexed'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_delegation_delegator_user_id_idx'
  ),
  'workflow delegation delegator lookup is indexed'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_delegation_revoked_by_idx'
  ),
  'workflow delegation revoker lookup is indexed'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'wf_task_last_assigned_by_idx'
  ),
  'workflow task reassignment operator lookup is indexed'
);
select ok(
  position(
    $transition$old.audit_status = 'pending_review' and new.audit_status in ('approved', 'rejected', 'draft')$transition$
    in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'trg_validate_tms_waybill_cost'
    )
  ) > 0,
  'workflow cancellation can restore a pending waybill cost to draft'
);
select ok(
  not exists (
    select 1 from public.wf_definition
    where status = 'published' and current_version_id is null
  ),
  'published workflows always point to a published version'
);
select ok(
  exists (
    select 1 from cron.job
    where jobname = 'workflow-task-reminders' and active
  ),
  'workflow reminder cron job is active'
);

select lives_ok(
  $$
    select app_private.validate_workflow_config(
      '{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":24,"reminderBeforeMinutes":60,"escalationEnabled":true,"escalateAfterHours":4,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}'::jsonb
    )
  $$,
  'valid workflow SLA configuration is accepted'
);
select throws_ok(
  $$
    select app_private.validate_workflow_config(
      '{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":0,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}'::jsonb
    )
  $$,
  'P0001',
  '节点 Review 的审批时限必须在 1 到 720 小时之间',
  'invalid zero-hour task SLA is rejected'
);
select throws_ok(
  $$
    select app_private.validate_workflow_config(
      '{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":1,"reminderBeforeMinutes":120,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}'::jsonb
    )
  $$,
  'P0001',
  '节点 Review 的到期前提醒不能超过审批时限',
  'reminder lead time cannot exceed the task SLA'
);

select lives_ok(
  format(
    'select app_private.validate_workflow_business_config(%L,%L::jsonb)',
    contract.business_type,
    jsonb_build_object(
      'nodes', jsonb_build_array(jsonb_build_object(
        'key','review','name','Review','order',1,
        'approvalMode','any','approvalThresholdPercent',1,'rejectVetoEnabled',true,
        'allowSelfApproval',false,'dueHours',24,'reminderBeforeMinutes',60,
        'escalationEnabled',true,'escalateAfterHours',4,
        'assignee',jsonb_build_object('type','initiator'),
        'condition',jsonb_build_object('field',contract.field_name,'operator','not_empty')
      ))
    )::text
  ),
  contract.business_type || ' accepts its server-owned condition field'
)
from (values
  ('tms_waybill_cost','amount'),
  ('tms_invoice','totalAmount'),
  ('tms_carrier_statement','statementAmount'),
  ('tms_customer_statement','statementAmount'),
  ('tms_contract','contractAmount'),
  ('vehicle_archive','plateNo')
) contract(business_type,field_name);

select throws_ok(
  $$
    select app_private.validate_workflow_business_config(
      'tms_contract',
      '{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","approvalThresholdPercent":1,"rejectVetoEnabled":true,"allowSelfApproval":false,"dueHours":24,"reminderBeforeMinutes":60,"escalationEnabled":true,"escalateAfterHours":4,"assignee":{"type":"initiator"},"condition":{"field":"clientInjectedField","operator":"not_empty"}}]}'::jsonb
    )
  $$,
  'P0001',
  '节点“Review”使用了业务类型 tms_contract 不支持的条件字段 clientInjectedField',
  'business workflow conditions reject fields that are not server owned'
);

-- Isolated tenant, auth, user, definition, and version fixtures.
insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by)
values
  ('a1000000-0000-4000-8000-000000000001', 'workflow-pgtap-a', 'Workflow pgTAP A', '1', 'pgtap', 'pgtap'),
  ('b1000000-0000-4000-8000-000000000001', 'workflow-pgtap-b', 'Workflow pgTAP B', '1', 'pgtap', 'pgtap')
on conflict (tenant_code) do nothing;

insert into public.sys_tenant(id, tenant_code, tenant_name, status, create_by, update_by)
values ('c1000000-0000-4000-8000-000000000001', 'platform', 'Platform', '1', 'pgtap', 'pgtap')
on conflict (tenant_code) do nothing;

insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
values
  ('a2000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'workflow-pgtap-initiator@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('a2000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'workflow-pgtap-approver1@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('a2000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'workflow-pgtap-approver2@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('b2000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'workflow-pgtap-outsider@example.invalid', '', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now())
on conflict (id) do nothing;

do $$
declare
  v_platform_tenant_id uuid;
  v_super_auth_user_id uuid;
begin
  select id into v_platform_tenant_id
  from public.sys_tenant where tenant_code = 'platform';

  select id into v_super_auth_user_id
  from auth.users where lower(email) = '869123771@qq.com' limit 1;

  if v_super_auth_user_id is null then
    v_super_auth_user_id := 'c2000000-0000-4000-8000-000000000001';
    insert into auth.users(
      id, aud, role, email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values (
      v_super_auth_user_id, 'authenticated', 'authenticated', '869123771@qq.com', '', now(),
      '{"provider":"email","providers":["email"]}', '{}', now(), now()
    );
  end if;

  if not exists (select 1 from public.sys_user where lower(user_email) = '869123771@qq.com') then
    insert into public.sys_user(
      id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
      tenant_id, user_type, create_by, update_by
    ) values (
      'c3000000-0000-4000-8000-000000000001', 'workflow-pgtap-super', 'Workflow pgTAP Super',
      '869123771@qq.com', '1', array['R_SUPER']::text[], v_super_auth_user_id,
      v_platform_tenant_id, '1', 'pgtap', 'pgtap'
    );
  end if;
end;
$$;

insert into public.sys_user(
  id, user_name, nick_name, user_email, status, user_roles, auth_user_id,
  tenant_id, user_type, create_by, update_by
)
values
  ('a3000000-0000-4000-8000-000000000001', 'workflow-pgtap-initiator', 'Test Initiator', 'workflow-pgtap-initiator@example.invalid', '1', array['R_REGISTER']::text[], 'a2000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', '2', 'pgtap', 'pgtap'),
  ('a3000000-0000-4000-8000-000000000002', 'workflow-pgtap-approver1', 'Test Approver 1', 'workflow-pgtap-approver1@example.invalid', '1', array['R_ADMIN']::text[], 'a2000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', '1', 'pgtap', 'pgtap'),
  ('a3000000-0000-4000-8000-000000000003', 'workflow-pgtap-approver2', 'Test Approver 2', 'workflow-pgtap-approver2@example.invalid', '1', array['R_REGISTER']::text[], 'a2000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000001', '2', 'pgtap', 'pgtap'),
  ('b3000000-0000-4000-8000-000000000001', 'workflow-pgtap-outsider', 'Test Outsider', 'workflow-pgtap-outsider@example.invalid', '1', array['R_REGISTER']::text[], 'b2000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', '2', 'pgtap', 'pgtap');

insert into public.wf_definition(
  id, code, name, business_type, description, status, tenant_id, create_by, update_by
)
values
  ('a4000000-0000-4000-8000-000000000001', 'workflow_pgtap_any', 'Workflow pgTAP Any', 'workflow_test_any', 'pgTAP any approval', 'published', 'a1000000-0000-4000-8000-000000000001', 'pgtap', 'pgtap'),
  ('a4000000-0000-4000-8000-000000000002', 'workflow_pgtap_all', 'Workflow pgTAP All', 'workflow_test_all', 'pgTAP all approval', 'published', 'a1000000-0000-4000-8000-000000000001', 'pgtap', 'pgtap');

insert into public.wf_version(
  id, definition_id, version_no, status, config, change_note, published_at,
  published_by, tenant_id, create_by, update_by
)
values
  (
    'a5000000-0000-4000-8000-000000000001',
    'a4000000-0000-4000-8000-000000000001', 1, 'published',
    '{"nodes":[{"key":"review","name":"Any review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":24,"reminderBeforeMinutes":60,"escalationEnabled":true,"escalateAfterHours":4,"assignee":{"type":"users","userIds":["a3000000-0000-4000-8000-000000000002","a3000000-0000-4000-8000-000000000003"]},"condition":{"operator":"always"}}]}'::jsonb,
    'pgTAP fixture', now(), 'pgtap', 'a1000000-0000-4000-8000-000000000001', 'pgtap', 'pgtap'
  ),
  (
    'a5000000-0000-4000-8000-000000000002',
    'a4000000-0000-4000-8000-000000000002', 1, 'published',
    '{"nodes":[{"key":"review","name":"All review","order":1,"approvalMode":"all","allowSelfApproval":false,"dueHours":24,"reminderBeforeMinutes":60,"escalationEnabled":true,"escalateAfterHours":4,"assignee":{"type":"users","userIds":["a3000000-0000-4000-8000-000000000002","a3000000-0000-4000-8000-000000000003"]},"condition":{"operator":"always"}}]}'::jsonb,
    'pgTAP fixture', now(), 'pgtap', 'a1000000-0000-4000-8000-000000000001', 'pgtap', 'pgtap'
  );

update public.wf_definition
set current_version_id = case id
  when 'a4000000-0000-4000-8000-000000000001' then 'a5000000-0000-4000-8000-000000000001'::uuid
  else 'a5000000-0000-4000-8000-000000000002'::uuid
end,
published_at = now(),
published_by = 'pgtap'
where id in (
  'a4000000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-000000000002'
);

-- Initiator: start and idempotency.
set local role authenticated;
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-initiator@example.invalid","role":"authenticated"}';

select lives_ok(
  $$select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000001','Any approval','{}'::jsonb,'start-any-1')$$,
  'initiator can start a published workflow'
);
select is(
  (select status from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'),
  'running',
  'new workflow instance is running'
);
select is(
  (select count(*) from public.wf_task where instance_id = (
    select id from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'
  ) and status = 'pending'),
  2::bigint,
  'any-approval node creates one pending task per assignee'
);
select is(
  public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000001','Any approval','{}'::jsonb,'start-any-1'),
  (select id from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'),
  'repeated workflow start returns the existing running instance'
);
select is(
  (select count(*) from public.wf_action where instance_id = (
    select id from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'
  ) and action = 'submit'),
  1::bigint,
  'idempotent start creates one submit action'
);

-- Any approval: one approval completes the node and repeated keys are idempotent.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000002","email":"workflow-pgtap-approver1@example.invalid","role":"authenticated"}';

select lives_ok(
  $$select public.act_workflow_task(
    (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000001') and assignee_user_id='a3000000-0000-4000-8000-000000000002'),
    'approve','approved by pgTAP','act-any-1'
  )$$,
  'assigned approver can approve a pending task'
);
select is(
  (select status from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'),
  'approved',
  'any approval completes the workflow instance'
);
select is(
  (select count(*) from public.wf_task where instance_id = (
    select id from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'
  ) and status = 'cancelled'),
  1::bigint,
  'any approval cancels the sibling pending task'
);
select is(
  public.act_workflow_task(
    (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000001') and assignee_user_id='a3000000-0000-4000-8000-000000000002'),
    'approve','replayed approval','act-any-1'
  ),
  (select id from public.wf_instance where business_id = 'a6000000-0000-4000-8000-000000000001'),
  'replayed task action returns the original instance'
);
select is(
  (select count(*) from public.wf_action where idempotency_key = 'act-any-1'),
  1::bigint,
  'replayed task action does not duplicate the audit record'
);

-- Withdraw before any approver has acted.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-initiator@example.invalid","role":"authenticated"}';
select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000002','Withdraw approval','{}'::jsonb,'start-withdraw-1');
select lives_ok(
  $$select public.withdraw_workflow(
    (select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000002'),
    'withdrawn by pgTAP'
  )$$,
  'initiator can withdraw before a task is handled'
);
select ok(
  (select status = 'withdrawn' from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000002')
  and not exists (
    select 1 from public.wf_task
    where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000002')
      and status='pending'
  ),
  'withdraw closes the instance and every pending task'
);

-- Reject requires a reason and closes the instance.
select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000003','Reject approval','{}'::jsonb,'start-reject-1');
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000003","email":"workflow-pgtap-approver2@example.invalid","role":"authenticated"}';
select throws_ok(
  $$select public.act_workflow_task(
    (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000003') and assignee_user_id='a3000000-0000-4000-8000-000000000003'),
    'reject','', 'act-reject-empty'
  )$$,
  'P0001',
  '驳回时必须填写原因',
  'rejecting without a reason is blocked'
);
select lives_ok(
  $$select public.act_workflow_task(
    (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000003') and assignee_user_id='a3000000-0000-4000-8000-000000000003'),
    'reject','insufficient evidence', 'act-reject-1'
  )$$,
  'assigned approver can reject with a reason'
);
select is(
  (select status from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000003'),
  'rejected',
  'reject action closes the workflow as rejected'
);

-- All approval: every assigned approver must approve.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-initiator@example.invalid","role":"authenticated"}';
select public.start_workflow('workflow_test_all','a6000000-0000-4000-8000-000000000004','All approval','{}'::jsonb,'start-all-1');
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000002","email":"workflow-pgtap-approver1@example.invalid","role":"authenticated"}';
select public.act_workflow_task(
  (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000004') and assignee_user_id='a3000000-0000-4000-8000-000000000002'),
  'approve','first approval','act-all-1'
);
select ok(
  (select status='running' from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000004')
  and (select count(*)=1 from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000004') and status='pending'),
  'all approval remains running until every approver acts'
);
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000003';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000003","email":"workflow-pgtap-approver2@example.invalid","role":"authenticated"}';
select public.act_workflow_task(
  (select id from public.wf_task where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000004') and assignee_user_id='a3000000-0000-4000-8000-000000000003'),
  'approve','second approval','act-all-2'
);
select is(
  (select status from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000004'),
  'approved',
  'all approval completes after the final approver acts'
);

-- Cross-tenant RLS and negative RPC authorization.
set local "request.jwt.claim.sub" = 'b2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"b2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-outsider@example.invalid","role":"authenticated"}';
select is(
  (select count(*) from public.wf_instance where tenant_id='a1000000-0000-4000-8000-000000000001'),
  0::bigint,
  'ordinary users cannot read another tenant workflow instances'
);
select throws_ok(
  $$select public.act_workflow_task(
    (select id from public.wf_task where tenant_id='a1000000-0000-4000-8000-000000000001' limit 1),
    'approve','cross tenant attack','cross-tenant-act'
  )$$,
  '42501',
  '待办不存在或当前用户不是审批人',
  'cross-tenant users cannot act on another tenant task'
);
select lives_ok(
  $$select public.get_workflow_monitor_summary()$$,
  'ordinary users can access tenant-scoped read-only approval monitoring'
);

-- Control-plane writes and workflow-state overrides require platform-super authorization.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000002","email":"workflow-pgtap-approver1@example.invalid","role":"authenticated"}';
select throws_ok(
  $$select public.save_workflow_definition(
    '{"code":"tenant_admin_must_not_write","name":"Blocked admin definition","businessType":"blocked_admin_business","config":{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":24,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}}'::jsonb
  )$$,
  '42501',
  '当前账号没有流程配置权限',
  'tenant administrators cannot create workflow definitions'
);

set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-initiator@example.invalid","role":"authenticated"}';
select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000005','Admin cancel target','{}'::jsonb,'start-admin-cancel');
select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000006','Super cancel target','{}'::jsonb,'start-super-cancel');

set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000002","email":"workflow-pgtap-approver1@example.invalid","role":"authenticated"}';
select throws_ok(
  $$select public.cancel_workflow_instance(
    (select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000005'),
    'tenant admin must not cancel', 'admin-cancel-blocked'
  )$$,
  '42501',
  '仅平台超级管理员可以终止审批流程',
  'tenant administrators cannot force-cancel workflow instances'
);

reset role;
do $$
declare
  v_super_auth_user_id uuid;
begin
  select u.auth_user_id into v_super_auth_user_id
  from public.sys_user u where lower(u.user_email) = '869123771@qq.com' limit 1;
  perform set_config('request.jwt.claim.sub', v_super_auth_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_super_auth_user_id, 'email', '869123771@qq.com', 'role', 'authenticated')::text,
    true
  );
end;
$$;
select lives_ok(
  $$select public.cancel_workflow_instance(
    (select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000006'),
    'platform super cancellation', 'super-cancel-1'
  )$$,
  'platform super can cancel an instance across tenant boundaries'
);
select ok(
  (select status='cancelled' from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000006')
  and not exists (
    select 1 from public.wf_task
    where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000006')
      and status='pending'
  ),
  'platform-super cancellation closes the instance and pending tasks'
);
select is(
  public.cancel_workflow_instance(
    (select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000006'),
    'platform super cancellation replay', 'super-cancel-1'
  ),
  (select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000006'),
  'platform-super cancellation is idempotent'
);
select is(
  (select count(*) from public.wf_action where idempotency_key='super-cancel-1'),
  1::bigint,
  'idempotent cancellation writes one immutable audit action'
);

-- Scheduler generation, delivery, and automatic notification closure.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-initiator@example.invalid","role":"authenticated"}';
select public.start_workflow('workflow_test_any','a6000000-0000-4000-8000-000000000007','Reminder target','{}'::jsonb,'start-reminder');
reset role;
update public.wf_task
set due_at = now() - interval '5 hours'
where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000007');
select app_private.process_workflow_task_reminders(50);

select is(
  (select count(*) from public.wf_task_reminder_event
   where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000007')
     and status='delivered'),
  4::bigint,
  'scheduler delivers overdue and manager escalation events for each task'
);
select is(
  (select count(*) from public.sys_notification
   where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000007')
     and source_type in ('workflow_task_overdue','workflow_task_manager_escalation')),
  4::bigint,
  'scheduler creates assignee and manager notifications exactly once'
);

update public.wf_task
set status='cancelled', handled_at=now(), comment='pgTAP scheduler cleanup'
where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000007')
  and status='pending';
select is(
  (select count(*) from public.sys_notification
   where instance_id=(select id from public.wf_instance where business_id='a6000000-0000-4000-8000-000000000007')
     and source_type in (
       'workflow_task','workflow_task_due_soon','workflow_task_overdue',
       'workflow_task_manager_escalation'
     )
     and not is_read),
  0::bigint,
  'closing tasks automatically archives all related reminders'
);

select throws_ok(
  $$update public.wf_action set comment='tampered' where idempotency_key='super-cancel-1'$$,
  'P0001',
  '审批动作记录不可修改或删除',
  'workflow audit actions are immutable'
);
select throws_ok(
  $$update public.wf_version set config='{"nodes":[]}'::jsonb where id='a5000000-0000-4000-8000-000000000001'$$,
  'P0001',
  '已发布或已归档的流程版本不可修改',
  'published workflow versions are immutable'
);

-- Transactional business callback Outbox, retry, dead-letter, and compensation.
select has_table(
  'public',
  'wf_business_callback_outbox',
  'workflow business callback Outbox exists'
);
select has_table(
  'public',
  'wf_business_callback_attempt',
  'workflow business callback delivery audit exists'
);
select ok(
  (select relrowsecurity from pg_class where oid='public.wf_business_callback_outbox'::regclass)
  and (select relrowsecurity from pg_class where oid='public.wf_business_callback_attempt'::regclass),
  'callback Outbox and attempt audit both enforce RLS'
);
select ok(
  not exists (
    select 1
    from public.wf_business_callback_outbox o
    where o.status <> 'succeeded'
  ),
  'successful generic workflow callbacks complete inline'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'b2000000-0000-4000-8000-000000000001';
set local "request.jwt.claims" = '{"sub":"b2000000-0000-4000-8000-000000000001","email":"workflow-pgtap-outsider@example.invalid","role":"authenticated"}';
select is(
  (select count(*) from public.wf_business_callback_outbox),
  0::bigint,
  'ordinary users cannot read callback operations data'
);
select lives_ok(
  $$select public.get_workflow_callback_outbox(null, 20)$$,
  'ordinary users can access tenant-scoped read-only callback monitoring'
);

reset role;
update public.wf_instance
set business_type='tms_waybill_cost',
    business_id='a6000000-0000-4000-8000-000000000008'
where business_id='a6000000-0000-4000-8000-000000000007';

select lives_ok(
  $$select app_private.apply_workflow_business_status(
    'tms_waybill_cost',
    'a6000000-0000-4000-8000-000000000008',
    'approved',
    'pgTAP',
    'missing business record must not roll back approval'
  )$$,
  'business callback failure is isolated from the workflow transaction'
);
select is(
  (select status from public.wf_business_callback_outbox
   where business_id='a6000000-0000-4000-8000-000000000008'
     and target_status='approved'),
  'retry_wait',
  'failed callback enters retry-wait state'
);

update public.wf_business_callback_outbox
set max_attempts=2, next_attempt_at=now()-interval '1 second'
where business_id='a6000000-0000-4000-8000-000000000008'
  and target_status='approved';
select app_private.process_workflow_business_callbacks(20);
select is(
  (select status from public.wf_business_callback_outbox
   where business_id='a6000000-0000-4000-8000-000000000008'
     and target_status='approved'),
  'dead_letter',
  'callback reaches dead-letter after the configured retry threshold'
);
select is(
  (select count(*) from public.wf_business_callback_attempt a
   join public.wf_business_callback_outbox o on o.id=a.outbox_id
   where o.business_id='a6000000-0000-4000-8000-000000000008'
     and o.target_status='approved'),
  2::bigint,
  'every failed callback attempt is recorded in the append-only audit'
);

do $$
declare
  v_super_auth_user_id uuid;
begin
  select u.auth_user_id into v_super_auth_user_id
  from public.sys_user u where lower(u.user_email) = '869123771@qq.com' limit 1;
  perform set_config('request.jwt.claim.sub', v_super_auth_user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_super_auth_user_id, 'email', '869123771@qq.com', 'role', 'authenticated')::text,
    true
  );
end;
$$;
set local role authenticated;
select is(
  (public.get_workflow_callback_outbox('dead_letter', 20) #>> '{summary,deadLetter}')::bigint,
  1::bigint,
  'platform super can monitor callback dead letters'
);
select lives_ok(
  $$select public.retry_workflow_business_callback(
    (select id from public.wf_business_callback_outbox
     where business_id='a6000000-0000-4000-8000-000000000008'
       and target_status='approved')
  )$$,
  'platform super can trigger audited manual compensation'
);
select ok(
  (select manual_retry_count=1 and status='retry_wait'
   from public.wf_business_callback_outbox
   where business_id='a6000000-0000-4000-8000-000000000008'
     and target_status='approved'),
  'manual compensation increments its audit counter and preserves retry state on failure'
);

reset role;
select throws_ok(
  $$update public.wf_business_callback_attempt
    set error_message='tampered'
    where outbox_id=(
      select id from public.wf_business_callback_outbox
      where business_id='a6000000-0000-4000-8000-000000000008'
        and target_status='approved'
    )$$,
  'P0001',
  '审批业务回调投递记录不可修改或删除',
  'callback delivery audit is immutable'
);

select * from finish();
rollback;
