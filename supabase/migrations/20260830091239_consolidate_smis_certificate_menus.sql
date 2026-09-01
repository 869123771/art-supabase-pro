begin;

update public.sys_menu
set meta = jsonb_set(
      jsonb_set(meta, '{is_hide}', 'true'::jsonb, true),
      '{is_enable}', 'false'::jsonb, true
    ),
    update_time = now(),
    update_by = '624944977@qq.com'
where name in (
  'SmisSpecialEquipmentOperatorCertificateLedger',
  'SmisSpecialOperationCertificate',
  'SmisSafetyManagerCertificate'
);

update public.sys_menu
set meta = jsonb_set(
      jsonb_set(meta, '{title}', '"人员证件台账"'::jsonb, true),
      '{is_enable}', 'true'::jsonb, true
    ),
    update_time = now(),
    update_by = '624944977@qq.com'
where name = 'SmisSpecialEquipmentPersonnelCertificateLedger';

commit;

;
