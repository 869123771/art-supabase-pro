begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(65);

-- Structural and authorization contract.
select has_table('public', 'wf_definition', 'workflow definition table exists');
select has_table('public', 'wf_version', 'workflow version table exists');
select has_table('public', 'wf_instance', 'workflow instance table exists');
select has_table('public', 'wf_task', 'workflow task table exists');
select has_table('public', 'wf_action', 'workflow action table exists');
select has_table('public', 'wf_task_reminder_event', 'workflow reminder ledger exists');

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
  '鑺傜偣 Review 鐨勫鎵规椂闄愬繀椤诲湪 1 鍒?720 灏忔椂涔嬮棿',
  'invalid zero-hour task SLA is rejected'
);
select throws_ok(
  $$
    select app_private.validate_workflow_config(
      '{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":1,"reminderBeforeMinutes":120,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}'::jsonb
    )
  $$,
  'P0001',
  '鑺傜偣 Review 鐨勫埌鏈熷墠鎻愰啋涓嶈兘瓒呰繃瀹℃壒鏃堕檺',
  'reminder lead time cannot exceed the task SLA'
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
  '椹冲洖鏃跺繀椤诲～鍐欏師鍥?,
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
  'P0001',
  '寰呭姙涓嶅瓨鍦ㄦ垨褰撳墠鐢ㄦ埛涓嶆槸瀹℃壒浜?,
  'cross-tenant users cannot act on another tenant task'
);
select throws_ok(
  $$select public.get_workflow_monitor_summary()$$,
  '42501',
  '褰撳墠璐﹀彿娌℃湁瀹℃壒鐩戞帶鏉冮檺',
  'ordinary users cannot access approval operations monitoring'
);

-- Control-plane writes and workflow-state overrides require platform-super authorization.
set local "request.jwt.claim.sub" = 'a2000000-0000-4000-8000-000000000002';
set local "request.jwt.claims" = '{"sub":"a2000000-0000-4000-8000-000000000002","email":"workflow-pgtap-approver1@example.invalid","role":"authenticated"}';
select throws_ok(
  $$select public.save_workflow_definition(
    '{"code":"tenant_admin_must_not_write","name":"Blocked admin definition","businessType":"blocked_admin_business","config":{"nodes":[{"key":"review","name":"Review","order":1,"approvalMode":"any","allowSelfApproval":false,"dueHours":24,"assignee":{"type":"initiator"},"condition":{"operator":"always"}}]}}'::jsonb
  )$$,
  '42501',
  '褰撳墠璐﹀彿娌℃湁娴佺▼閰嶇疆鏉冮檺',
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
  '褰撳墠璐﹀彿娌℃湁缁堟瀹℃壒娴佺▼鐨勬潈闄?,
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
  '瀹℃壒鍔ㄤ綔璁板綍涓嶅彲淇敼鎴栧垹闄?,
  'workflow audit actions are immutable'
);
select throws_ok(
  $$update public.wf_version set config='{"nodes":[]}'::jsonb where id='a5000000-0000-4000-8000-000000000001'$$,
  'P0001',
  '宸插彂甯冩垨宸插綊妗ｇ殑娴佺▼鐗堟湰涓嶅彲淇敼',
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
select throws_ok(
  $$select public.get_workflow_callback_outbox(null, 20)$$,
  '42501',
  '褰撳墠璐﹀彿娌℃湁瀹℃壒鍥炶皟鐩戞帶鏉冮檺',
  'ordinary users cannot access callback operations RPCs'
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
  '瀹℃壒涓氬姟鍥炶皟鎶曢€掕褰曚笉鍙慨鏀规垨鍒犻櫎',
  'callback delivery audit is immutable'
);

select * from finish();
rollback;
