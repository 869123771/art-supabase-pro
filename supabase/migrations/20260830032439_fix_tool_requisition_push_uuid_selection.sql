CREATE OR REPLACE FUNCTION public.smis_push_tool_requisition_items_secure(
  p_items jsonb,
  p_warehouse_id uuid,
  p_issuer_employee_id uuid,
  p_issue_date date DEFAULT CURRENT_DATE
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_tenant uuid;
  v_employee uuid;
  v_record_id uuid;
  v_no text;
  v_employee_row record;
  v_warehouse record;
  v_issuer record;
  v_item_ids uuid[];
BEGIN
  IF (SELECT auth.uid()) IS NULL
    OR NOT app_private.has_permission('SmisToolPersonalRequisition:Push') THEN
    RAISE EXCEPTION '当前账号没有下推发放的权限' USING errcode = '42501';
  END IF;

  IF jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array'
    OR jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION '请选择待发放的领用明细' USING errcode = '22023';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_items) AS item
    WHERE nullif(item ->> 'id', '') IS NULL
      OR coalesce((item ->> 'issue_quantity')::numeric, 0) <= 0
  ) THEN
    RAISE EXCEPTION '领用明细或发放数量无效' USING errcode = '22023';
  END IF;

  SELECT array_agg((item ->> 'id')::uuid)
  INTO v_item_ids
  FROM jsonb_array_elements(p_items) AS item;

  IF cardinality(v_item_ids) <> jsonb_array_length(p_items)
    OR cardinality(v_item_ids) <> (
      SELECT count(DISTINCT item_id)
      FROM unnest(v_item_ids) AS item_id
    ) THEN
    RAISE EXCEPTION '领用明细不能重复' USING errcode = '22023';
  END IF;

  SELECT requisition.tenant_id, requisition.employee_id
  INTO v_tenant, v_employee
  FROM public.smis_tool_personal_requisition_item AS item
  JOIN public.smis_tool_personal_requisition AS requisition
    ON requisition.id = item.requisition_id
  WHERE item.id = ANY(v_item_ids)
    AND item.status = 'pending_issue'
  LIMIT 1;

  IF v_tenant IS NULL
    OR (
      SELECT count(*)
      FROM public.smis_tool_personal_requisition_item
      WHERE id = ANY(v_item_ids)
    ) <> cardinality(v_item_ids)
    OR EXISTS (
      SELECT 1
      FROM public.smis_tool_personal_requisition_item AS item
      JOIN public.smis_tool_personal_requisition AS requisition
        ON requisition.id = item.requisition_id
      WHERE item.id = ANY(v_item_ids)
        AND (
          requisition.tenant_id <> v_tenant
          OR requisition.employee_id <> v_employee
          OR item.status <> 'pending_issue'
        )
    ) THEN
    RAISE EXCEPTION '只能选择同一领用人的待发放明细' USING errcode = '22023';
  END IF;

  IF NOT app_private.is_platform_super()
    AND v_tenant <> app_private.auth_user_tenant_id() THEN
    RAISE EXCEPTION '所选数据不属于当前租户' USING errcode = '42501';
  END IF;

  SELECT employee.*, organization.organization_name, position.position_name
  INTO v_employee_row
  FROM public.hr_employee AS employee
  LEFT JOIN public.sys_organization AS organization
    ON organization.id = employee.organization_id
  LEFT JOIN public.hr_position AS position
    ON position.id = employee.position_id
  WHERE employee.id = v_employee
    AND employee.tenant_id = v_tenant;

  SELECT *
  INTO v_warehouse
  FROM public.smis_storage_location
  WHERE id = p_warehouse_id
    AND tenant_id = v_tenant
    AND status = 'enabled';

  SELECT *
  INTO v_issuer
  FROM public.hr_employee
  WHERE id = p_issuer_employee_id
    AND tenant_id = v_tenant;

  IF v_employee_row.id IS NULL OR v_warehouse.id IS NULL OR v_issuer.id IS NULL THEN
    RAISE EXCEPTION '领用人、发放仓库或发放人无效' USING errcode = 'P0002';
  END IF;

  INSERT INTO public.smis_tool_issuance_record (
    tenant_id, issuance_no, employee_id, employee_no_snapshot, employee_name_snapshot,
    position_name_snapshot, organization_id, organization_name_snapshot, warehouse_id,
    warehouse_name_snapshot, issuer_employee_id, issuer_name_snapshot, issue_date, status
  )
  VALUES (
    v_tenant, app_private.next_document_number('smis.tool_issuance_record', v_tenant),
    v_employee_row.id, v_employee_row.employee_no, v_employee_row.employee_name,
    v_employee_row.position_name, v_employee_row.organization_id,
    v_employee_row.organization_name, v_warehouse.id, v_warehouse.location_name,
    v_issuer.id, v_issuer.employee_name, coalesce(p_issue_date, current_date), 'draft'
  )
  RETURNING id INTO v_record_id;

  INSERT INTO public.smis_tool_issuance_record_item (
    tenant_id, issuance_record_id, requisition_item_id, material_id,
    material_category_snapshot, material_name_snapshot, specification_model_snapshot,
    unit_snapshot, issue_quantity
  )
  SELECT
    v_tenant, v_record_id, requisition_item.id, requisition_item.material_id,
    requisition_item.material_category_snapshot, requisition_item.material_name_snapshot,
    requisition_item.specification_model_snapshot, requisition_item.unit_snapshot,
    (payload_item ->> 'issue_quantity')::numeric
  FROM jsonb_array_elements(p_items) AS payload_item
  JOIN public.smis_tool_personal_requisition_item AS requisition_item
    ON requisition_item.id = (payload_item ->> 'id')::uuid;

  v_no := app_private.post_tool_issuance_record(v_record_id);

  RETURN jsonb_build_object('id', v_record_id, 'issuanceNo', v_no);
END
$function$;

REVOKE ALL ON FUNCTION public.smis_push_tool_requisition_items_secure(jsonb, uuid, uuid, date)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.smis_push_tool_requisition_items_secure(jsonb, uuid, uuid, date)
TO authenticated;;
