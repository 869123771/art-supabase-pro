begin;

create temporary table hr_time_test_context (
  tenant_id uuid not null,
  employee_id uuid not null,
  ordinary_auth_user_id uuid,
  shift_id uuid,
  assignment_id uuid,
  record_id uuid,
  correction_id uuid,
  period_id uuid,
  work_date date not null
) on commit drop;

create temporary table hr_time_test_result (
  check_name text primary key,
  passed boolean not null,
  detail text
) on commit drop;

insert into hr_time_test_context(tenant_id,employee_id,ordinary_auth_user_id,work_date)
select e.tenant_id,e.id,
  coalesce((select u.auth_user_id from public.sys_user u
    where u.auth_user_id is not null
      and not ('R_SUPER'=any(coalesce(u.user_roles,array[]::text[])))
      and cardinality(coalesce(u.user_roles,array[]::text[]))=0
    order by u.create_time limit 1),gen_random_uuid()),
  (date_trunc('month',current_date+interval '10 years')+interval '10 days')::date
from public.hr_employee e
where e.employment_status not in ('left','terminated')
order by e.employee_no limit 1;

grant select,update on hr_time_test_context to authenticated;
grant select,insert on hr_time_test_result to authenticated;
grant execute on function public.get_app_user_display_name() to authenticated;

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select auth_user_id from public.sys_user where auth_user_id is not null
    and ('R_SUPER'=any(user_roles) or user_type='0')
    order by case when 'R_SUPER'=any(user_roles) then 0 else 1 end limit 1),
  'role','authenticated'
)::text,true);
set local role authenticated;

do $test$
declare
  v hr_time_test_context%rowtype;
  v_shift_id uuid;
  v_assignment_id uuid;
  v_record_id uuid;
  v_correction_id uuid;
  v_period_id uuid;
  v_direct_blocked boolean:=false;
begin
  select * into v from hr_time_test_context limit 1;
  if v.tenant_id is null then raise exception 'No time management test fixture'; end if;

  v_shift_id:=public.hr_save_attendance_record_secure('shift',null,jsonb_build_object(
    'tenant_id',v.tenant_id,'shift_code','TEST-TIME-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    'shift_name','自动化标准班','shift_type','regular','start_time','09:00','end_time','18:00',
    'break_minutes',60,'time_zone','Asia/Shanghai','late_grace_minutes',5,
    'early_leave_grace_minutes',5,'enabled',true
  ));
  v_assignment_id:=public.hr_save_attendance_record_secure('assignment',null,jsonb_build_object(
    'tenant_id',v.tenant_id,'employee_id',v.employee_id,'shift_id',v_shift_id,
    'work_date',v.work_date,'assignment_status','scheduled'
  ));
  v_record_id:=public.hr_save_attendance_record_secure('record',null,jsonb_build_object(
    'tenant_id',v.tenant_id,'employee_id',v.employee_id,'shift_id',v_shift_id,'work_date',v.work_date,
    'clock_in_at',make_timestamptz(extract(year from v.work_date)::integer,extract(month from v.work_date)::integer,
      extract(day from v.work_date)::integer,9,30,0,'Asia/Shanghai'),
    'clock_out_at',make_timestamptz(extract(year from v.work_date)::integer,extract(month from v.work_date)::integer,
      extract(day from v.work_date)::integer,18,0,0,'Asia/Shanghai'),
    'attendance_status','normal','source','manual'
  ));
  update hr_time_test_context set shift_id=v_shift_id,assignment_id=v_assignment_id,record_id=v_record_id;

  insert into hr_time_test_result values('daily_valuation_detects_exception',exists(
    select 1 from jsonb_array_elements(public.hr_list_attendance_records_secure(
      'record',0,19,null,'open',date_trunc('month',v.work_date)::date,v.tenant_id)->'records') row
    where (row->>'id')::uuid=v_record_id and (row->>'scheduled_minutes')::integer=480
      and (row->>'late_minutes')::integer=25 and (row->>'exception_status')='open'
  ),'班次时区、宽限和计划工时参与日核算，并识别迟到异常');

  v_correction_id:=public.hr_save_attendance_record_secure('correction',null,jsonb_build_object(
    'tenant_id',v.tenant_id,'attendance_record_id',v_record_id,
    'requested_clock_in_at',make_timestamptz(extract(year from v.work_date)::integer,extract(month from v.work_date)::integer,
      extract(day from v.work_date)::integer,9,0,0,'Asia/Shanghai'),
    'requested_clock_out_at',make_timestamptz(extract(year from v.work_date)::integer,extract(month from v.work_date)::integer,
      extract(day from v.work_date)::integer,18,0,0,'Asia/Shanghai'),
    'reason','自动化测试补录正确上班时间','proof_urls',jsonb_build_array('https://example.invalid/evidence')
  ));
  perform public.hr_transition_attendance_correction_secure(v_correction_id,'submit',null);
  perform public.hr_transition_attendance_correction_secure(v_correction_id,'approve','证据核验通过');
  update hr_time_test_context set correction_id=v_correction_id;

  insert into hr_time_test_result values('approved_correction_revalues_record',exists(
    select 1 from jsonb_array_elements(public.hr_list_attendance_records_secure(
      'record',0,19,null,'resolved',date_trunc('month',v.work_date)::date,v.tenant_id)->'records') row
    where (row->>'id')::uuid=v_record_id and (row->>'late_minutes')::integer=0
      and (row->>'payable_minutes')::integer=480 and row->>'source'='correction'
  ),'批准修正单后回写打卡并重新核算，异常转为已修正');

  v_period_id:=public.hr_save_attendance_record_secure('period',null,jsonb_build_object(
    'tenant_id',v.tenant_id,'period_month',date_trunc('month',v.work_date)::date
  ));
  perform public.hr_transition_attendance_period_secure(v_period_id,'review','月度考勤核对开始');
  perform public.hr_transition_attendance_period_secure(v_period_id,'close','所有异常与修正均已处理');
  update hr_time_test_context set period_id=v_period_id;

  insert into hr_time_test_result values('period_close_locks_records',exists(
    select 1 from jsonb_array_elements(public.hr_list_attendance_records_secure(
      'record',0,19,null,null,date_trunc('month',v.work_date)::date,v.tenant_id)->'records') row
    where (row->>'id')::uuid=v_record_id and row->>'locked_at' is not null
  ),'月度封账固化汇总快照并锁定期间内考勤记录');

  begin
    perform 1 from public.hr_attendance_record limit 1;
  exception when insufficient_privilege then v_direct_blocked:=true;
  end;
  insert into hr_time_test_result values('direct_table_access_denied',v_direct_blocked,
    '登录用户不能绕过受控 RPC 直接读取或修改考勤事实');
end
$test$;

reset role;
insert into hr_time_test_result values('anonymous_rpc_execution_denied',
  not has_function_privilege('anon','public.hr_attendance_overview_secure(uuid)','execute')
    and not has_function_privilege('anon','public.hr_save_attendance_record_secure(text,uuid,jsonb)','execute'),
  '匿名角色不能调用考勤工时读写 RPC');

select set_config('request.jwt.claims',jsonb_build_object(
  'sub',(select ordinary_auth_user_id from hr_time_test_context limit 1),'role','authenticated'
)::text,true);
set local role authenticated;

do $test$
declare v_denied boolean:=false;
begin
  begin perform public.hr_attendance_overview_secure(null);
  exception when insufficient_privilege then v_denied:=true;
  end;
  insert into hr_time_test_result values('ordinary_user_denied',v_denied,
    '未授权普通用户不能读取租户考勤运营数据');
end
$test$;

reset role;
select check_name,passed,detail from hr_time_test_result order by check_name;
do $test$
begin
  if exists(select 1 from hr_time_test_result where not passed) then
    raise exception 'HR time management verification failed';
  end if;
end
$test$;

rollback;
