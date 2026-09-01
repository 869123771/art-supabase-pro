drop index if exists public.sys_attachment_hash_unique;

create unique index sys_attachment_tenant_hash_unique
  on public.sys_attachment (tenant_id, hash)
  where hash is not null;;
