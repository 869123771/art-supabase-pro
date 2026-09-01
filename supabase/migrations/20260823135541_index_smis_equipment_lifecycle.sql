create index if not exists idx_smis_business_record_equipment_lifecycle
  on public.smis_business_record (tenant_id, (payload->>'equipment_id'), update_time desc)
  where module_code = any(array[
    'external-inspection',
    'internal-inspection',
    'annual-inspection',
    'periodic-inspection'
  ]::text[]);;
