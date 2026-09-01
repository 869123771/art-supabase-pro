alter table public.smis_site
  drop constraint smis_site_category_check;

alter table public.smis_site
  add constraint smis_site_category_not_blank
  check (btrim(category_code) <> '');

;
