-- Read-only assertions against posted opening documents; no business data is changed.
BEGIN;
DO $test$
DECLARE
  report jsonb;
  row_data jsonb;
  initial record;
  matched integer := 0;
BEGIN
  report := public.wms_inventory_report_secure('ledger', p_limit => 200);
  FOR initial IN
    SELECT movement.target_batch_id, line.opening_quantity, line.base_quantity,
      document.document_no
    FROM public.wms_initial_stock_line line
    JOIN public.wms_initial_stock_document document
      ON document.id = line.document_id AND document.tenant_id = line.tenant_id
    JOIN public.wms_inventory_movement movement
      ON movement.id = line.movement_id AND movement.tenant_id = line.tenant_id
    WHERE document.status = 'approved'
  LOOP
    SELECT value INTO row_data FROM jsonb_array_elements(report->'data')
    WHERE value->>'batch_id' = initial.target_batch_id::text;
    IF row_data IS NULL THEN CONTINUE; END IF;
    matched := matched + 1;
    IF (row_data->>'opening_quantity')::numeric <> initial.opening_quantity THEN
      RAISE EXCEPTION 'Opening quantity differs from approved initial stock line';
    END IF;
    IF (row_data->>'opening_quantity')::numeric * (row_data->>'basic_factor')::numeric
      <> initial.base_quantity THEN
      RAISE EXCEPTION 'Opening basic quantity differs from initial stock line';
    END IF;
    IF nullif(row_data->>'document_no','') IS NULL
      OR nullif(row_data->>'document_type','') IS NULL THEN
      RAISE EXCEPTION 'Ledger document identity missing';
    END IF;
    IF (row_data->>'closing_quantity')::numeric <>
      (row_data->>'opening_quantity')::numeric + (row_data->>'inbound_quantity')::numeric
      - (row_data->>'outbound_quantity')::numeric THEN
      RAISE EXCEPTION 'Ledger balance equation failed';
    END IF;
  END LOOP;
  IF matched = 0 THEN RAISE EXCEPTION 'No approved opening fixture was verified'; END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(public.wms_inventory_report_secure('movement', p_limit => 200)->'data')
    WHERE value->>'document_type' IN ('initial_stock_in','initial_purchase_in','initial_purchase_return','initialization_correction')
  ) THEN RAISE EXCEPTION 'Opening stock was counted as daily movement'; END IF;
  IF has_function_privilege('authenticated','app_private.generate_material_batch_no(uuid)','EXECUTE')
    OR has_function_privilege('anon','app_private.generate_material_batch_no(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Internal batch generator is publicly executable';
  END IF;
END $test$;
ROLLBACK;
