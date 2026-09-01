create unique index if not exists tms_customer_tenant_tax_no_normalized_unique
on public.tms_customer (
  tenant_id,
  upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g'))
)
where nullif(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g'), '') is not null;

create unique index if not exists tms_customer_tenant_name_normalized_unique
on public.tms_customer (
  tenant_id,
  lower(regexp_replace(btrim(customer_name), '[[:space:][:punct:]，。；（）]+', '', 'g'))
);

create unique index if not exists tms_carrier_tenant_tax_no_normalized_unique
on public.tms_carrier (
  tenant_id,
  upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g'))
)
where nullif(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g'), '') is not null;

create unique index if not exists tms_carrier_tenant_name_normalized_unique
on public.tms_carrier (
  tenant_id,
  lower(regexp_replace(btrim(company_name), '[[:space:][:punct:]，。；（）]+', '', 'g'))
);

create or replace function public.resolve_tms_invoice_counterparty(p_artifact_id uuid)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_artifact record;
  v_direction text;
  v_party_kind text;
  v_name text;
  v_tax_no text;
  v_normalized_name text;
  v_normalized_tax_no text;
  v_tax_match_count integer := 0;
  v_name_match_count integer := 0;
  v_tax_match_id uuid;
  v_name_match_id uuid;
  v_match_id uuid;
  v_match_method text;
  v_party_name text;
  v_party_code text;
  v_party_tax_no text;
  v_party_enabled boolean;
  v_status text;
  v_message text;
  v_can_create boolean := false;
begin
  select
    tenant_id,
    proposed_payload,
    confidence,
    metadata
  into v_artifact
  from public.ai_artifact_review
  where id = p_artifact_id
    and feature = 'invoice_ocr'
    and artifact_type = 'tms_invoice_draft';

  if not found then
    raise exception '发票识别记录不存在或当前用户无权访问';
  end if;

  v_direction := coalesce(v_artifact.metadata ->> 'direction', 'output');
  if v_direction not in ('output', 'input') then
    raise exception '发票方向无效';
  end if;

  v_party_kind := case when v_direction = 'output' then 'customer' else 'carrier' end;
  v_name := nullif(
    btrim(
      case
        when v_direction = 'output' then
          coalesce(v_artifact.proposed_payload ->> 'buyerName', v_artifact.proposed_payload ->> 'invoiceTitle', '')
        else
          coalesce(v_artifact.proposed_payload ->> 'sellerName', v_artifact.proposed_payload ->> 'invoiceTitle', '')
      end
    ),
    ''
  );
  v_tax_no := nullif(
    btrim(
      case
        when v_direction = 'output' then
          coalesce(v_artifact.proposed_payload ->> 'buyerTaxNumber', v_artifact.proposed_payload ->> 'taxNumber', '')
        else
          coalesce(v_artifact.proposed_payload ->> 'sellerTaxNumber', v_artifact.proposed_payload ->> 'taxNumber', '')
      end
    ),
    ''
  );
  v_normalized_name := coalesce(
    lower(regexp_replace(btrim(v_name), '[[:space:][:punct:]，。；（）]+', '', 'g')),
    ''
  );
  v_normalized_tax_no := coalesce(
    upper(regexp_replace(btrim(v_tax_no), '[^0-9A-Za-z]', '', 'g')),
    ''
  );

  if v_normalized_name = '' and v_normalized_tax_no = '' then
    return jsonb_build_object(
      'status', 'invalid',
      'direction', v_direction,
      'party_kind', v_party_kind,
      'name', v_name,
      'tax_no', v_tax_no,
      'confidence', coalesce(v_artifact.confidence, 0),
      'can_create', false,
      'requires_review', true,
      'message', '未识别到可用于匹配的往来单位名称或税号，请重新识别或手动选择'
    );
  end if;

  if v_direction = 'output' then
    if v_normalized_tax_no <> '' then
      select count(*)::integer, min(id::text)::uuid
      into v_tax_match_count, v_tax_match_id
      from public.tms_customer
      where tenant_id = v_artifact.tenant_id
        and upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')) = v_normalized_tax_no;
    end if;
    if v_normalized_name <> '' then
      select count(*)::integer, min(id::text)::uuid
      into v_name_match_count, v_name_match_id
      from public.tms_customer
      where tenant_id = v_artifact.tenant_id
        and lower(regexp_replace(btrim(customer_name), '[[:space:][:punct:]，。；（）]+', '', 'g')) = v_normalized_name;
    end if;
  else
    if v_normalized_tax_no <> '' then
      select count(*)::integer, min(id::text)::uuid
      into v_tax_match_count, v_tax_match_id
      from public.tms_carrier
      where tenant_id = v_artifact.tenant_id
        and upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')) = v_normalized_tax_no;
    end if;
    if v_normalized_name <> '' then
      select count(*)::integer, min(id::text)::uuid
      into v_name_match_count, v_name_match_id
      from public.tms_carrier
      where tenant_id = v_artifact.tenant_id
        and lower(regexp_replace(btrim(company_name), '[[:space:][:punct:]，。；（）]+', '', 'g')) = v_normalized_name;
    end if;
  end if;

  if v_tax_match_count > 1 or v_name_match_count > 1 then
    v_status := 'ambiguous';
    v_message := '租户内存在多个相同税号或名称的往来单位，请先整理主数据后手动选择';
  elsif v_tax_match_id is not null and v_name_match_id is not null and v_tax_match_id <> v_name_match_id then
    v_status := 'conflict';
    v_message := '识别出的名称和税号分别命中了不同往来单位，请人工核对';
  else
    v_match_id := coalesce(v_tax_match_id, v_name_match_id);
  end if;

  if v_status is null and v_match_id is not null then
    v_match_method := case when v_tax_match_id is not null then 'tax_no' else 'name' end;
    if v_direction = 'output' then
      select customer_name, customer_code, tax_no, enabled
      into v_party_name, v_party_code, v_party_tax_no, v_party_enabled
      from public.tms_customer
      where id = v_match_id;
    else
      select company_name, carrier_code, tax_no, enabled
      into v_party_name, v_party_code, v_party_tax_no, v_party_enabled
      from public.tms_carrier
      where id = v_match_id;
    end if;

    if not coalesce(v_party_enabled, false) then
      v_status := 'disabled';
      v_message := '匹配到的往来单位已停用，请先启用或手动选择其他单位';
    elsif v_match_method = 'name'
      and v_normalized_tax_no <> ''
      and nullif(upper(regexp_replace(btrim(v_party_tax_no), '[^0-9A-Za-z]', '', 'g')), '') is not null
      and upper(regexp_replace(btrim(v_party_tax_no), '[^0-9A-Za-z]', '', 'g')) <> v_normalized_tax_no then
      v_status := 'conflict';
      v_message := '同名往来单位的税号与票面税号不一致，请人工核对';
    else
      v_status := 'matched';
      v_message := case
        when v_match_method = 'tax_no' then '已按纳税人识别号匹配并带入往来单位'
        else '已按完整名称匹配并带入往来单位'
      end;
    end if;
  end if;

  if v_status is null then
    v_status := 'unmatched';
    v_can_create := app_private.is_platform_super()
      and v_normalized_name <> ''
      and char_length(v_name) between 2 and 100;
    v_message := case
      when v_can_create then '未找到现有往来单位，请核对识别信息后建档'
      else '未找到现有往来单位，可手动选择；新建档案需平台超级管理员确认'
    end;
  end if;

  return jsonb_build_object(
    'status', v_status,
    'direction', v_direction,
    'party_kind', v_party_kind,
    'name', v_name,
    'tax_no', v_tax_no,
    'confidence', coalesce(v_artifact.confidence, 0),
    'match_method', v_match_method,
    'can_create', v_can_create,
    'requires_review', coalesce(v_artifact.confidence, 0) < 0.75,
    'message', v_message,
    'party', case
      when v_match_id is null then null
      else jsonb_build_object(
        'id', v_match_id,
        'party_name', v_party_name,
        'party_code', v_party_code,
        'tax_no', v_party_tax_no,
        'enabled', v_party_enabled
      )
    end
  );
end;
$$;

create or replace function public.create_tms_invoice_counterparty_from_ocr(
  p_artifact_id uuid,
  p_name text,
  p_tax_no text default null,
  p_carrier_type text default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_artifact record;
  v_direction text;
  v_name text := nullif(btrim(p_name), '');
  v_tax_no text := nullif(btrim(p_tax_no), '');
  v_normalized_name text;
  v_normalized_tax_no text;
  v_tax_match_id uuid;
  v_name_match_id uuid;
  v_match_id uuid;
  v_created boolean := false;
  v_party_name text;
  v_party_code text;
  v_party_tax_no text;
  v_party_enabled boolean;
  v_existing_normalized_tax_no text;
begin
  if not app_private.is_platform_super() then
    raise exception '只有平台超级管理员可以确认 AI 往来单位建档';
  end if;

  select tenant_id, metadata
  into v_artifact
  from public.ai_artifact_review
  where id = p_artifact_id
    and feature = 'invoice_ocr'
    and artifact_type = 'tms_invoice_draft';

  if not found then
    raise exception '发票识别记录不存在或当前用户无权访问';
  end if;

  v_direction := coalesce(v_artifact.metadata ->> 'direction', 'output');
  if v_direction not in ('output', 'input') then
    raise exception '发票方向无效';
  end if;
  if v_name is null or char_length(v_name) not between 2 and 100 then
    raise exception '往来单位名称长度应为 2 到 100 个字符';
  end if;
  if v_tax_no is not null and upper(regexp_replace(v_tax_no, '[^0-9A-Za-z]', '', 'g')) !~ '^[0-9A-Z]{15,20}$' then
    raise exception '纳税人识别号格式不正确';
  end if;
  if v_direction = 'input' and nullif(btrim(p_carrier_type), '') is null then
    raise exception '请选择承运商类型';
  end if;

  v_normalized_name := lower(regexp_replace(v_name, '[[:space:][:punct:]，。；（）]+', '', 'g'));
  v_normalized_tax_no := coalesce(
    upper(regexp_replace(v_tax_no, '[^0-9A-Za-z]', '', 'g')),
    ''
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'invoice-counterparty:name:' || v_artifact.tenant_id::text || ':' || v_direction || ':' || v_normalized_name,
      0
    )
  );
  if v_normalized_tax_no <> '' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        'invoice-counterparty:tax:' || v_artifact.tenant_id::text || ':' || v_direction || ':' || v_normalized_tax_no,
        0
      )
    );
  end if;

  if v_direction = 'output' then
    if v_normalized_tax_no <> '' then
      select id into v_tax_match_id
      from public.tms_customer
      where tenant_id = v_artifact.tenant_id
        and upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')) = v_normalized_tax_no
      limit 1;
    end if;
    select id into v_name_match_id
    from public.tms_customer
    where tenant_id = v_artifact.tenant_id
      and lower(regexp_replace(btrim(customer_name), '[[:space:][:punct:]，。；（）]+', '', 'g')) = v_normalized_name
    limit 1;
  else
    if v_normalized_tax_no <> '' then
      select id into v_tax_match_id
      from public.tms_carrier
      where tenant_id = v_artifact.tenant_id
        and upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')) = v_normalized_tax_no
      limit 1;
    end if;
    select id into v_name_match_id
    from public.tms_carrier
    where tenant_id = v_artifact.tenant_id
      and lower(regexp_replace(btrim(company_name), '[[:space:][:punct:]，。；（）]+', '', 'g')) = v_normalized_name
    limit 1;
  end if;

  if v_tax_match_id is not null and v_name_match_id is not null and v_tax_match_id <> v_name_match_id then
    raise exception '名称和税号分别对应不同往来单位，禁止重复建档';
  end if;
  v_match_id := coalesce(v_tax_match_id, v_name_match_id);

  if v_match_id is not null and v_name_match_id is not null and v_normalized_tax_no <> '' then
    if v_direction = 'output' then
      select coalesce(upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')), '')
      into v_existing_normalized_tax_no
      from public.tms_customer
      where id = v_match_id;
    else
      select coalesce(upper(regexp_replace(btrim(tax_no), '[^0-9A-Za-z]', '', 'g')), '')
      into v_existing_normalized_tax_no
      from public.tms_carrier
      where id = v_match_id;
    end if;
    if v_existing_normalized_tax_no <> '' and v_existing_normalized_tax_no <> v_normalized_tax_no then
      raise exception '同名往来单位的税号与票面税号不一致，禁止重复建档';
    end if;
  end if;

  if v_match_id is null then
    if v_direction = 'output' then
      insert into public.tms_customer (
        tenant_id,
        customer_name,
        invoice_title,
        tax_no,
        enabled,
        tags
      ) values (
        v_artifact.tenant_id,
        v_name,
        v_name,
        v_tax_no,
        true,
        '{}'::text[]
      )
      returning id into v_match_id;
    else
      insert into public.tms_carrier (
        tenant_id,
        company_name,
        carrier_type,
        invoice_title,
        tax_no,
        enabled
      ) values (
        v_artifact.tenant_id,
        v_name,
        btrim(p_carrier_type),
        v_name,
        v_tax_no,
        true
      )
      returning id into v_match_id;
    end if;
    v_created := true;
  end if;

  if v_direction = 'output' then
    select customer_name, customer_code, tax_no, enabled
    into v_party_name, v_party_code, v_party_tax_no, v_party_enabled
    from public.tms_customer
    where id = v_match_id;
  else
    select company_name, carrier_code, tax_no, enabled
    into v_party_name, v_party_code, v_party_tax_no, v_party_enabled
    from public.tms_carrier
    where id = v_match_id;
  end if;

  if not coalesce(v_party_enabled, false) then
    raise exception '同名或同税号往来单位已存在但处于停用状态，请先启用该档案';
  end if;

  return jsonb_build_object(
    'created', v_created,
    'direction', v_direction,
    'party', jsonb_build_object(
      'id', v_match_id,
      'party_name', v_party_name,
      'party_code', v_party_code,
      'tax_no', v_party_tax_no,
      'enabled', v_party_enabled
    )
  );
end;
$$;

revoke all on function public.resolve_tms_invoice_counterparty(uuid) from public, anon;
grant execute on function public.resolve_tms_invoice_counterparty(uuid) to authenticated, service_role;

revoke all on function public.create_tms_invoice_counterparty_from_ocr(uuid, text, text, text) from public, anon;
grant execute on function public.create_tms_invoice_counterparty_from_ocr(uuid, text, text, text) to authenticated, service_role;

comment on function public.resolve_tms_invoice_counterparty(uuid)
is 'Tenant-scoped read-only resolution of an OCR invoice party to an existing customer or carrier.';

comment on function public.create_tms_invoice_counterparty_from_ocr(uuid, text, text, text)
is 'Platform-super-confirmed atomic creation or reuse of an OCR invoice customer/carrier master record.';

notify pgrst, 'reload schema';

;
