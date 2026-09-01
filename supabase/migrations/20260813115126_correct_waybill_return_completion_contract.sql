-- Align the return-completion repair with the deployed TMS schema and preserve
-- the established RPC response contract used by Web and the driver app.

CREATE OR REPLACE FUNCTION public.tms_archive_order_delivery_receipt(
  p_order_id uuid,
  p_signed_cod_amount numeric DEFAULT 0,
  p_receipt_image_urls jsonb DEFAULT '[]'::jsonb,
  p_signed_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app_private'
AS $function$
DECLARE
  order_record public.tms_order%ROWTYPE;
  waybill_record public.tms_waybill%ROWTYPE;
  receipt_at timestamptz;
  operator_value text;
  data_changed boolean;
BEGIN
  IF p_signed_cod_amount IS NULL OR p_signed_cod_amount < 0 THEN
    RAISE EXCEPTION '代收货款金额不能小于 0' USING ERRCODE = '23514';
  END IF;
  IF NOT app_private.tms_valid_url_array(p_receipt_image_urls) THEN
    RAISE EXCEPTION '请上传 1 至 9 张有效回单照片' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO order_record
  FROM public.tms_order
  WHERE id = p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '订单不存在' USING ERRCODE = 'P0002';
  END IF;

  IF NOT app_private.can_manage_tms()
     OR (
       NOT app_private.is_platform_super()
       AND order_record.tenant_id IS DISTINCT FROM app_private.current_user_tenant_id()
     ) THEN
    RAISE EXCEPTION '无权归档该订单回单' USING ERRCODE = '42501';
  END IF;
  IF order_record.order_status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '仅已签收或已完成订单可归档回单，当前状态：%', order_record.order_status
      USING ERRCODE = '23514';
  END IF;

  SELECT * INTO waybill_record
  FROM public.tms_waybill
  WHERE order_id = order_record.id
  ORDER BY create_time DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '订单未关联运输运单' USING ERRCODE = 'P0002';
  END IF;
  IF waybill_record.status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '运输运单尚未签收，当前状态：%', waybill_record.status
      USING ERRCODE = '23514';
  END IF;

  receipt_at := COALESCE(order_record.signed_at, p_signed_at, now());
  IF receipt_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION '签收时间不能晚于当前时间' USING ERRCODE = '23514';
  END IF;

  data_changed :=
    order_record.signed_cod_amount IS DISTINCT FROM p_signed_cod_amount
    OR COALESCE(order_record.receipt_image_urls, '[]'::jsonb) IS DISTINCT FROM p_receipt_image_urls
    OR order_record.signed_at IS DISTINCT FROM receipt_at;

  UPDATE public.tms_order
  SET signed_cod_amount = p_signed_cod_amount,
      receipt_image_urls = p_receipt_image_urls,
      signed_at = receipt_at,
      update_time = now()
  WHERE id = order_record.id;

  IF data_changed THEN
    operator_value := app_private.tms_current_operator_name();
    INSERT INTO public.tms_waybill_event (
      tenant_id, waybill_id, event_type, event_time,
      operator_name, location_text, payload, remark
    ) VALUES (
      waybill_record.tenant_id,
      waybill_record.id,
      'receipt_archived',
      now(),
      operator_value,
      waybill_record.receiver_address,
      jsonb_build_object(
        'action', 'archive_receipt',
        'source', 'web',
        'receiptCount', jsonb_array_length(p_receipt_image_urls),
        'signedCodAmount', p_signed_cod_amount,
        'receiptSignedAt', receipt_at
      ),
      'Web 端回单复核归档，不改变运输执行状态'
    );
  END IF;

  RETURN jsonb_build_object(
    'orderId', order_record.id,
    'waybillId', waybill_record.id,
    'orderStatus', order_record.order_status,
    'waybillStatus', waybill_record.status,
    'receiptCount', jsonb_array_length(p_receipt_image_urls),
    'requiresReturnCompletion',
      waybill_record.status = 'signed'
      OR (
        waybill_record.status = 'completed'
        AND NOT EXISTS (
          SELECT 1
          FROM public.tms_waybill_execution_record execution
          WHERE execution.waybill_id = waybill_record.id
            AND execution.return_time IS NOT NULL
            AND execution.return_odometer_km IS NOT NULL
            AND app_private.tms_valid_url_array(execution.return_photo_urls)
            AND execution.completion_recorded_at IS NOT NULL
        )
      )
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.trg_guard_tms_waybill_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app_private'
AS $function$
BEGIN
  IF NEW.status <> 'completed' OR OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tms_waybill_execution_record execution
    WHERE execution.waybill_id = NEW.id
      AND execution.departure_time IS NOT NULL
      AND execution.departure_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(execution.departure_photo_urls)
      AND execution.signed_at IS NOT NULL
      AND NULLIF(btrim(execution.signer_name), '') IS NOT NULL
      AND app_private.tms_valid_url_array(execution.receipt_urls)
      AND app_private.tms_valid_url_array(execution.signature_urls)
      AND execution.return_time IS NOT NULL
      AND execution.return_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(execution.return_photo_urls)
      AND execution.completion_recorded_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION '回场档案不完整，不能完成运输运单' USING ERRCODE = '23514';
  END IF;

  IF NEW.vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.vehicle_mileage_record mileage
    WHERE mileage.waybill_id = NEW.id
      AND mileage.end_mileage IS NOT NULL
  ) THEN
    RAISE EXCEPTION '车辆里程记录未生成，不能完成运输运单' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tms_waybill_guard_completion_integrity ON public.tms_waybill;
CREATE TRIGGER tms_waybill_guard_completion_integrity
BEFORE UPDATE OF status ON public.tms_waybill
FOR EACH ROW
EXECUTE FUNCTION public.trg_guard_tms_waybill_completion();

DROP FUNCTION IF EXISTS public.tms_complete_waybill_execution(
  uuid, numeric, jsonb, timestamptz, text
);

CREATE OR REPLACE FUNCTION public.tms_complete_waybill_execution(
  p_waybill_id uuid,
  p_return_time timestamptz,
  p_return_odometer_km numeric,
  p_photo_urls jsonb,
  p_remark text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app_private'
AS $function$
DECLARE
  waybill_record public.tms_waybill%ROWTYPE;
  execution_record public.tms_waybill_execution_record%ROWTYPE;
  vehicle_record public.vehicle_archive%ROWTYPE;
  operator_value text;
  occurred_at timestamptz;
  is_driver boolean;
  is_manager boolean;
  repairing_incomplete_completion boolean := false;
BEGIN
  IF p_return_odometer_km IS NULL OR p_return_odometer_km < 0 THEN
    RAISE EXCEPTION '收车里程必须大于或等于 0 公里' USING ERRCODE = '23514';
  END IF;
  IF NOT app_private.tms_valid_url_array(p_photo_urls) THEN
    RAISE EXCEPTION '请上传 1 至 9 张收车凭证照片' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO waybill_record
  FROM public.tms_waybill
  WHERE id = p_waybill_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION '运单不存在' USING ERRCODE = 'P0002';
  END IF;

  is_driver := app_private.can_access_assigned_waybill(p_waybill_id);
  is_manager := app_private.can_manage_waybill_execution_action('completion')
    AND (
      app_private.is_platform_super()
      OR waybill_record.tenant_id = app_private.current_user_tenant_id()
    );
  IF NOT is_driver AND NOT is_manager THEN
    RAISE EXCEPTION '无权完成该运单' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO execution_record
  FROM public.tms_waybill_execution_record
  WHERE waybill_id = p_waybill_id
  FOR UPDATE;

  IF waybill_record.status = 'completed'
     AND execution_record.return_time IS NOT NULL
     AND execution_record.return_odometer_km IS NOT NULL
     AND app_private.tms_valid_url_array(execution_record.return_photo_urls)
     AND execution_record.completion_recorded_at IS NOT NULL THEN
    RETURN public.tms_get_waybill_execution_context(p_waybill_id);
  END IF;
  IF waybill_record.status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '仅已签收运单可以确认回场' USING ERRCODE = '23514';
  END IF;
  repairing_incomplete_completion := waybill_record.status = 'completed';

  IF execution_record.signed_at IS NULL THEN
    RAISE EXCEPTION '签收记录不完整，无法确认回场' USING ERRCODE = '23514';
  END IF;
  IF execution_record.departure_odometer_km IS NULL
     OR p_return_odometer_km < execution_record.departure_odometer_km THEN
    RAISE EXCEPTION '收车里程不能小于出车里程 % 公里', execution_record.departure_odometer_km
      USING ERRCODE = '23514';
  END IF;

  occurred_at := COALESCE(p_return_time, now());
  IF occurred_at < execution_record.signed_at
     OR occurred_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION '收车时间必须晚于签收时间且不能超过当前时间 10 分钟'
      USING ERRCODE = '23514';
  END IF;
  operator_value := app_private.tms_current_operator_name();

  UPDATE public.tms_waybill_execution_record
  SET return_time = occurred_at,
      return_odometer_km = p_return_odometer_km,
      return_photo_urls = p_photo_urls,
      completion_remark = NULLIF(btrim(p_remark), ''),
      completion_operator_name = operator_value,
      completion_recorded_at = now(),
      update_time = now()
  WHERE id = execution_record.id;

  SELECT * INTO vehicle_record
  FROM public.vehicle_archive
  WHERE id = waybill_record.vehicle_id;

  IF vehicle_record.id IS NOT NULL THEN
    INSERT INTO public.vehicle_mileage_record (
      tenant_id, vehicle_id, waybill_id, plate_no, company_name,
      start_time, end_time, start_mileage, end_mileage, running_mileage
    ) VALUES (
      waybill_record.tenant_id,
      vehicle_record.id,
      waybill_record.id,
      vehicle_record.plate_no,
      vehicle_record.company_name,
      execution_record.departure_time,
      occurred_at,
      execution_record.departure_odometer_km,
      p_return_odometer_km,
      p_return_odometer_km - execution_record.departure_odometer_km
    )
    ON CONFLICT (waybill_id) WHERE waybill_id IS NOT NULL DO UPDATE SET
      end_time = EXCLUDED.end_time,
      end_mileage = EXCLUDED.end_mileage,
      running_mileage = EXCLUDED.running_mileage,
      update_time = now();
  END IF;

  UPDATE public.tms_waybill
  SET status = 'completed',
      completed_at = occurred_at,
      update_time = now()
  WHERE id = waybill_record.id;

  INSERT INTO public.tms_waybill_event (
    tenant_id, waybill_id, event_type, event_time,
    operator_name, location_text, payload, remark
  ) VALUES (
    waybill_record.tenant_id,
    waybill_record.id,
    'completed',
    occurred_at,
    operator_value,
    concat_ws(' - ', waybill_record.origin_city, waybill_record.destination_city),
    jsonb_build_object(
      'action', CASE WHEN repairing_incomplete_completion THEN 'repair_completion' ELSE 'complete' END,
      'source', CASE WHEN is_driver THEN 'driver' ELSE 'web' END,
      'repairingIncompleteCompletion', repairing_incomplete_completion,
      'returnOdometerKm', p_return_odometer_km,
      'runningMileageKm', p_return_odometer_km - execution_record.departure_odometer_km,
      'photoCount', jsonb_array_length(p_photo_urls)
    ),
    CASE
      WHEN repairing_incomplete_completion THEN concat('补录历史缺失回场；', COALESCE(NULLIF(btrim(p_remark), ''), '无备注'))
      ELSE NULLIF(btrim(p_remark), '')
    END
  );

  RETURN public.tms_get_waybill_execution_context(p_waybill_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.tms_complete_waybill_execution(uuid, timestamptz, numeric, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tms_complete_waybill_execution(uuid, timestamptz, numeric, jsonb, text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.tms_get_waybill_execution_context(p_waybill_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'app_private'
AS $function$
DECLARE
  waybill_record public.tms_waybill%ROWTYPE;
  execution_record public.tms_waybill_execution_record%ROWTYPE;
  loading_status_value text;
  unloading_status_value text;
  arrival_event public.tms_waybill_event%ROWTYPE;
  can_access boolean;
  needs_return_completion boolean := false;
BEGIN
  SELECT * INTO waybill_record
  FROM public.tms_waybill
  WHERE id = p_waybill_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION '运单不存在' USING ERRCODE = 'P0002';
  END IF;

  can_access := app_private.can_access_assigned_waybill(p_waybill_id)
    OR (
      app_private.is_active_tenant_user()
      AND (
        app_private.is_platform_super()
        OR waybill_record.tenant_id = app_private.current_user_tenant_id()
      )
    );
  IF NOT can_access THEN
    RAISE EXCEPTION '无权查看该运单执行信息' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO execution_record
  FROM public.tms_waybill_execution_record
  WHERE waybill_id = p_waybill_id;

  SELECT operation_status INTO loading_status_value
  FROM public.tms_waybill_cargo_operation
  WHERE waybill_id = p_waybill_id AND operation_type = 'loading';

  SELECT operation_status INTO unloading_status_value
  FROM public.tms_waybill_cargo_operation
  WHERE waybill_id = p_waybill_id AND operation_type = 'unloading';

  SELECT * INTO arrival_event
  FROM public.tms_waybill_event
  WHERE waybill_id = p_waybill_id AND event_type = 'arrived'
  ORDER BY event_time DESC, create_time DESC
  LIMIT 1;

  needs_return_completion :=
    waybill_record.status IN ('signed', 'completed')
    AND NOT (
      execution_record.return_time IS NOT NULL
      AND execution_record.return_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(execution_record.return_photo_urls)
      AND execution_record.completion_recorded_at IS NOT NULL
    );

  RETURN jsonb_build_object(
    'waybillId', waybill_record.id,
    'waybillStatus', waybill_record.status,
    'loadingStatus', loading_status_value,
    'unloadingStatus', unloading_status_value,
    'arrivalTime', arrival_event.event_time,
    'arrivalAddress', arrival_event.location_text,
    'arrivalLongitude', arrival_event.longitude,
    'arrivalLatitude', arrival_event.latitude,
    'canAccept', waybill_record.status = 'pending'
      AND app_private.can_access_assigned_waybill(p_waybill_id),
    'canDepart', waybill_record.status = 'loading'
      AND loading_status_value = 'completed'
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('departure')
      ),
    'canArrive', waybill_record.status = 'transporting'
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('arrival')
      ),
    'canUnload', waybill_record.status IN ('arrived', 'unloading')
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('arrival')
      ),
    'canSign', waybill_record.status IN ('unloading', 'signed')
      AND unloading_status_value = 'completed'
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('signature')
      ),
    'canComplete', needs_return_completion
      AND execution_record.signed_at IS NOT NULL
      AND execution_record.departure_odometer_km IS NOT NULL
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('completion')
      ),
    'canCancel', waybill_record.status IN ('pending', 'accepted')
      AND (
        app_private.can_access_assigned_waybill(p_waybill_id)
        OR app_private.can_manage_waybill_execution_action('cancel')
      ),
    'needsReturnCompletion', needs_return_completion,
    'record', CASE
      WHEN execution_record.id IS NULL THEN NULL
      ELSE jsonb_build_object(
        'id', execution_record.id,
        'tenantId', execution_record.tenant_id,
        'waybillId', execution_record.waybill_id,
        'departureTime', execution_record.departure_time,
        'departureOdometerKm', execution_record.departure_odometer_km,
        'departurePhotoUrls', COALESCE(execution_record.departure_photo_urls, '[]'::jsonb),
        'departureRemark', execution_record.departure_remark,
        'departureOperatorName', execution_record.departure_operator_name,
        'departureRecordedAt', execution_record.departure_recorded_at,
        'signedAt', execution_record.signed_at,
        'signerName', execution_record.signer_name,
        'receiptUrls', COALESCE(execution_record.receipt_urls, '[]'::jsonb),
        'signatureUrls', COALESCE(execution_record.signature_urls, '[]'::jsonb),
        'signatureRemark', execution_record.signature_remark,
        'signatureOperatorName', execution_record.signature_operator_name,
        'signatureRecordedAt', execution_record.signature_recorded_at,
        'returnTime', execution_record.return_time,
        'returnOdometerKm', execution_record.return_odometer_km,
        'returnPhotoUrls', COALESCE(execution_record.return_photo_urls, '[]'::jsonb),
        'completionRemark', execution_record.completion_remark,
        'completionOperatorName', execution_record.completion_operator_name,
        'completionRecordedAt', execution_record.completion_recorded_at,
        'createTime', execution_record.create_time,
        'updateTime', execution_record.update_time
      )
    END
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.tms_get_waybill_execution_context(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tms_get_waybill_execution_context(uuid) TO authenticated, service_role;

COMMENT ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz)
IS 'Archives an order receipt without changing transport execution status.';
COMMENT ON FUNCTION public.tms_complete_waybill_execution(uuid, timestamptz, numeric, jsonb, text)
IS 'Completes a signed waybill after return evidence, or repairs a historical completed waybill whose return archive is missing.';

;
