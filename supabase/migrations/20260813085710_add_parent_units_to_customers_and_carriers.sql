alter table public.tms_customer
add column parent_unit_id uuid;

alter table public.tms_carrier
add column parent_unit_id uuid;

comment on column public.tms_customer.parent_unit_id is '上级客户单位，同租户内可空自关联';
comment on column public.tms_carrier.parent_unit_id is '上级承运商单位，同租户内可空自关联';

alter table public.tms_customer
add constraint tms_customer_parent_unit_not_self
check (parent_unit_id is null or parent_unit_id <> id),
add constraint tms_customer_parent_unit_id_fkey
foreign key (parent_unit_id)
references public.tms_customer(id)
on delete set null;

alter table public.tms_carrier
add constraint tms_carrier_parent_unit_not_self
check (parent_unit_id is null or parent_unit_id <> id),
add constraint tms_carrier_parent_unit_id_fkey
foreign key (parent_unit_id)
references public.tms_carrier(id)
on delete set null;

create index tms_customer_parent_unit_id_idx
on public.tms_customer(parent_unit_id)
where parent_unit_id is not null;

create index tms_carrier_parent_unit_id_idx
on public.tms_carrier(parent_unit_id)
where parent_unit_id is not null;

create or replace function app_private.validate_tms_parent_unit()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_entity_label text := tg_argv[0];
  v_parent_tenant_id uuid;
  v_has_cycle boolean;
begin
  if new.parent_unit_id is null then
    return new;
  end if;

  if new.parent_unit_id = new.id then
    raise exception using
      errcode = '23514',
      message = format('%s不能选择自身作为上级单位', v_entity_label);
  end if;

  execute format(
    'select tenant_id from %I.%I where id = $1',
    tg_table_schema,
    tg_table_name
  )
  into v_parent_tenant_id
  using new.parent_unit_id;

  if v_parent_tenant_id is null then
    raise exception using
      errcode = '23503',
      message = format('所选上级%s不存在或无权访问', v_entity_label);
  end if;

  if v_parent_tenant_id is distinct from new.tenant_id then
    raise exception using
      errcode = '23514',
      message = format('上级%s必须与当前单位属于同一租户', v_entity_label);
  end if;

  execute format(
    $query$
      with recursive ancestors as (
        select id, parent_unit_id
        from %I.%I
        where id = $1 and tenant_id = $2

        union

        select parent.id, parent.parent_unit_id
        from %I.%I as parent
        join ancestors on parent.id = ancestors.parent_unit_id
        where parent.tenant_id = $2
      )
      select exists(select 1 from ancestors where id = $3)
    $query$,
    tg_table_schema,
    tg_table_name,
    tg_table_schema,
    tg_table_name
  )
  into v_has_cycle
  using new.parent_unit_id, new.tenant_id, new.id;

  if v_has_cycle then
    raise exception using
      errcode = '23514',
      message = format('所选上级%s会形成循环层级', v_entity_label);
  end if;

  return new;
end;
$$;

comment on function app_private.validate_tms_parent_unit() is
'校验客户和承运商上级单位必须同租户且不能形成循环层级';

create trigger tms_customer_validate_parent_unit
before insert or update of parent_unit_id, tenant_id
on public.tms_customer
for each row
execute function app_private.validate_tms_parent_unit('客户');

create trigger tms_carrier_validate_parent_unit
before insert or update of parent_unit_id, tenant_id
on public.tms_carrier
for each row
execute function app_private.validate_tms_parent_unit('承运商');;
