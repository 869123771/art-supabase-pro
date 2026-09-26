-- One-time WMS menu alignment. Validate with ROLLBACK before running this COMMIT version.
begin;

insert into public.sys_menu (id,parent_id,name,path,component,type,sort,meta,app_code)
values (
  'aa5fb758-387e-456e-ad8b-5dda406c53a7',
  'a08a35e5-cd58-450a-858c-cbb8d9415ce2',
  'WmsAdjustmentBusiness','adjustment-business','','folder',11,
  '{"icon":"ri:exchange-box-line","title":"库存调整","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
  'wms'
);

insert into public.sys_role_menu (role_id,menu_id,tenant_id,permission)
select role_id,'aa5fb758-387e-456e-ad8b-5dda406c53a7',tenant_id,permission
from public.sys_role_menu
where menu_id='d1000000-0000-4000-8000-000000000102';

update public.sys_menu
set parent_id='0522cb21-bbfb-43d0-adf7-a9e8be223ca7',
    component='/wms/count-business/count/index',sort=1,
    meta=jsonb_set(meta,'{is_hide}','false'::jsonb),update_time=now()
where name='WmsCount' and id='3a3440f7-e83d-4139-9cc5-5dbc88b0ade6';

update public.sys_menu
set component='/wms/transfer-business/direct-transfer/index',sort=2,
    meta=jsonb_set(meta,'{is_hide}','false'::jsonb),update_time=now()
where name='WmsDirectTransfer' and id='d1000000-0000-4000-8000-000000000105';

update public.sys_menu
set parent_id='aa5fb758-387e-456e-ad8b-5dda406c53a7',
    component='/wms/adjustment-business/adjustment/index',sort=1,
    meta=jsonb_set(meta,'{is_hide}','false'::jsonb),update_time=now()
where name='WmsAdjustment' and id='c35fc1e3-974d-48f9-9a3a-75b70dd73d3f';

update public.sys_menu
set parent_id='aa5fb758-387e-456e-ad8b-5dda406c53a7',
    component='/wms/adjustment-business/assembly/index',sort=2,
    meta=jsonb_set(meta,'{is_hide}','false'::jsonb),update_time=now()
where name='WmsAssembly' and id='b1f9c279-1b29-4819-94d9-50b61de03080';

insert into public.sys_menu (id,parent_id,name,path,component,type,sort,meta,app_code)
values (
  '31eea7c3-edb0-4ef5-a3ad-d4ac1464fe82',
  'd1000000-0000-4000-8000-000000000102',
  'WmsStepTransfer','step-transfer','/wms/transfer-business/step-transfer/index','menu',3,
  '{"icon":"ri:truck-line","title":"分步调拨","is_hide":false,"is_enable":true,"keep_alive":true}'::jsonb,
  'wms'
);

insert into public.sys_role_menu (role_id,menu_id,tenant_id,permission)
select role_id,'31eea7c3-edb0-4ef5-a3ad-d4ac1464fe82',tenant_id,permission
from public.sys_role_menu
where menu_id='3a2220b5-3efa-416c-96ab-e20999c003f7';

do $$
begin
  if (select count(*) from public.sys_menu where id in (
    'aa5fb758-387e-456e-ad8b-5dda406c53a7',
    '31eea7c3-edb0-4ef5-a3ad-d4ac1464fe82',
    '3a3440f7-e83d-4139-9cc5-5dbc88b0ade6',
    'd1000000-0000-4000-8000-000000000105',
    'c35fc1e3-974d-48f9-9a3a-75b70dd73d3f',
    'b1f9c279-1b29-4819-94d9-50b61de03080'
  ) and coalesce((meta->>'is_hide')::boolean,false)=false)<>6
  or (select count(*) from public.sys_role_menu where menu_id in (
    'aa5fb758-387e-456e-ad8b-5dda406c53a7',
    '31eea7c3-edb0-4ef5-a3ad-d4ac1464fe82'))<>4
  then raise exception 'WMS 菜单与角色授权核对失败'; end if;
end $$;

select name,path,component,parent_id,meta->>'is_hide' is_hide
from public.sys_menu where id in (
  'aa5fb758-387e-456e-ad8b-5dda406c53a7',
  '31eea7c3-edb0-4ef5-a3ad-d4ac1464fe82',
  '3a3440f7-e83d-4139-9cc5-5dbc88b0ade6',
  'd1000000-0000-4000-8000-000000000105',
  'c35fc1e3-974d-48f9-9a3a-75b70dd73d3f',
  'b1f9c279-1b29-4819-94d9-50b61de03080'
) order by name;

commit;
