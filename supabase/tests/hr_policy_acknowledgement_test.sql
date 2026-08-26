begin;
set local timezone='Asia/Shanghai';

create temporary table hr_policy_ack_test_context(
  tenant_id uuid not null,
  ordinary_auth_user_id uuid not null,
  policy_id uuid,
  receipt_id uuid
) on commit drop;
create temporary table hr_policy_ack_test_result(
  check_name text primary key,passed boolean not null,detail text
) on commit drop;

insert into hr_policy_ack_test_context(tenant_id,ordinary_auth_user_id)
select user_row.tenant_id,user_row.auth_user_id
from public.sys_user user_row
where user_row.auth_user_id is not null and user_row.status='1'
  and 'R_REGISTER'=any(user_row.user_roles)
  and exists(select 1 from public.hr_employee employee where employee.tenant_id=user_row.tenant_id and employee.employment_status in ('probation','active','leave'))
order by user_row.create_time limit 1;
grant select,update on hr_policy_ack_test_context to authenticated;
grant select,insert,update on hr_policy_ack_test_result to anon,authenticated;

set local role anon;
do $test$ declare v_denied boolean:=false; begin
  begin perform public.hr_policy_acknowledgement_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true; end;
  insert into hr_policy_ack_test_result values('anon_denied',v_denied,'匿名账号不能读取政策签收');
end $test$;
reset role;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null and ('R_SUPER'=any(user_roles) or user_type='0') order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_tenant_id uuid:=(select tenant_id from hr_policy_ack_test_context limit 1);
  v_policy_id uuid;
  v_receipt_id uuid;
  v_records jsonb;
  v_overview jsonb;
  v_immutable boolean:=false;
  v_waiver_guard boolean:=false;
begin
  if v_tenant_id is null then raise exception 'No ordinary HR tenant test fixture'; end if;
  v_policy_id:=public.hr_save_policy_document_secure(null,jsonb_build_object(
    'tenant_id',v_tenant_id,'policy_code','POLICY_ACK_TEST','policy_title','员工政策签收自动化测试',
    'category','员工行为规范','version_no',1,'effective_date',current_date,
    'acknowledgement_due_days',7,'audience_type','all',
    'document_reference','policy://test/POLICY_ACK_TEST/v1',
    'content_summary','验证政策版本、适用人群、送达、签收、豁免和证据边界。'
  ));
  perform public.hr_transition_policy_acknowledgement_secure('policy',v_policy_id,'publish','批准发布测试政策',null);
  v_records:=public.hr_list_policy_acknowledgement_records_secure('receipt',0,199,null,null,v_policy_id,v_tenant_id);
  v_receipt_id:=(v_records->'records'->0->>'id')::uuid;
  update hr_policy_ack_test_context set policy_id=v_policy_id,receipt_id=v_receipt_id;
  insert into hr_policy_ack_test_result values(
    'audience_delivery',v_receipt_id is not null and (v_records->>'total')::integer>=1,
    '发布政策按适用人群快照逐员工送达记录'
  );

  begin
    perform public.hr_save_policy_document_secure(v_policy_id,jsonb_build_object(
      'tenant_id',v_tenant_id,'policy_code','POLICY_ACK_TEST','policy_title','不应覆盖已发布版本',
      'category','员工行为规范','version_no',1,'effective_date',current_date,
      'acknowledgement_due_days',7,'audience_type','all',
      'document_reference','policy://invalid','content_summary','不应保存'
    ));
  exception when others then v_immutable:=true; end;
  insert into hr_policy_ack_test_result values('published_immutable',v_immutable,'已发布政策不可覆盖修改，只能创建新版本');

  perform public.hr_transition_policy_acknowledgement_secure(
    'receipt',v_receipt_id,'acknowledge','已阅读并理解政策内容','ACK-TEST-001'
  );
  v_records:=public.hr_list_policy_acknowledgement_records_secure('receipt',0,9,null,'acknowledged',v_policy_id,v_tenant_id);
  insert into hr_policy_ack_test_result values(
    'acknowledgement_evidence',(v_records->>'total')::integer=1
      and v_records->'records'->0->>'evidence_reference'='ACK-TEST-001',
    '签收记录确认人、时间、说明与凭证引用'
  );

  perform public.hr_transition_policy_acknowledgement_secure('receipt',v_receipt_id,'reopen','发现签收主体需重新确认',null);
  begin perform public.hr_transition_policy_acknowledgement_secure('receipt',v_receipt_id,'waive',null,null);
  exception when others then v_waiver_guard:=true; end;
  insert into hr_policy_ack_test_result values('waiver_reason_gate',v_waiver_guard,'豁免签收必须填写原因');
  perform public.hr_transition_policy_acknowledgement_secure(
    'receipt',v_receipt_id,'waive','测试员工已离开适用岗位','WAIVE-TEST-001'
  );
  v_overview:=public.hr_policy_acknowledgement_overview_secure(v_tenant_id);
  insert into hr_policy_ack_test_result values(
    'completion_governance',(v_overview->>'receipt_count')::integer>=1
      and (v_overview->>'acknowledged_count')::integer>=1
      and (v_overview->>'completion_rate')::numeric>0,
    '已签收与已豁免共同纳入完成率，待签和逾期独立跟踪'
  );
end $test$;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_policy_ack_test_context limit 1),'role','authenticated')::text,true);
set local role authenticated;

do $test$
declare
  v_policy_id uuid:=(select policy_id from hr_policy_ack_test_context limit 1);
  v_receipts jsonb;
  v_write_denied boolean:=false;
  v_direct_denied boolean:=false;
begin
  v_receipts:=public.hr_list_policy_acknowledgement_records_secure('receipt',0,9,null,null,v_policy_id,null);
  insert into hr_policy_ack_test_result values(
    'ordinary_safe_read',coalesce((v_receipts->>'evidence_access')::boolean,true)=false
      and v_receipts->'records'->0->>'evidence_reference' is null
      and v_receipts->'records'->0->>'waiver_reason' is null,
    '普通用户可租户内只读，但签收凭证与豁免依据由服务端隐藏'
  );
  begin perform public.hr_transition_policy_acknowledgement_secure('receipt',(select receipt_id from hr_policy_ack_test_context limit 1),'reopen','不应执行',null);
  exception when insufficient_privilege then v_write_denied:=true; end;
  insert into hr_policy_ack_test_result values('ordinary_write_denied',v_write_denied,'普通用户不能改变政策或签收流程状态');
  begin perform count(*) from public.hr_policy_receipt;
  exception when insufficient_privilege then v_direct_denied:=true; end;
  insert into hr_policy_ack_test_result values('direct_table_denied',v_direct_denied,'政策与签收业务表不向 authenticated 直接开放');
end $test$;

reset role;
select check_name,passed,detail from hr_policy_ack_test_result order by check_name;
do $test$ declare v_failed text; begin
  select string_agg(check_name||': '||detail,'; ') into v_failed from hr_policy_ack_test_result where not passed;
  if v_failed is not null then raise exception 'HR policy acknowledgement test failed: %',v_failed; end if;
end $test$;
rollback;
