begin;

alter function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) rename to smis_list_personnel_certificates_raw_secure;

revoke all on function public.smis_list_personnel_certificates_raw_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon, authenticated;

create or replace function public.smis_list_personnel_certificates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_employee_name text default null,
  p_certificate_number text default null,
  p_certificate_category text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_warning_status text default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_payload jsonb;
begin
  v_payload := public.smis_list_personnel_certificates_raw_secure(
    p_from, p_to, p_employee_name, p_certificate_number,
    p_certificate_category, p_start_date, p_end_date,
    p_warning_status, p_purpose
  );

  if app_private.is_platform_super()
     or app_private.has_permission('SmisPersonnelCertificateLedger:ViewHistory') then
    return v_payload;
  end if;

  return jsonb_set(
    v_payload,
    '{records}',
    coalesce((
      select jsonb_agg(
        certificate_row
        || jsonb_build_object(
          'items',
          coalesce((
            select jsonb_agg(
              (item_row - 'reviewHistory' - 'reviewCount')
              || jsonb_build_object('reviewHistory', '[]'::jsonb, 'reviewCount', 0)
            )
            from jsonb_array_elements(certificate_row->'items') item_row
          ), '[]'::jsonb)
        )
      )
      from jsonb_array_elements(v_payload->'records') certificate_row
    ), '[]'::jsonb),
    true
  );
end;
$function$;

revoke all on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon;
grant execute on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) to authenticated;

commit;

;
