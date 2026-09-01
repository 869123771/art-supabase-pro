alter table public.tms_waybill_cargo_operation
  add column if not exists gross_weight_ton numeric,
  add column if not exists tare_weight_ton numeric,
  add column if not exists recognition_info text,
  add column if not exists recognition_payload jsonb not null default '{}'::jsonb;

do $migration$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_waybill_cargo_operation'::regclass
      and conname = 'tms_waybill_cargo_operation_gross_weight_positive'
  ) then
    alter table public.tms_waybill_cargo_operation
      add constraint tms_waybill_cargo_operation_gross_weight_positive
      check (gross_weight_ton is null or gross_weight_ton > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_waybill_cargo_operation'::regclass
      and conname = 'tms_waybill_cargo_operation_tare_weight_positive'
  ) then
    alter table public.tms_waybill_cargo_operation
      add constraint tms_waybill_cargo_operation_tare_weight_positive
      check (tare_weight_ton is null or tare_weight_ton > 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_waybill_cargo_operation'::regclass
      and conname = 'tms_waybill_cargo_operation_weight_order'
  ) then
    alter table public.tms_waybill_cargo_operation
      add constraint tms_waybill_cargo_operation_weight_order
      check (
        gross_weight_ton is null
        or tare_weight_ton is null
        or gross_weight_ton >= tare_weight_ton
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_waybill_cargo_operation'::regclass
      and conname = 'tms_waybill_cargo_operation_recognition_info_length'
  ) then
    alter table public.tms_waybill_cargo_operation
      add constraint tms_waybill_cargo_operation_recognition_info_length
      check (recognition_info is null or char_length(recognition_info) <= 10000);
  end if;
end;
$migration$;

create or replace function public.tms_get_waybill_cargo_operation_context(
  p_waybill_id uuid,
  p_operation_type text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'app_private'
as $function$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  policy_value jsonb;
  center_longitude numeric;
  center_latitude numeric;
  radius_value integer;
  allow_outside boolean;
  auto_checkin boolean;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id;

  if not found or not app_private.can_access_waybill_cargo_operation(p_waybill_id) then
    raise exception '无权查看该运单的装卸货信息' using errcode = '42501';
  end if;

  select * into operation_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id
    and operation_type = p_operation_type;

  policy_value := app_private.tms_cargo_operation_policy();
  if p_operation_type = 'loading' then
    center_longitude := waybill_record.shipper_longitude;
    center_latitude := waybill_record.shipper_latitude;
    radius_value := (policy_value ->> 'loadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'loadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmLoading')::boolean;
  else
    center_longitude := waybill_record.receiver_longitude;
    center_latitude := waybill_record.receiver_latitude;
    radius_value := (policy_value ->> 'unloadingRadiusM')::integer;
    allow_outside := (policy_value ->> 'unloadingAllowOutsideCheckIn')::boolean;
    auto_checkin := (policy_value ->> 'autoConfirmUnloading')::boolean;
  end if;

  return jsonb_build_object(
    'waybillId', waybill_record.id,
    'operationType', p_operation_type,
    'waybillStatus', waybill_record.status,
    'centerLongitude', center_longitude,
    'centerLatitude', center_latitude,
    'radiusM', radius_value,
    'allowOutsideCheckIn', allow_outside,
    'autoCheckIn', auto_checkin,
    'geofenceEnabled', (policy_value ->> 'enabled')::boolean,
    'canManage', app_private.can_manage_waybill_cargo_operation(p_operation_type),
    'operation', case
      when operation_record.id is null then null
      else jsonb_build_object(
        'id', operation_record.id,
        'tenantId', operation_record.tenant_id,
        'waybillId', operation_record.waybill_id,
        'operationType', operation_record.operation_type,
        'operationStatus', operation_record.operation_status,
        'checkinTime', operation_record.checkin_time,
        'checkinMode', operation_record.checkin_mode,
        'operatorName', operation_record.operator_name,
        'longitude', operation_record.longitude,
        'latitude', operation_record.latitude,
        'locationAccuracyM', operation_record.location_accuracy_m,
        'locationText', operation_record.location_text,
        'geofenceCenterLongitude', operation_record.geofence_center_longitude,
        'geofenceCenterLatitude', operation_record.geofence_center_latitude,
        'geofenceRadiusM', operation_record.geofence_radius_m,
        'distanceM', operation_record.distance_m,
        'insideGeofence', operation_record.inside_geofence,
        'outsideReason', operation_record.outside_reason,
        'grossWeightTon', operation_record.gross_weight_ton,
        'tareWeightTon', operation_record.tare_weight_ton,
        'weightTon', operation_record.weight_ton,
        'recognitionInfo', operation_record.recognition_info,
        'recognitionPayload', operation_record.recognition_payload,
        'photoUrls', operation_record.photo_urls,
        'weighbridgeTicketUrls', operation_record.weighbridge_ticket_urls,
        'completedAt', operation_record.completed_at,
        'remark', operation_record.remark,
        'createBy', operation_record.create_by,
        'createTime', operation_record.create_time,
        'updateBy', operation_record.update_by,
        'updateTime', operation_record.update_time
      )
    end
  );
end;
$function$;

create or replace function public.tms_complete_waybill_cargo_operation(
  p_waybill_id uuid,
  p_operation_type text,
  p_gross_weight_ton numeric,
  p_tare_weight_ton numeric,
  p_weight_ton numeric,
  p_photo_urls jsonb,
  p_weighbridge_ticket_urls jsonb,
  p_recognition_info text,
  p_recognition_payload jsonb,
  p_remark text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'app_private'
as $function$
declare
  waybill_record public.tms_waybill%rowtype;
  operation_record public.tms_waybill_cargo_operation%rowtype;
  is_driver boolean;
  is_manager boolean;
  operator_value text;
  recognition_value text;
  recognition_payload_value jsonb;
begin
  if p_operation_type not in ('loading', 'unloading') then
    raise exception '不支持的装卸货操作类型' using errcode = '22023';
  end if;
  if p_weight_ton is null or p_weight_ton <= 0 then
    raise exception '%净重必须大于 0 吨',
      case p_operation_type when 'loading' then '装货' else '卸货' end
      using errcode = '23514';
  end if;
  if p_gross_weight_ton is not null and p_gross_weight_ton <= 0 then
    raise exception '毛重必须大于 0 吨' using errcode = '23514';
  end if;
  if p_tare_weight_ton is not null and p_tare_weight_ton <= 0 then
    raise exception '皮重必须大于 0 吨' using errcode = '23514';
  end if;
  if p_gross_weight_ton is not null and p_tare_weight_ton is not null
    and p_gross_weight_ton < p_tare_weight_ton then
    raise exception '毛重不能小于皮重' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_photo_urls) then
    raise exception '请上传 1 至 9 张现场照片' using errcode = '23514';
  end if;
  if not app_private.tms_valid_url_array(p_weighbridge_ticket_urls) then
    raise exception '请上传 1 至 9 张磅单' using errcode = '23514';
  end if;

  recognition_value := nullif(btrim(p_recognition_info), '');
  if recognition_value is not null and char_length(recognition_value) > 10000 then
    raise exception '识别信息不能超过 10000 个字符' using errcode = '22001';
  end if;
  recognition_payload_value := coalesce(p_recognition_payload, '{}'::jsonb);
  if jsonb_typeof(recognition_payload_value) <> 'object' then
    raise exception '识别信息结构无效' using errcode = '22023';
  end if;

  select * into waybill_record
  from public.tms_waybill
  where id = p_waybill_id
  for update;
  if not found then
    raise exception '运单不存在' using errcode = 'P0002';
  end if;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_cargo_operation(p_operation_type)
    and (app_private.is_platform_super()
      or waybill_record.tenant_id = app_private.current_user_tenant_id());
  if not is_driver and not is_manager then
    raise exception '无权操作该运单' using errcode = '42501';
  end if;

  select * into operation_record
  from public.tms_waybill_cargo_operation
  where waybill_id = p_waybill_id and operation_type = p_operation_type
  for update;
  if not found then
    raise exception '请先完成%打卡',
      case p_operation_type when 'loading' then '装货' else '到达' end
      using errcode = '23514';
  end if;
  if operation_record.operation_status = 'completed' then
    return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
  end if;

  if p_operation_type = 'loading' and waybill_record.status not in ('accepted', 'loading') then
    raise exception '当前运单状态不支持提交装货信息' using errcode = '23514';
  end if;
  if p_operation_type = 'unloading' and waybill_record.status <> 'unloading' then
    raise exception '当前运单状态不支持提交卸货信息' using errcode = '23514';
  end if;

  update public.tms_waybill_cargo_operation
  set operation_status = 'completed',
      gross_weight_ton = p_gross_weight_ton,
      tare_weight_ton = p_tare_weight_ton,
      weight_ton = p_weight_ton,
      photo_urls = p_photo_urls,
      weighbridge_ticket_urls = p_weighbridge_ticket_urls,
      recognition_info = recognition_value,
      recognition_payload = recognition_payload_value,
      completed_at = coalesce(completed_at, now()),
      remark = nullif(btrim(p_remark), '')
  where id = operation_record.id
  returning * into operation_record;

  if p_operation_type = 'loading' then
    update public.tms_waybill
    set status = case when status = 'accepted' then 'loading' else status end,
        loaded_at = coalesce(loaded_at, operation_record.completed_at),
        cargo_weight_ton = p_weight_ton,
        pickup_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb)
          || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  else
    update public.tms_waybill
    set unloaded_at = coalesce(unloaded_at, operation_record.completed_at),
        delivery_photos = p_photo_urls,
        receipt_attachments = coalesce(receipt_attachments, '[]'::jsonb)
          || p_weighbridge_ticket_urls
    where id = waybill_record.id;
  end if;

  operator_value := app_private.tms_current_operator_name();
  insert into public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time, operator_name,
    location_text, longitude, latitude, payload, remark
  ) values (
    waybill_record.tenant_id, waybill_record.id,
    case p_operation_type when 'loading' then 'loaded' else 'unloaded' end,
    operation_record.completed_at, operator_value, operation_record.location_text,
    operation_record.longitude, operation_record.latitude,
    jsonb_build_object(
      'action', 'complete_' || p_operation_type,
      'source', 'driver',
      'weightTon', p_weight_ton,
      'grossWeightTon', p_gross_weight_ton,
      'tareWeightTon', p_tare_weight_ton,
      'photoCount', jsonb_array_length(p_photo_urls),
      'ticketCount', jsonb_array_length(p_weighbridge_ticket_urls),
      'checkinMode', operation_record.checkin_mode,
      'insideGeofence', operation_record.inside_geofence,
      'hasRecognitionInfo', recognition_value is not null,
      'recognitionConfidence', recognition_payload_value -> 'confidence'
    ),
    nullif(btrim(p_remark), '')
  );

  return public.tms_get_waybill_cargo_operation_context(p_waybill_id, p_operation_type);
end;
$function$;

grant execute on function public.tms_complete_waybill_cargo_operation(
  uuid, text, numeric, numeric, numeric, jsonb, jsonb, text, jsonb, text
) to authenticated, service_role;

notify pgrst, 'reload schema';

;
