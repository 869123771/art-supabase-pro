create or replace function app_private.hr_valuate_attendance_record(p_record_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_record public.hr_attendance_record;
  v_shift public.hr_shift;
  v_planned_start timestamptz;
  v_planned_end timestamptz;
  v_scheduled integer := 0;
  v_work integer := 0;
  v_late integer := 0;
  v_early integer := 0;
  v_absence integer := 0;
  v_overtime integer := 0;
  v_status text := 'normal';
  v_exception text := 'clear';
  v_note text;
begin
  select * into v_record from public.hr_attendance_record where id = p_record_id for update;
  if not found then raise exception '考勤记录不存在'; end if;
  if v_record.locked_at is not null then raise exception '考勤记录已封账，不能重新核算'; end if;

  if v_record.shift_id is not null then
    select * into v_shift from public.hr_shift
    where id = v_record.shift_id and tenant_id = v_record.tenant_id;
  else
    select shift.* into v_shift
    from public.hr_shift_assignment assignment
    join public.hr_shift shift on shift.id = assignment.shift_id and shift.tenant_id = assignment.tenant_id
    where assignment.tenant_id = v_record.tenant_id
      and assignment.employee_id = v_record.employee_id
      and assignment.work_date = v_record.work_date
      and assignment.assignment_status <> 'cancelled';
  end if;

  if found then
    v_planned_start := (v_record.work_date::timestamp + v_shift.start_time) at time zone v_shift.time_zone;
    v_planned_end := ((v_record.work_date + case when v_shift.cross_day then 1 else 0 end)::timestamp
      + v_shift.end_time) at time zone v_shift.time_zone;
    v_scheduled := greatest(floor(extract(epoch from (v_planned_end - v_planned_start)) / 60)::integer
      - v_shift.break_minutes, 0);
  end if;

  if v_record.attendance_status in ('leave', 'business_trip') then
    v_status := v_record.attendance_status;
    v_note := case when v_status = 'leave' then '已批准休假，不生成出勤异常' else '已登记出差，不生成出勤异常' end;
  elsif v_record.clock_in_at is null or v_record.clock_out_at is null then
    v_status := 'absent';
    v_absence := v_scheduled;
    v_exception := 'open';
    v_note := case
      when v_record.clock_in_at is null and v_record.clock_out_at is null then '缺少上下班打卡'
      when v_record.clock_in_at is null then '缺少上班打卡'
      else '缺少下班打卡'
    end;
  else
    v_work := greatest(floor(extract(epoch from (v_record.clock_out_at - v_record.clock_in_at)) / 60)::integer
      - coalesce(v_shift.break_minutes, 0), 0);
    if v_planned_start is not null then
      v_late := greatest(floor(extract(epoch from (v_record.clock_in_at - v_planned_start)) / 60)::integer
        - v_shift.late_grace_minutes, 0);
      v_early := greatest(floor(extract(epoch from (v_planned_end - v_record.clock_out_at)) / 60)::integer
        - v_shift.early_leave_grace_minutes, 0);
    end if;
    v_absence := greatest(v_scheduled - v_work, 0);
    v_overtime := greatest(v_work - v_scheduled, 0);
    if v_late > 0 then v_status := 'late';
    elsif v_early > 0 then v_status := 'early_leave';
    else v_status := 'normal'; end if;
    if v_late > 0 or v_early > 0 or v_absence > 0 then v_exception := 'open'; end if;
    v_note := concat_ws('；',
      case when v_late > 0 then '迟到 ' || v_late || ' 分钟' end,
      case when v_early > 0 then '早退 ' || v_early || ' 分钟' end,
      case when v_absence > 0 then '缺勤 ' || v_absence || ' 分钟' end,
      case when v_overtime > 0 then '超出计划 ' || v_overtime || ' 分钟' end
    );
    if v_note = '' then v_note := '打卡覆盖计划工时'; end if;
  end if;

  update public.hr_attendance_record
  set shift_id = coalesce(shift_id, v_shift.id),
      scheduled_minutes = v_scheduled,
      work_minutes = v_work,
      overtime_minutes = v_overtime,
      late_minutes = v_late,
      early_leave_minutes = v_early,
      absence_minutes = v_absence,
      payable_minutes = v_work,
      attendance_status = v_status,
      exception_status = v_exception,
      valuation_note = v_note
  where id = p_record_id;
end
$function$;

revoke all on function app_private.hr_valuate_attendance_record(uuid) from public, anon, authenticated;

create or replace function public.hr_attendance_overview_secure(p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrAttendance', 'Hr:Attendance:View', null, false) then
    raise exception '当前账号没有查看考勤工时的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  return jsonb_build_object(
    'active_shift_count', (select count(*) from public.hr_shift s
      where (p_tenant_id is null or s.tenant_id = p_tenant_id) and s.enabled),
    'today_assignment_count', (select count(*) from public.hr_shift_assignment a
      where (p_tenant_id is null or a.tenant_id = p_tenant_id)
        and a.work_date = current_date and a.assignment_status <> 'cancelled'),
    'open_exception_count', (select count(*) from public.hr_attendance_record r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id) and r.exception_status = 'open'),
    'pending_correction_count', (select count(*) from public.hr_attendance_correction c
      where (p_tenant_id is null or c.tenant_id = p_tenant_id) and c.status = 'submitted'),
    'reviewing_period_count', (select count(*) from public.hr_attendance_period p
      where (p_tenant_id is null or p.tenant_id = p_tenant_id) and p.status = 'reviewing'),
    'month_completion_rate', (
      select coalesce(round(100 * count(*) filter (where r.exception_status <> 'open')::numeric
        / nullif(count(*), 0), 1), 0)
      from public.hr_attendance_record r
      where (p_tenant_id is null or r.tenant_id = p_tenant_id)
        and r.work_date >= date_trunc('month', current_date)::date
        and r.work_date < (date_trunc('month', current_date) + interval '1 month')::date
    )
  );
end
$function$;

create or replace function public.hr_list_attendance_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_period_month date default null,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_offset integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(500, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_keyword text := nullif(btrim(p_keyword), '');
  v_result jsonb;
begin
  if p_kind not in ('record', 'assignment', 'correction', 'period', 'shift') then
    raise exception '不支持的考勤记录类型';
  end if;
  if not app_private.can_execute_business_action('HrAttendance', 'Hr:Attendance:View', null, false) then
    raise exception '当前账号没有查看考勤工时的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'shift' then
    with filtered as materialized (
      select s.*,
        (select count(*) from public.hr_shift_assignment a where a.shift_id=s.id and a.tenant_id=s.tenant_id) usage_count
      from public.hr_shift s
      where (p_tenant_id is null or s.tenant_id=p_tenant_id)
        and (p_status is null or s.enabled = (p_status='enabled'))
        and (v_keyword is null or s.shift_code ilike '%'||v_keyword||'%'
          or s.shift_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by enabled desc, shift_code offset v_offset limit v_limit
    )
    select jsonb_build_object('records',coalesce(jsonb_agg(to_jsonb(paged) order by enabled desc,shift_code),'[]'::jsonb),
      'total',(select count(*) from filtered)) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'assignment' then
    with filtered as materialized (
      select a.*, e.employee_no,e.employee_name,s.shift_code,s.shift_name,s.start_time,s.end_time
      from public.hr_shift_assignment a
      join public.hr_employee e on e.id=a.employee_id and e.tenant_id=a.tenant_id
      join public.hr_shift s on s.id=a.shift_id and s.tenant_id=a.tenant_id
      where (p_tenant_id is null or a.tenant_id=p_tenant_id)
        and (p_status is null or a.assignment_status=p_status)
        and (p_period_month is null or a.work_date >= date_trunc('month',p_period_month)::date
          and a.work_date < (date_trunc('month',p_period_month)+interval '1 month')::date)
        and (v_keyword is null or e.employee_no ilike '%'||v_keyword||'%'
          or e.employee_name ilike '%'||v_keyword||'%' or s.shift_name ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by work_date desc,employee_name offset v_offset limit v_limit
    )
    select jsonb_build_object('records',coalesce(jsonb_agg(
      (to_jsonb(paged)-'employee_no'-'employee_name'-'shift_code'-'shift_name'-'start_time'-'end_time')
      ||jsonb_build_object('employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
        'shift',jsonb_build_object('id',shift_id,'code',shift_code,'name',shift_name,'start_time',start_time,'end_time',end_time))
      order by work_date desc,employee_name),'[]'::jsonb),'total',(select count(*) from filtered))
    into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'record' then
    with filtered as materialized (
      select r.*, e.employee_no,e.employee_name,s.shift_code,s.shift_name,
        exists(select 1 from public.hr_attendance_correction c where c.attendance_record_id=r.id and c.status='submitted') pending_correction
      from public.hr_attendance_record r
      join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
      left join public.hr_shift s on s.id=r.shift_id and s.tenant_id=r.tenant_id
      where (p_tenant_id is null or r.tenant_id=p_tenant_id)
        and (p_status is null or r.exception_status=p_status)
        and (p_period_month is null or r.work_date >= date_trunc('month',p_period_month)::date
          and r.work_date < (date_trunc('month',p_period_month)+interval '1 month')::date)
        and (v_keyword is null or e.employee_no ilike '%'||v_keyword||'%'
          or e.employee_name ilike '%'||v_keyword||'%' or s.shift_name ilike '%'||v_keyword||'%'
          or r.valuation_note ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by work_date desc,employee_name offset v_offset limit v_limit
    )
    select jsonb_build_object('records',coalesce(jsonb_agg(
      (to_jsonb(paged)-'employee_no'-'employee_name'-'shift_code'-'shift_name')
      ||jsonb_build_object('employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
        'shift',case when shift_id is null then null else jsonb_build_object('id',shift_id,'code',shift_code,'name',shift_name) end)
      order by work_date desc,employee_name),'[]'::jsonb),'total',(select count(*) from filtered))
    into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  if p_kind = 'correction' then
    with filtered as materialized (
      select c.*,r.work_date,r.clock_in_at original_clock_in_at,r.clock_out_at original_clock_out_at,
        r.exception_status,e.employee_no,e.employee_name
      from public.hr_attendance_correction c
      join public.hr_attendance_record r on r.id=c.attendance_record_id and r.tenant_id=c.tenant_id
      join public.hr_employee e on e.id=c.employee_id and e.tenant_id=c.tenant_id
      where (p_tenant_id is null or c.tenant_id=p_tenant_id)
        and (p_status is null or c.status=p_status)
        and (p_period_month is null or r.work_date >= date_trunc('month',p_period_month)::date
          and r.work_date < (date_trunc('month',p_period_month)+interval '1 month')::date)
        and (v_keyword is null or c.correction_no ilike '%'||v_keyword||'%'
          or e.employee_no ilike '%'||v_keyword||'%' or e.employee_name ilike '%'||v_keyword||'%'
          or c.reason ilike '%'||v_keyword||'%')
    ), paged as (
      select * from filtered order by case when status='submitted' then 0 else 1 end,create_time desc
      offset v_offset limit v_limit
    )
    select jsonb_build_object('records',coalesce(jsonb_agg(
      (to_jsonb(paged)-'employee_no'-'employee_name')
      ||jsonb_build_object('employee',jsonb_build_object('id',employee_id,'code',employee_no,'name',employee_name),
        'record',jsonb_build_object('id',attendance_record_id,'work_date',work_date,
          'clock_in_at',original_clock_in_at,'clock_out_at',original_clock_out_at,'exception_status',exception_status))
      order by case when status='submitted' then 0 else 1 end,create_time desc),'[]'::jsonb),
      'total',(select count(*) from filtered)) into v_result from paged;
    return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
  end if;

  with filtered as materialized (
    select p.* from public.hr_attendance_period p
    where (p_tenant_id is null or p.tenant_id=p_tenant_id)
      and (p_status is null or p.status=p_status)
      and (p_period_month is null or p.period_month=date_trunc('month',p_period_month)::date)
  ), paged as (
    select * from filtered order by period_month desc offset v_offset limit v_limit
  )
  select jsonb_build_object('records',coalesce(jsonb_agg(to_jsonb(paged) order by period_month desc),'[]'::jsonb),
    'total',(select count(*) from filtered)) into v_result from paged;
  return coalesce(v_result,jsonb_build_object('records','[]'::jsonb,'total',0));
end
$function$;

create or replace function public.hr_list_attendance_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('employee','shift','record') then raise exception '不支持的考勤选项类型'; end if;
  if not app_private.can_execute_business_action('HrAttendance', 'Hr:Attendance:View', null, false) then
    raise exception '当前账号没有查看考勤选项的权限' using errcode='42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id:=v_tenant_id; end if;
  if p_kind='employee' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'tenant_id',e.tenant_id,
      'code',e.employee_no,'name',e.employee_name) order by e.employee_no)
      from public.hr_employee e where (p_tenant_id is null or e.tenant_id=p_tenant_id)
        and e.employment_status <> 'terminated'),'[]'::jsonb);
  end if;
  if p_kind='shift' then
    return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'tenant_id',s.tenant_id,
      'code',s.shift_code,'name',s.shift_name,'start_time',s.start_time,'end_time',s.end_time,
      'time_zone',s.time_zone) order by s.shift_code)
      from public.hr_shift s where (p_tenant_id is null or s.tenant_id=p_tenant_id) and s.enabled),'[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'tenant_id',r.tenant_id,
    'code',to_char(r.work_date,'YYYY-MM-DD'),'name',e.employee_name,'employee_id',r.employee_id,
    'work_date',r.work_date,'clock_in_at',r.clock_in_at,'clock_out_at',r.clock_out_at,
    'exception_status',r.exception_status) order by r.work_date desc,e.employee_name)
    from public.hr_attendance_record r join public.hr_employee e on e.id=r.employee_id and e.tenant_id=r.tenant_id
    where (p_tenant_id is null or r.tenant_id=p_tenant_id) and r.locked_at is null
      and not exists(select 1 from public.hr_attendance_correction c
        where c.attendance_record_id=r.id and c.status in ('draft','submitted'))),'[]'::jsonb);
end
$function$;

create or replace function public.hr_save_attendance_record_secure(
  p_kind text,
  p_id uuid,
  p_payload jsonb
)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant uuid := coalesce((p_payload->>'tenant_id')::uuid,v_tenant_id);
  v_id uuid;
  v_record public.hr_attendance_record;
  v_shift_id uuid;
  v_code text;
begin
  if p_kind not in ('shift','assignment','record','correction','period') then raise exception '不支持的考勤记录类型'; end if;
  if not app_private.can_execute_business_action('HrAttendance',
    case when p_id is null then 'Hr:Attendance:Add' else 'Hr:Attendance:Edit' end,null,false) then
    raise exception '当前账号没有维护考勤工时的权限' using errcode='42501';
  end if;
  if not app_private.is_platform_super() then v_target_tenant:=v_tenant_id; end if;
  if v_target_tenant is null then raise exception '请选择租户'; end if;

  if p_kind='shift' then
    if nullif(btrim(p_payload->>'shift_code'),'') is null or nullif(btrim(p_payload->>'shift_name'),'') is null then
      raise exception '班次编码和名称不能为空';
    end if;
    if not exists(select 1 from pg_catalog.pg_timezone_names where name=coalesce(nullif(p_payload->>'time_zone',''),'Asia/Shanghai')) then
      raise exception '班次时区无效';
    end if;
    if p_id is null then
      insert into public.hr_shift(tenant_id,shift_code,shift_name,shift_type,start_time,end_time,break_minutes,
        cross_day,enabled,time_zone,late_grace_minutes,early_leave_grace_minutes,remark)
      values(v_target_tenant,btrim(p_payload->>'shift_code'),btrim(p_payload->>'shift_name'),
        coalesce(p_payload->>'shift_type','regular'),(p_payload->>'start_time')::time,(p_payload->>'end_time')::time,
        coalesce((p_payload->>'break_minutes')::integer,0),coalesce((p_payload->>'cross_day')::boolean,false),
        coalesce((p_payload->>'enabled')::boolean,true),coalesce(nullif(p_payload->>'time_zone',''),'Asia/Shanghai'),
        coalesce((p_payload->>'late_grace_minutes')::integer,0),
        coalesce((p_payload->>'early_leave_grace_minutes')::integer,0),nullif(btrim(p_payload->>'remark'),''))
      returning id into v_id;
    else
      update public.hr_shift set shift_code=btrim(p_payload->>'shift_code'),shift_name=btrim(p_payload->>'shift_name'),
        shift_type=coalesce(p_payload->>'shift_type',shift_type),start_time=(p_payload->>'start_time')::time,
        end_time=(p_payload->>'end_time')::time,break_minutes=coalesce((p_payload->>'break_minutes')::integer,0),
        cross_day=coalesce((p_payload->>'cross_day')::boolean,false),enabled=coalesce((p_payload->>'enabled')::boolean,true),
        time_zone=coalesce(nullif(p_payload->>'time_zone',''),'Asia/Shanghai'),
        late_grace_minutes=coalesce((p_payload->>'late_grace_minutes')::integer,0),
        early_leave_grace_minutes=coalesce((p_payload->>'early_leave_grace_minutes')::integer,0),
        remark=nullif(btrim(p_payload->>'remark'),'')
      where id=p_id and (app_private.is_platform_super() or tenant_id=v_target_tenant) returning id into v_id;
    end if;
  elsif p_kind='assignment' then
    if exists(select 1 from public.hr_attendance_period p where p.tenant_id=v_target_tenant and p.status='closed'
      and (p_payload->>'work_date')::date >= p.period_month
      and (p_payload->>'work_date')::date < p.period_month+interval '1 month') then raise exception '所属考勤期间已封账'; end if;
    if p_id is null then
      insert into public.hr_shift_assignment(tenant_id,employee_id,shift_id,work_date,assignment_status,remark)
      values(v_target_tenant,(p_payload->>'employee_id')::uuid,(p_payload->>'shift_id')::uuid,
        (p_payload->>'work_date')::date,coalesce(p_payload->>'assignment_status','scheduled'),
        nullif(btrim(p_payload->>'remark'),'')) returning id into v_id;
    else
      update public.hr_shift_assignment set employee_id=(p_payload->>'employee_id')::uuid,
        shift_id=(p_payload->>'shift_id')::uuid,work_date=(p_payload->>'work_date')::date,
        assignment_status=coalesce(p_payload->>'assignment_status',assignment_status),remark=nullif(btrim(p_payload->>'remark'),'')
      where id=p_id and (app_private.is_platform_super() or tenant_id=v_target_tenant) returning id into v_id;
    end if;
  elsif p_kind='record' then
    if p_id is not null then select * into v_record from public.hr_attendance_record where id=p_id for update; end if;
    if p_id is not null and (not found or (not app_private.is_platform_super() and v_record.tenant_id<>v_target_tenant)) then
      raise exception '考勤记录不存在或无权操作';
    end if;
    if p_id is not null and v_record.locked_at is not null then raise exception '考勤记录已封账'; end if;
    v_shift_id:=nullif(p_payload->>'shift_id','')::uuid;
    if p_id is null then
      insert into public.hr_attendance_record(tenant_id,employee_id,shift_id,work_date,clock_in_at,clock_out_at,
        attendance_status,source,remark,source_reference)
      values(v_target_tenant,(p_payload->>'employee_id')::uuid,v_shift_id,(p_payload->>'work_date')::date,
        nullif(p_payload->>'clock_in_at','')::timestamptz,nullif(p_payload->>'clock_out_at','')::timestamptz,
        coalesce(p_payload->>'attendance_status','normal'),coalesce(p_payload->>'source','manual'),
        nullif(btrim(p_payload->>'remark'),''),nullif(btrim(p_payload->>'source_reference'),'')) returning id into v_id;
    else
      update public.hr_attendance_record set employee_id=(p_payload->>'employee_id')::uuid,shift_id=v_shift_id,
        work_date=(p_payload->>'work_date')::date,clock_in_at=nullif(p_payload->>'clock_in_at','')::timestamptz,
        clock_out_at=nullif(p_payload->>'clock_out_at','')::timestamptz,
        attendance_status=coalesce(p_payload->>'attendance_status',attendance_status),
        source=coalesce(p_payload->>'source',source),remark=nullif(btrim(p_payload->>'remark'),''),
        source_reference=nullif(btrim(p_payload->>'source_reference'),'')
      where id=p_id returning id into v_id;
    end if;
    perform app_private.hr_valuate_attendance_record(v_id);
  elsif p_kind='correction' then
    select * into v_record from public.hr_attendance_record
    where id=(p_payload->>'attendance_record_id')::uuid
      and (app_private.is_platform_super() or tenant_id=v_target_tenant) for update;
    if not found then raise exception '待修正考勤记录不存在'; end if;
    if v_record.locked_at is not null then raise exception '考勤记录已封账，不能发起修正'; end if;
    if nullif(btrim(p_payload->>'reason'),'') is null then raise exception '修正原因不能为空'; end if;
    if p_id is null then
      v_code:='HRTC'||to_char(clock_timestamp(),'YYYYMMDDHH24MISS')||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
      insert into public.hr_attendance_correction(tenant_id,correction_no,attendance_record_id,employee_id,
        requested_clock_in_at,requested_clock_out_at,reason,proof_urls,status,original_snapshot)
      values(v_record.tenant_id,v_code,v_record.id,v_record.employee_id,
        nullif(p_payload->>'requested_clock_in_at','')::timestamptz,
        nullif(p_payload->>'requested_clock_out_at','')::timestamptz,btrim(p_payload->>'reason'),
        coalesce(p_payload->'proof_urls','[]'::jsonb),'draft',jsonb_build_object(
          'clock_in_at',v_record.clock_in_at,'clock_out_at',v_record.clock_out_at,
          'work_minutes',v_record.work_minutes,'attendance_status',v_record.attendance_status,
          'exception_status',v_record.exception_status)) returning id into v_id;
    else
      update public.hr_attendance_correction set requested_clock_in_at=nullif(p_payload->>'requested_clock_in_at','')::timestamptz,
        requested_clock_out_at=nullif(p_payload->>'requested_clock_out_at','')::timestamptz,
        reason=btrim(p_payload->>'reason'),proof_urls=coalesce(p_payload->'proof_urls','[]'::jsonb),
        status=case when status='rejected' then 'draft' else status end,
        reviewed_at=null,reviewed_by=null,review_comment=null
      where id=p_id and status in ('draft','rejected')
        and (app_private.is_platform_super() or tenant_id=v_target_tenant) returning id into v_id;
    end if;
  else
    if p_id is null then
      insert into public.hr_attendance_period(tenant_id,period_month,status)
      values(v_target_tenant,date_trunc('month',(p_payload->>'period_month')::date)::date,'open') returning id into v_id;
    else
      update public.hr_attendance_period set close_note=nullif(btrim(p_payload->>'close_note'),'')
      where id=p_id and status='open' and (app_private.is_platform_super() or tenant_id=v_target_tenant)
      returning id into v_id;
    end if;
  end if;
  if v_id is null then raise exception '记录不存在、状态不允许编辑或租户不匹配'; end if;
  return v_id;
end
$function$;

create or replace function public.hr_transition_attendance_correction_secure(
  p_id uuid,p_action text,p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_correction public.hr_attendance_correction;
begin
  if p_action not in ('submit','approve','reject','cancel') then raise exception '不支持的修正单动作'; end if;
  if not app_private.can_execute_business_action('HrAttendance',
    case when p_action in ('approve','reject') then 'Hr:Attendance:ReviewCorrection' else 'Hr:Attendance:Edit' end,
    null,false) then raise exception '当前账号没有处理考勤修正的权限' using errcode='42501'; end if;
  select * into v_correction from public.hr_attendance_correction c where c.id=p_id
    and (app_private.is_platform_super() or c.tenant_id=v_tenant_id) for update;
  if not found then raise exception '考勤修正单不存在或无权操作'; end if;
  if p_action='submit' then
    if v_correction.status not in ('draft','rejected') then raise exception '当前修正单不能提交'; end if;
    update public.hr_attendance_correction set status='submitted',submitted_at=now(),
      reviewed_at=null,reviewed_by=null,review_comment=null where id=p_id;
    return;
  end if;
  if p_action='cancel' then
    if v_correction.status not in ('draft','submitted') then raise exception '当前修正单不能取消'; end if;
    update public.hr_attendance_correction set status='cancelled' where id=p_id;
    return;
  end if;
  if v_correction.status<>'submitted' then raise exception '只有待审核修正单可以评审'; end if;
  if p_action='reject' then
    if nullif(btrim(p_comment),'') is null then raise exception '驳回必须填写原因'; end if;
    update public.hr_attendance_correction set status='rejected',reviewed_at=now(),
      reviewed_by=auth.uid()::text,review_comment=btrim(p_comment) where id=p_id;
    return;
  end if;
  if exists(select 1 from public.hr_attendance_record r where r.id=v_correction.attendance_record_id and r.locked_at is not null) then
    raise exception '考勤记录已封账，不能批准修正';
  end if;
  update public.hr_attendance_record set clock_in_at=v_correction.requested_clock_in_at,
    clock_out_at=v_correction.requested_clock_out_at,source='correction',source_reference=v_correction.correction_no,
    remark=concat_ws('；',remark,'修正单 '||v_correction.correction_no||' 已批准')
  where id=v_correction.attendance_record_id;
  perform app_private.hr_valuate_attendance_record(v_correction.attendance_record_id);
  update public.hr_attendance_record set exception_status='resolved'
  where id=v_correction.attendance_record_id and exception_status='clear';
  update public.hr_attendance_correction set status='approved',reviewed_at=now(),
    reviewed_by=auth.uid()::text,review_comment=nullif(btrim(p_comment),'') where id=p_id;
end
$function$;

create or replace function public.hr_transition_attendance_record_secure(
  p_id uuid,p_action text,p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_record public.hr_attendance_record;
begin
  if p_action not in ('evaluate','waive','reopen') then raise exception '不支持的考勤记录动作'; end if;
  if not app_private.can_execute_business_action('HrAttendance',
    case when p_action='evaluate' then 'Hr:Attendance:Evaluate' else 'Hr:Attendance:ReviewCorrection' end,
    null,false) then raise exception '当前账号没有处理考勤异常的权限' using errcode='42501'; end if;
  select * into v_record from public.hr_attendance_record r where r.id=p_id
    and (app_private.is_platform_super() or r.tenant_id=v_tenant_id) for update;
  if not found then raise exception '考勤记录不存在或无权操作'; end if;
  if v_record.locked_at is not null then raise exception '考勤记录已封账'; end if;
  if p_action='evaluate' then perform app_private.hr_valuate_attendance_record(p_id); return; end if;
  if nullif(btrim(p_comment),'') is null then raise exception '处理异常必须填写原因'; end if;
  if p_action='waive' then
    if v_record.exception_status<>'open' then raise exception '只有待处理异常可以豁免'; end if;
    update public.hr_attendance_record set exception_status='waived',
      valuation_note=concat_ws('；',valuation_note,'豁免：'||btrim(p_comment)) where id=p_id;
  else
    if v_record.exception_status not in ('resolved','waived') then raise exception '当前记录不能重新打开'; end if;
    update public.hr_attendance_record set exception_status='open',
      valuation_note=concat_ws('；',valuation_note,'重新打开：'||btrim(p_comment)) where id=p_id;
  end if;
end
$function$;

create or replace function public.hr_transition_attendance_period_secure(
  p_id uuid,p_action text,p_comment text default null
)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_period public.hr_attendance_period;
  v_record_count integer;
  v_exception_count integer;
  v_scheduled bigint;
  v_payable bigint;
  v_overtime bigint;
begin
  if p_action not in ('review','close','reopen') then raise exception '不支持的考勤期间动作'; end if;
  if p_action='reopen' and not app_private.is_platform_super() then
    raise exception '只有平台超级管理员可以重新开放已封账期间' using errcode='42501';
  end if;
  if p_action<>'reopen' and not app_private.can_execute_business_action('HrAttendance','Hr:Attendance:ClosePeriod',null,false) then
    raise exception '当前账号没有考勤封账权限' using errcode='42501';
  end if;
  select * into v_period from public.hr_attendance_period p where p.id=p_id
    and (app_private.is_platform_super() or p.tenant_id=v_tenant_id) for update;
  if not found then raise exception '考勤期间不存在或无权操作'; end if;
  if p_action='reopen' then
    if v_period.status<>'closed' then raise exception '只有已封账期间可以重新开放'; end if;
    update public.hr_attendance_record set locked_at=null,locked_by=null
    where tenant_id=v_period.tenant_id and work_date>=v_period.period_month
      and work_date<v_period.period_month+interval '1 month';
    update public.hr_attendance_period set status='open',reviewed_at=null,reviewed_by=null,
      closed_at=null,closed_by=null,close_note=nullif(btrim(p_comment),'') where id=p_id;
    return;
  end if;
  select count(*),count(*) filter(where exception_status='open'),
    coalesce(sum(scheduled_minutes),0),coalesce(sum(payable_minutes),0),coalesce(sum(overtime_minutes),0)
  into v_record_count,v_exception_count,v_scheduled,v_payable,v_overtime
  from public.hr_attendance_record where tenant_id=v_period.tenant_id
    and work_date>=v_period.period_month and work_date<v_period.period_month+interval '1 month';
  if p_action='review' then
    if v_period.status<>'open' then raise exception '只有开放期间可以进入核对'; end if;
    update public.hr_attendance_period set status='reviewing',record_count=v_record_count,
      exception_count=v_exception_count,total_scheduled_minutes=v_scheduled,total_payable_minutes=v_payable,
      total_overtime_minutes=v_overtime,reviewed_at=now(),reviewed_by=auth.uid()::text,
      close_note=nullif(btrim(p_comment),'') where id=p_id;
    return;
  end if;
  if v_period.status<>'reviewing' then raise exception '只有核对中期间可以封账'; end if;
  if v_exception_count>0 then raise exception '仍有 % 条待处理考勤异常，不能封账',v_exception_count; end if;
  if exists(select 1 from public.hr_attendance_correction c join public.hr_attendance_record r
    on r.id=c.attendance_record_id and r.tenant_id=c.tenant_id
    where c.tenant_id=v_period.tenant_id and c.status='submitted'
      and r.work_date>=v_period.period_month and r.work_date<v_period.period_month+interval '1 month') then
    raise exception '期间内仍有待审核修正单，不能封账';
  end if;
  if nullif(btrim(p_comment),'') is null then raise exception '封账必须填写复核说明'; end if;
  update public.hr_attendance_record set locked_at=now(),locked_by=auth.uid()::text
  where tenant_id=v_period.tenant_id and work_date>=v_period.period_month
    and work_date<v_period.period_month+interval '1 month';
  update public.hr_attendance_period set status='closed',record_count=v_record_count,
    exception_count=v_exception_count,total_scheduled_minutes=v_scheduled,total_payable_minutes=v_payable,
    total_overtime_minutes=v_overtime,closed_at=now(),closed_by=auth.uid()::text,
    close_note=btrim(p_comment) where id=p_id;
end
$function$;

create or replace function public.hr_delete_attendance_record_secure(p_kind text,p_id uuid)
returns void language plpgsql security definer set search_path = '' as $function$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_deleted integer;
begin
  if p_kind not in ('shift','assignment','correction','period') then raise exception '该类考勤记录不允许删除'; end if;
  if not app_private.can_execute_business_action('HrAttendance','Hr:Attendance:Delete',null,false) then
    raise exception '当前账号没有删除考勤记录的权限' using errcode='42501';
  end if;
  if p_kind='shift' then
    delete from public.hr_shift s where s.id=p_id and (app_private.is_platform_super() or s.tenant_id=v_tenant_id)
      and not exists(select 1 from public.hr_shift_assignment a where a.shift_id=s.id)
      and not exists(select 1 from public.hr_attendance_record r where r.shift_id=s.id);
  elsif p_kind='assignment' then
    delete from public.hr_shift_assignment a where a.id=p_id
      and (app_private.is_platform_super() or a.tenant_id=v_tenant_id) and a.assignment_status='scheduled'
      and not exists(select 1 from public.hr_attendance_record r where r.tenant_id=a.tenant_id
        and r.employee_id=a.employee_id and r.work_date=a.work_date)
      and not exists(select 1 from public.hr_attendance_period p where p.tenant_id=a.tenant_id and p.status='closed'
        and a.work_date>=p.period_month and a.work_date<p.period_month+interval '1 month');
  elsif p_kind='correction' then
    delete from public.hr_attendance_correction c where c.id=p_id
      and (app_private.is_platform_super() or c.tenant_id=v_tenant_id) and c.status='draft';
  else
    delete from public.hr_attendance_period p where p.id=p_id
      and (app_private.is_platform_super() or p.tenant_id=v_tenant_id) and p.status='open'
      and not exists(select 1 from public.hr_attendance_record r where r.tenant_id=p.tenant_id
        and r.work_date>=p.period_month and r.work_date<p.period_month+interval '1 month');
  end if;
  get diagnostics v_deleted=row_count;
  if v_deleted=0 then raise exception '记录不存在、状态不允许删除或已被业务引用'; end if;
end
$function$;

revoke all on function public.hr_attendance_overview_secure(uuid) from public,anon,authenticated;
revoke all on function public.hr_list_attendance_records_secure(text,integer,integer,text,text,date,uuid) from public,anon,authenticated;
revoke all on function public.hr_list_attendance_options_secure(text,uuid) from public,anon,authenticated;
revoke all on function public.hr_save_attendance_record_secure(text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.hr_transition_attendance_correction_secure(uuid,text,text) from public,anon,authenticated;
revoke all on function public.hr_transition_attendance_record_secure(uuid,text,text) from public,anon,authenticated;
revoke all on function public.hr_transition_attendance_period_secure(uuid,text,text) from public,anon,authenticated;
revoke all on function public.hr_delete_attendance_record_secure(text,uuid) from public,anon,authenticated;

grant execute on function public.hr_attendance_overview_secure(uuid) to authenticated,service_role;
grant execute on function public.hr_list_attendance_records_secure(text,integer,integer,text,text,date,uuid) to authenticated,service_role;
grant execute on function public.hr_list_attendance_options_secure(text,uuid) to authenticated,service_role;
grant execute on function public.hr_save_attendance_record_secure(text,uuid,jsonb) to authenticated,service_role;
grant execute on function public.hr_transition_attendance_correction_secure(uuid,text,text) to authenticated,service_role;
grant execute on function public.hr_transition_attendance_record_secure(uuid,text,text) to authenticated,service_role;
grant execute on function public.hr_transition_attendance_period_secure(uuid,text,text) to authenticated,service_role;
grant execute on function public.hr_delete_attendance_record_secure(text,uuid) to authenticated,service_role;
