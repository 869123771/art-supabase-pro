-- Driver records may be submitted in real time or backfilled later. The business
-- state machine, permissions, required evidence, and odometer checks remain in
-- place; only occurrence-time ordering/current-time guards are removed.
do $migration$
declare
  function_definition text;
  updated_definition text;
begin
  select pg_get_functiondef(
    'public.tms_record_waybill_departure(uuid,timestamp with time zone,numeric,jsonb,text)'::regprocedure
  ) into function_definition;
  updated_definition := replace(
    function_definition,
    $old$  occurred_at := coalesce(p_departure_time, now());
  if occurred_at < coalesce(loading_record.completed_at, waybill_record.loaded_at, waybill_record.accepted_at)
     or occurred_at > now() + interval '10 minutes' then
    raise exception '发车时间必须晚于装货完成时间且不能超过当前时间 10 分钟' using errcode = '23514';
  end if;
  operator_value := app_private.tms_current_operator_name();$old$,
    $new$  occurred_at := coalesce(p_departure_time, now());
  -- Occurrence time is supplied by the operator; departure_recorded_at preserves submission time.
  operator_value := app_private.tms_current_operator_name();$new$
  );
  if updated_definition = function_definition then
    raise exception 'tms_record_waybill_departure time guard did not match expected definition';
  end if;
  execute updated_definition;

  select pg_get_functiondef(
    'public.tms_sign_waybill(uuid,timestamp with time zone,text,jsonb,jsonb,text)'::regprocedure
  ) into function_definition;
  updated_definition := replace(
    function_definition,
    $old$  occurred_at := coalesce(p_signed_at, now());
  if occurred_at < coalesce(unloading_record.completed_at, waybill_record.unloaded_at)
     or occurred_at > now() + interval '10 minutes' then
    raise exception '签收时间必须晚于卸货完成时间且不能超过当前时间 10 分钟' using errcode = '23514';
  end if;
  operator_value := app_private.tms_current_operator_name();$old$,
    $new$  occurred_at := coalesce(p_signed_at, now());
  -- Occurrence time is supplied by the operator; signature_recorded_at preserves submission time.
  operator_value := app_private.tms_current_operator_name();$new$
  );
  if updated_definition = function_definition then
    raise exception 'tms_sign_waybill time guard did not match expected definition';
  end if;
  execute updated_definition;

  select pg_get_functiondef(
    'public.tms_complete_waybill_execution(uuid,timestamp with time zone,numeric,jsonb,text)'::regprocedure
  ) into function_definition;
  updated_definition := replace(
    function_definition,
    $old$  occurred_at := COALESCE(p_return_time, now());
  IF occurred_at < execution_record.signed_at
     OR occurred_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION '收车时间必须晚于签收时间且不能超过当前时间 10 分钟'
      USING ERRCODE = '23514';
  END IF;
  operator_value := app_private.tms_current_operator_name();$old$,
    $new$  occurred_at := COALESCE(p_return_time, now());
  -- Occurrence time is supplied by the operator; completion_recorded_at preserves submission time.
  operator_value := app_private.tms_current_operator_name();$new$
  );
  if updated_definition = function_definition then
    raise exception 'tms_complete_waybill_execution time guard did not match expected definition';
  end if;
  execute updated_definition;

  select pg_get_functiondef(
    'public.tms_submit_driver_waybill_expense(uuid,uuid,numeric,date,jsonb,text,uuid,text,text,text,text,text,numeric,numeric,text,text)'::regprocedure
  ) into function_definition;
  updated_definition := replace(
    function_definition,
    $old$  if p_occurred_on is null or p_occurred_on > current_date then
    raise exception '费用发生日期不能为空或晚于今天';
  end if;$old$,
    $new$  if p_occurred_on is null then
    raise exception '费用发生日期不能为空';
  end if;$new$
  );
  if updated_definition = function_definition then
    raise exception 'tms_submit_driver_waybill_expense time guard did not match expected definition';
  end if;
  execute updated_definition;
end;
$migration$;

;
