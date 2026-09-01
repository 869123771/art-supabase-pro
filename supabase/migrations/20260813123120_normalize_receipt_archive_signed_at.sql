-- Driver execution is authoritative for the actual signed time. This also
-- repairs legacy Web records that stored a Shanghai wall-clock value as UTC.

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
  execution_signed_at timestamptz;
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

  SELECT signed_at INTO execution_signed_at
  FROM public.tms_waybill_execution_record
  WHERE waybill_id = waybill_record.id;

  receipt_at := COALESCE(
    execution_signed_at,
    CASE
      WHEN order_record.signed_at <= now() + interval '10 minutes' THEN order_record.signed_at
    END,
    p_signed_at,
    now()
  );
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

;
