update public.sys_dictionary as dictionary
set label = '已签收',
    update_time = now()
where dictionary.value = 'signed'
  and dictionary.type_id in (
    select type_record.id
    from public.sys_dict_type as type_record
    where type_record.code = 'tmsWaybillStatus'
  );

revoke all on function public.tms_confirm_waybill_departure(uuid) from public;
revoke all on function public.tms_confirm_waybill_departure(uuid) from anon;
revoke all on function public.tms_confirm_waybill_departure(uuid) from authenticated;;
