-- Separate delivery-receipt archiving from vehicle-return completion.
-- The waybill is the authority for transport completion; an order receipt must
-- never advance a waybill to completed on its own.

DROP TRIGGER IF EXISTS tms_order_sync_completed_waybill ON public.tms_order;
DROP FUNCTION IF EXISTS public.trg_sync_completed_waybill_from_order();

CREATE OR REPLACE FUNCTION public.tms_archive_order_delivery_receipt(
  p_order_id uuid,
  p_signed_cod_amount numeric DEFAULT 0,
  p_receipt_image_urls jsonb DEFAULT '[]'::jsonb,
  p_signed_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO 'public', 'app_private'
AS $function$
DECLARE
  v_order public.tms_order%ROWTYPE;
  v_waybill public.tms_waybill%ROWTYPE;
  v_receipt_at timestamptz;
  v_operator_name text;
  v_changed boolean;
BEGIN
  IF p_signed_cod_amount IS NULL OR p_signed_cod_amount < 0 THEN
    RAISE EXCEPTION '代收货款金额不能小于 0';
  END IF;

  IF NOT app_private.tms_valid_url_array(p_receipt_image_urls, 1, 9) THEN
    RAISE EXCEPTION '请上传 1 至 9 张有效回单照片';
  END IF;

  SELECT *
  INTO v_order
  FROM public.tms_order
  WHERE id = p_order_id
    AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '订单不存在或已删除';
  END IF;

  IF NOT app_private.can_manage_tms()
     OR (
       NOT app_private.is_platform_super()
       AND v_order.tenant_id IS DISTINCT FROM app_private.current_tenant_id()
     ) THEN
    RAISE EXCEPTION '无权归档该订单回单';
  END IF;

  IF v_order.order_status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '仅已签收或已完成订单可归档回单，当前状态：%', v_order.order_status;
  END IF;

  SELECT w.*
  INTO v_waybill
  FROM public.tms_waybill w
  WHERE w.order_id = v_order.id
    AND w.is_deleted = false
  ORDER BY w.create_time DESC
  LIMIT 1
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '订单未关联运输运单';
  END IF;

  IF v_waybill.status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '运输运单尚未签收，当前状态：%', v_waybill.status;
  END IF;

  v_receipt_at := COALESCE(v_order.signed_at, p_signed_at, now());
  IF v_receipt_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION '签收时间不能晚于当前时间';
  END IF;

  v_changed :=
    v_order.signed_cod_amount IS DISTINCT FROM p_signed_cod_amount
    OR COALESCE(v_order.receipt_image_urls, '[]'::jsonb) IS DISTINCT FROM p_receipt_image_urls
    OR v_order.signed_at IS DISTINCT FROM v_receipt_at;

  UPDATE public.tms_order
  SET signed_cod_amount = p_signed_cod_amount,
      receipt_image_urls = p_receipt_image_urls,
      signed_at = v_receipt_at,
      update_time = now()
  WHERE id = v_order.id;

  IF v_changed THEN
    v_operator_name := app_private.tms_current_operator_name();

    INSERT INTO public.tms_waybill_event (
      waybill_id, event_type, event_time, location_name, remark,
      operator_name, payload, tenant_id, created_by
    ) VALUES (
      v_waybill.id,
      'receipt_archived',
      now(),
      COALESCE(v_waybill.route_end, v_order.receiving_address),
      'Web 端回单复核归档，不改变运输执行状态',
      v_operator_name,
      jsonb_build_object(
        'action', 'archive_receipt',
        'source', 'web',
        'receiptCount', jsonb_array_length(p_receipt_image_urls),
        'signedCodAmount', p_signed_cod_amount,
        'receiptSignedAt', v_receipt_at
      ),
      v_waybill.tenant_id,
      app_private.current_user_id()
    );
  END IF;

  RETURN jsonb_build_object(
    'orderId', v_order.id,
    'waybillId', v_waybill.id,
    'orderStatus', v_order.order_status,
    'waybillStatus', v_waybill.status,
    'receiptCount', jsonb_array_length(p_receipt_image_urls),
    'requiresReturnCompletion',
      v_waybill.status = 'signed'
      OR (
        v_waybill.status = 'completed'
        AND NOT EXISTS (
          SELECT 1
          FROM public.tms_waybill_execution_record e
          WHERE e.waybill_id = v_waybill.id
            AND e.return_time IS NOT NULL
            AND e.return_odometer_km IS NOT NULL
            AND app_private.tms_valid_url_array(e.return_photo_urls, 1, 9)
        )
      )
  );
END;
$function$;

COMMENT ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz)
IS 'Archives/reviews an order delivery receipt without changing order or waybill execution status.';

REVOKE ALL ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) FROM anon;
GRANT EXECUTE ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tms_archive_order_delivery_receipt(uuid, numeric, jsonb, timestamptz) TO service_role;

DROP FUNCTION IF EXISTS public.tms_complete_order_with_waybill(uuid, numeric, jsonb, timestamptz);

CREATE OR REPLACE FUNCTION public.trg_guard_tms_waybill_completion()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app_private'
AS $function$
BEGIN
  IF NEW.status <> 'completed' OR OLD.status = 'completed' THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.tms_waybill_execution_record e
    WHERE e.waybill_id = NEW.id
      AND e.departure_time IS NOT NULL
      AND e.departure_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(e.departure_photo_urls, 1, 9)
      AND e.signed_at IS NOT NULL
      AND NULLIF(btrim(e.signer_name), '') IS NOT NULL
      AND app_private.tms_valid_url_array(e.signature_urls, 1, 9)
      AND e.return_time IS NOT NULL
      AND e.return_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(e.return_photo_urls, 1, 9)
      AND e.completion_recorded_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION '回场档案不完整，不能完成运输运单';
  END IF;

  IF NEW.vehicle_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.vehicle_mileage_record m
    WHERE m.waybill_id = NEW.id
      AND m.end_mileage_km IS NOT NULL
  ) THEN
    RAISE EXCEPTION '车辆里程记录未生成，不能完成运输运单';
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tms_waybill_guard_completion_integrity ON public.tms_waybill;
CREATE TRIGGER tms_waybill_guard_completion_integrity
BEFORE UPDATE OF status ON public.tms_waybill
FOR EACH ROW
EXECUTE FUNCTION public.trg_guard_tms_waybill_completion();

CREATE OR REPLACE FUNCTION public.tms_complete_waybill_execution(
  p_waybill_id uuid,
  p_return_odometer_km numeric,
  p_return_photo_urls jsonb DEFAULT '[]'::jsonb,
  p_occurred_at timestamptz DEFAULT NULL,
  p_remark text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app_private'
AS $function$
DECLARE
  v_waybill public.tms_waybill%ROWTYPE;
  v_execution public.tms_waybill_execution_record%ROWTYPE;
  v_actor auth.users%ROWTYPE;
  v_occurred_at timestamptz := COALESCE(p_occurred_at, now());
  v_operator_name text;
  v_return_photo_count integer;
  v_repairing_incomplete_completion boolean := false;
BEGIN
  IF p_return_odometer_km IS NULL OR p_return_odometer_km < 0 THEN
    RAISE EXCEPTION '回场里程不能为空且不能小于 0';
  END IF;

  IF NOT app_private.tms_valid_url_array(p_return_photo_urls, 1, 9) THEN
    RAISE EXCEPTION '请上传 1 至 9 张有效回场照片';
  END IF;

  v_return_photo_count := jsonb_array_length(p_return_photo_urls);

  SELECT *
  INTO v_waybill
  FROM public.tms_waybill
  WHERE id = p_waybill_id
    AND is_deleted = false
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION '运单不存在或已删除';
  END IF;

  SELECT *
  INTO v_execution
  FROM public.tms_waybill_execution_record
  WHERE waybill_id = v_waybill.id
  FOR UPDATE;

  IF v_waybill.status = 'completed'
     AND v_execution.return_time IS NOT NULL
     AND v_execution.return_odometer_km IS NOT NULL
     AND app_private.tms_valid_url_array(v_execution.return_photo_urls, 1, 9) THEN
    RETURN public.tms_get_waybill_execution_context(p_waybill_id);
  END IF;

  IF v_waybill.status NOT IN ('signed', 'completed') THEN
    RAISE EXCEPTION '当前运单状态不允许确认回场：%', v_waybill.status;
  END IF;

  v_repairing_incomplete_completion := v_waybill.status = 'completed';

  SELECT *
  INTO v_actor
  FROM auth.users
  WHERE id = auth.uid();

  IF NOT (
    app_private.is_platform_super()
    OR (
      app_private.is_active_tenant_user()
      AND (
        app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
        OR app_private.can_manage_waybill_execution_action('completion')
      )
    )
  ) THEN
    RAISE EXCEPTION '无权确认该运单回场';
  END IF;

  IF v_execution.signed_at IS NULL THEN
    RAISE EXCEPTION '签收记录不存在，不能确认回场';
  END IF;

  IF v_execution.departure_odometer_km IS NULL THEN
    RAISE EXCEPTION '发车里程不存在，不能确认回场';
  END IF;

  IF p_return_odometer_km < v_execution.departure_odometer_km THEN
    RAISE EXCEPTION '回场里程不能小于发车里程';
  END IF;

  IF v_occurred_at < v_execution.signed_at THEN
    RAISE EXCEPTION '回场时间不能早于签收时间';
  END IF;

  IF v_occurred_at > now() + interval '10 minutes' THEN
    RAISE EXCEPTION '回场时间不能晚于当前时间';
  END IF;

  v_operator_name := app_private.tms_current_operator_name();

  INSERT INTO public.tms_waybill_execution_record (
    waybill_id, tenant_id, return_time, return_odometer_km,
    return_photo_urls, return_remark, completion_operator_name,
    completion_recorded_at, created_by, updated_by
  ) VALUES (
    v_waybill.id,
    v_waybill.tenant_id,
    v_occurred_at,
    p_return_odometer_km,
    p_return_photo_urls,
    NULLIF(btrim(COALESCE(p_remark, '')), ''),
    v_operator_name,
    now(),
    app_private.current_user_id(),
    app_private.current_user_id()
  )
  ON CONFLICT (waybill_id) DO UPDATE
  SET return_time = EXCLUDED.return_time,
      return_odometer_km = EXCLUDED.return_odometer_km,
      return_photo_urls = EXCLUDED.return_photo_urls,
      return_remark = EXCLUDED.return_remark,
      completion_operator_name = EXCLUDED.completion_operator_name,
      completion_recorded_at = EXCLUDED.completion_recorded_at,
      updated_by = EXCLUDED.updated_by,
      update_time = now();

  IF v_waybill.vehicle_id IS NOT NULL THEN
    INSERT INTO public.vehicle_mileage_record (
      tenant_id, vehicle_id, waybill_id, record_date,
      start_mileage_km, end_mileage_km, record_source,
      remark, created_by, updated_by
    ) VALUES (
      v_waybill.tenant_id,
      v_waybill.vehicle_id,
      v_waybill.id,
      (v_occurred_at AT TIME ZONE 'Asia/Shanghai')::date,
      v_execution.departure_odometer_km,
      p_return_odometer_km,
      'waybill_completion',
      concat('运单 ', v_waybill.waybill_no, ' 回场自动生成'),
      app_private.current_user_id(),
      app_private.current_user_id()
    )
    ON CONFLICT (waybill_id) DO UPDATE
    SET vehicle_id = EXCLUDED.vehicle_id,
        record_date = EXCLUDED.record_date,
        start_mileage_km = EXCLUDED.start_mileage_km,
        end_mileage_km = EXCLUDED.end_mileage_km,
        record_source = EXCLUDED.record_source,
        remark = EXCLUDED.remark,
        updated_by = EXCLUDED.updated_by,
        update_time = now();
  END IF;

  IF v_repairing_incomplete_completion THEN
    UPDATE public.tms_waybill
    SET completed_at = v_occurred_at,
        update_time = now()
    WHERE id = v_waybill.id;
  ELSE
    UPDATE public.tms_waybill
    SET status = 'completed',
        completed_at = v_occurred_at,
        update_time = now()
    WHERE id = v_waybill.id;
  END IF;

  INSERT INTO public.tms_waybill_event (
    waybill_id, event_type, event_time, location_name, remark,
    operator_name, payload, tenant_id, created_by
  ) VALUES (
    v_waybill.id,
    'completed',
    v_occurred_at,
    v_waybill.route_start,
    CASE
      WHEN v_repairing_incomplete_completion THEN concat(
        '补录回场；',
        COALESCE(NULLIF(btrim(COALESCE(p_remark, '')), ''), '无备注')
      )
      ELSE NULLIF(btrim(COALESCE(p_remark, '')), '')
    END,
    v_operator_name,
    jsonb_build_object(
      'action', CASE WHEN v_repairing_incomplete_completion THEN 'repair_completion' ELSE 'complete' END,
      'source', CASE
        WHEN app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
          THEN 'driver'
        ELSE 'web'
      END,
      'repairingIncompleteCompletion', v_repairing_incomplete_completion,
      'returnOdometerKm', p_return_odometer_km,
      'returnPhotoCount', v_return_photo_count
    ),
    v_waybill.tenant_id,
    app_private.current_user_id()
  );

  RETURN public.tms_get_waybill_execution_context(p_waybill_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.tms_complete_waybill_execution(uuid, numeric, jsonb, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tms_complete_waybill_execution(uuid, numeric, jsonb, timestamptz, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.tms_complete_waybill_execution(uuid, numeric, jsonb, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tms_complete_waybill_execution(uuid, numeric, jsonb, timestamptz, text) TO service_role;

CREATE OR REPLACE FUNCTION public.tms_get_waybill_execution_context(p_waybill_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'app_private'
AS $function$
DECLARE
  v_waybill public.tms_waybill%ROWTYPE;
  v_execution public.tms_waybill_execution_record%ROWTYPE;
  v_actor auth.users%ROWTYPE;
  v_can_depart boolean := false;
  v_can_sign boolean := false;
  v_can_complete boolean := false;
  v_needs_return_completion boolean := false;
  v_departure_photo_count integer := 0;
  v_return_photo_count integer := 0;
  v_signature_count integer := 0;
BEGIN
  SELECT *
  INTO v_waybill
  FROM public.tms_waybill
  WHERE id = p_waybill_id
    AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION '运单不存在或已删除';
  END IF;

  SELECT *
  INTO v_execution
  FROM public.tms_waybill_execution_record
  WHERE waybill_id = v_waybill.id;

  SELECT *
  INTO v_actor
  FROM auth.users
  WHERE id = auth.uid();

  IF NOT (
    app_private.is_platform_super()
    OR app_private.is_active_tenant_user()
    OR app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
  ) THEN
    RAISE EXCEPTION '无权查看该运单执行信息';
  END IF;

  v_departure_photo_count := COALESCE(jsonb_array_length(v_execution.departure_photo_urls), 0);
  v_return_photo_count := COALESCE(jsonb_array_length(v_execution.return_photo_urls), 0);
  v_signature_count := COALESCE(jsonb_array_length(v_execution.signature_urls), 0);

  v_needs_return_completion :=
    v_waybill.status IN ('signed', 'completed')
    AND NOT (
      v_execution.return_time IS NOT NULL
      AND v_execution.return_odometer_km IS NOT NULL
      AND app_private.tms_valid_url_array(v_execution.return_photo_urls, 1, 9)
      AND v_execution.completion_recorded_at IS NOT NULL
    );

  v_can_depart := v_waybill.status = 'loaded'
    AND (
      app_private.is_platform_super()
      OR app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
      OR app_private.can_manage_waybill_execution_action('departure')
    );

  v_can_sign := v_waybill.status IN ('unloading', 'signed')
    AND (
      app_private.is_platform_super()
      OR app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
      OR app_private.can_manage_waybill_execution_action('signature')
    );

  v_can_complete := v_needs_return_completion
    AND v_execution.signed_at IS NOT NULL
    AND v_execution.departure_odometer_km IS NOT NULL
    AND (
      app_private.is_platform_super()
      OR app_private.is_assigned_waybill_driver(v_waybill.id, v_actor.email, v_actor.raw_user_meta_data)
      OR app_private.can_manage_waybill_execution_action('completion')
    );

  RETURN jsonb_build_object(
    'waybill', jsonb_build_object(
      'id', v_waybill.id,
      'waybillNo', v_waybill.waybill_no,
      'status', v_waybill.status,
      'routeStart', v_waybill.route_start,
      'routeEnd', v_waybill.route_end,
      'driverName', v_waybill.driver_name,
      'driverPhone', v_waybill.driver_phone,
      'vehiclePlateNo', v_waybill.vehicle_plate_no
    ),
    'record', jsonb_build_object(
      'departureTime', v_execution.departure_time,
      'departureOdometerKm', v_execution.departure_odometer_km,
      'departurePhotoUrls', COALESCE(v_execution.departure_photo_urls, '[]'::jsonb),
      'departurePhotoCount', v_departure_photo_count,
      'departureRemark', v_execution.departure_remark,
      'departureOperatorName', v_execution.departure_operator_name,
      'departureRecordedAt', v_execution.departure_recorded_at,
      'signedAt', v_execution.signed_at,
      'signerName', v_execution.signer_name,
      'signatureUrls', COALESCE(v_execution.signature_urls, '[]'::jsonb),
      'signatureCount', v_signature_count,
      'signRemark', v_execution.sign_remark,
      'signOperatorName', v_execution.sign_operator_name,
      'signRecordedAt', v_execution.sign_recorded_at,
      'returnTime', v_execution.return_time,
      'returnOdometerKm', v_execution.return_odometer_km,
      'returnPhotoUrls', COALESCE(v_execution.return_photo_urls, '[]'::jsonb),
      'returnPhotoCount', v_return_photo_count,
      'returnRemark', v_execution.return_remark,
      'completionOperatorName', v_execution.completion_operator_name,
      'completionRecordedAt', v_execution.completion_recorded_at
    ),
    'needsReturnCompletion', v_needs_return_completion,
    'canDepart', v_can_depart,
    'canSign', v_can_sign,
    'canComplete', v_can_complete
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.tms_get_waybill_execution_context(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tms_get_waybill_execution_context(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.tms_get_waybill_execution_context(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tms_get_waybill_execution_context(uuid) TO service_role;

COMMENT ON FUNCTION public.tms_complete_waybill_execution(uuid, numeric, jsonb, timestamptz, text)
IS 'Completes a signed waybill after return evidence, or repairs a historical completed waybill whose return archive is missing.';

;
