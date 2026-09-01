
do $migration$
declare
  v_definition text;
  v_old text := $old$
    select * into v_voucher
    from public.fms_voucher
    where account_set_id = v_event.account_set_id
      and source_type = v_event.source_type
      and source_id = v_event.source_id
    order by create_time limit 1;
    if found then
      update public.fms_posting_event set status = 'generated', voucher_id = v_voucher.id,
        processed_at = coalesce(processed_at, now()), last_error = null, update_time = now()
      where id = v_event.id returning * into v_event;
      return v_event;
    end if;
$old$;
  v_new text := $new$
    if v_event.voucher_id is not null then
      select * into v_voucher
      from public.fms_voucher
      where id = v_event.voucher_id
        and account_set_id = v_event.account_set_id;
      if found then
        update public.fms_posting_event set status = 'generated',
          processed_at = coalesce(processed_at, now()), last_error = null, update_time = now()
        where id = v_event.id returning * into v_event;
        return v_event;
      end if;
    end if;
$new$;
begin
  select pg_get_functiondef('app_private.process_fms_posting_event(uuid,boolean)'::regprocedure)
  into v_definition;

  if position(v_old in v_definition) = 0 then
    raise exception 'process_fms_posting_event source lookup block did not match expected definition';
  end if;

  execute replace(v_definition, v_old, v_new);
end
$migration$;

comment on function app_private.process_fms_posting_event(uuid, boolean) is
  'Processes one posting event idempotently by its own voucher_id, allowing separate lifecycle events of the same source object to generate separate vouchers.';
;
