create index hr_leave_policy_type_fk_idx
  on public.hr_leave_policy(leave_type_id, tenant_id);
create or replace function app_private.prevent_hr_leave_ledger_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  raise exception '休假余额台账不可修改或删除，请追加冲销分录';
end;
$function$;
create trigger hr_leave_ledger_immutable
before update or delete on public.hr_leave_ledger
for each row execute function app_private.prevent_hr_leave_ledger_mutation();
revoke all on function app_private.prevent_hr_leave_ledger_mutation()
  from public, anon, authenticated;
update public.sys_dictionary dictionary_row
set label = '不自动授予',
    remark = '不自动生成权益额度，可由授权人员通过余额调整授予',
    update_by = '624944977@qq.com',
    update_time = now()
from public.sys_dict_type dictionary_type
where dictionary_type.id = dictionary_row.type_id
  and dictionary_type.code = 'hrLeaveEntitlementMethod'
  and dictionary_row.value = 'none';
