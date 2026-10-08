-- Compare the batch summary reader with its secured source RPCs and verify tenant scope.
BEGIN;
CREATE TEMP TABLE vms_query_batch_ctx AS
WITH super_user AS (
  SELECT u.auth_user_id FROM public.sys_user u
  JOIN public.sys_role r ON r.tenant_id = u.tenant_id AND r.role_code = ANY(u.user_roles)
  WHERE u.status = '1' AND u.deleted_at IS NULL AND u.auth_user_id IS NOT NULL
    AND r.enabled AND r.builtin_type = 'platform_super'
  LIMIT 1
), ordinary_user AS (
  SELECT u.auth_user_id, u.tenant_id, v.id AS vehicle_id
  FROM public.sys_user u
  JOIN public.mdm_vehicle v ON v.tenant_id = u.tenant_id
  WHERE u.status = '1' AND u.deleted_at IS NULL AND u.auth_user_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.sys_role r
      WHERE r.tenant_id = u.tenant_id AND r.role_code = ANY(u.user_roles)
        AND r.builtin_type = 'platform_super'
    )
    AND EXISTS (
      SELECT 1 FROM public.sys_role r
      JOIN public.sys_role_menu rm ON rm.role_id = r.id
      JOIN public.sys_menu m ON m.id = rm.menu_id
      WHERE r.tenant_id = u.tenant_id AND r.enabled
        AND r.role_code = ANY(u.user_roles) AND m.name = 'VehicleQuery'
    )
  LIMIT 1
)
SELECT s.auth_user_id AS super_id, o.auth_user_id AS ordinary_id,
  o.tenant_id AS own_tenant, o.vehicle_id,
  (SELECT id FROM public.sys_tenant WHERE id <> o.tenant_id LIMIT 1) AS other_tenant
FROM super_user s CROSS JOIN ordinary_user o;
DO $test$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM vms_query_batch_ctx
    WHERE super_id IS NOT NULL AND ordinary_id IS NOT NULL
      AND vehicle_id IS NOT NULL AND other_tenant IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'VMS batch scope fixtures are incomplete';
  END IF;
END $test$;
GRANT SELECT ON vms_query_batch_ctx TO authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object('sub', super_id, 'role', 'authenticated')::text, true)
FROM vms_query_batch_ctx;
SELECT set_config('request.headers', '{}', true);
SET LOCAL ROLE authenticated;
DO $test$ DECLARE ctx record; got jsonb; BEGIN
  SELECT * INTO ctx FROM vms_query_batch_ctx;
  got := public.vms_get_vehicle_query_summary_records_secure(ARRAY[ctx.vehicle_id]);
  IF NOT got ? ctx.vehicle_id::text THEN
    RAISE EXCEPTION 'Platform all could not read vehicle summary';
  END IF;
  IF got->ctx.vehicle_id::text->'insurance' IS DISTINCT FROM
      (public.vms_list_vehicle_insurance_secure(p_from => 0, p_to => 499, p_vehicle_id => ctx.vehicle_id)->'records')
    OR got->ctx.vehicle_id::text->'inspection' IS DISTINCT FROM
      (public.vms_list_vehicle_inspections_secure(p_from => 0, p_to => 499, p_vehicle_id => ctx.vehicle_id)->'records')
    OR got->ctx.vehicle_id::text->'maintenance' IS DISTINCT FROM
      (public.vms_list_vehicle_maintenance_secure(p_from => 0, p_to => 499,
        p_vehicle_id => ctx.vehicle_id, p_maintenance_type => 'maintenance')->'records')
    OR got->ctx.vehicle_id::text->'mileage' IS DISTINCT FROM
      (public.vms_list_vehicle_mileage_secure(p_from => 0, p_to => 499, p_vehicle_id => ctx.vehicle_id)->'records') THEN
    RAISE EXCEPTION 'Batch records differ from secured source readers';
  END IF;
  PERFORM set_config('request.headers', jsonb_build_object('x-art-tenant-scope', ctx.other_tenant)::text, true);
  IF public.vms_get_vehicle_query_summary_records_secure(ARRAY[ctx.vehicle_id]) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'Platform selected scope leaked vehicle summary';
  END IF;
  PERFORM set_config('request.headers', jsonb_build_object('x-art-tenant-scope', ctx.own_tenant)::text, true);
  IF NOT public.vms_get_vehicle_query_summary_records_secure(ARRAY[ctx.vehicle_id]) ? ctx.vehicle_id::text THEN
    RAISE EXCEPTION 'Platform selected scope missed vehicle summary';
  END IF;
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', ctx.ordinary_id, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.headers', '{}', true);
  IF NOT public.vms_get_vehicle_query_summary_records_secure(ARRAY[ctx.vehicle_id]) ? ctx.vehicle_id::text THEN
    RAISE EXCEPTION 'Ordinary own scope missed vehicle summary';
  END IF;
  PERFORM set_config('request.headers', jsonb_build_object('x-art-tenant-scope', ctx.other_tenant)::text, true);
  IF NOT public.vms_get_vehicle_query_summary_records_secure(ARRAY[ctx.vehicle_id]) ? ctx.vehicle_id::text THEN
    RAISE EXCEPTION 'Forged ordinary header changed vehicle summary scope';
  END IF;
END $test$;
ROLLBACK;
