alter function public.smis_save_sites_secure(uuid[], jsonb)
  security invoker;

comment on function public.smis_save_sites_secure(uuid[], jsonb) is
  '以调用者权限编排多个原子场所新增请求；每条写入继续由 smis_save_site_secure 执行租户和按钮权限校验。';

;
