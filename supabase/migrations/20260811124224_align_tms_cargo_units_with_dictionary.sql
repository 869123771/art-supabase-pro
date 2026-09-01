set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table public.tms_cargo
  drop constraint tms_cargo_unit_check,
  add constraint tms_cargo_unit_check
    check (
      unit = any (
        array[
          'kg'::text,
          'ton'::text,
          'car'::text,
          'piece'::text,
          'box'::text,
          'bottle'::text,
          'item'::text,
          'set'::text
        ]
      )
    );;
