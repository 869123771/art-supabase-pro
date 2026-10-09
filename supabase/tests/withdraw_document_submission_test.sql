-- Lifecycle and tenant regression. Every mutation, audit and notification rolls back.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{}',true);
DO $test$
declare
 d public.wms_initial_stock_document;
 v_id uuid; v_warehouse uuid; v_status text; v_instance uuid := '44ff8058-6365-4358-a896-df87d8262cf4';
 v_row jsonb; v_table text; v_function text;
begin
 select * into strict d from public.wms_initial_stock_document where id='32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4';
 -- Use the existing submitted fixture only inside this transaction.
 perform public.wms_change_initial_stock_status_secure(d.id,'withdraw');
 assert (select status='draft' from public.wms_initial_stock_document where id=d.id),'initial withdrawal';
 begin perform public.wms_change_initial_stock_status_secure(d.id,'withdraw'); raise exception 'repeat allowed'; exception when check_violation then null; end;
 perform public.wms_change_initial_stock_status_secure(d.id,'submit');
 assert (select status='submitted' from public.wms_initial_stock_document where id=d.id),'resubmit';
 -- A subtransaction restores the submitted fixture after the rejection check.
 begin
   update public.wms_initial_stock_document set status='approved',approved_at=now() where id=d.id;
   begin perform public.wms_change_initial_stock_status_secure(d.id,'withdraw'); raise exception 'approved allowed'; exception when check_violation then null; end;
   raise exception 'restore fixture' using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
 -- Both purchase and sales use independent document clones.
 foreach v_table in array array['wms_purchase_document','wms_sales_document'] loop
   execute format('select to_jsonb(d) from public.%I d limit 1',v_table) into v_row;
   assert v_row is not null,'missing test fixture';
   v_id:=gen_random_uuid();
   v_row:=v_row||jsonb_build_object('id',v_id,'document_no','WITHDRAW-TEST-'||v_id,'status','submitted','approved_at',null);
   execute format('insert into public.%I select * from jsonb_populate_record(null::public.%I,$1)',v_table,v_table) using v_row;
   v_function:=case v_table when 'wms_purchase_document' then 'wms_change_purchase_document_status_secure' else 'wms_change_sales_document_status_secure' end;
   execute format('select public.%I($1,$2)',v_function) using v_id,'withdraw';
   execute format('select status from public.%I where id=$1',v_table) into v_status using v_id;
   assert v_status='draft','purchase/sales withdrawal';
   -- Returning to draft restores the existing guarded delete path.
   execute format('select public.%I($1,$2)',v_function) using v_id,'delete';
 end loop;
 select id into strict v_warehouse from public.mdm_warehouse where tenant_id=d.tenant_id and organization_id=d.organization_id limit 1;
 insert into public.wms_transfer_request_document(tenant_id,organization_id,document_no,document_type_id,business_type_id,status)
 values(d.tenant_id,d.organization_id,'WITHDRAW-TEST-TRANSFER',d.document_type_id,d.business_type_id,'submitted') returning id into v_id;
 perform public.wms_change_transfer_request_status_secure(v_id,'withdraw');
 assert(select status='draft' from public.wms_transfer_request_document where id=v_id),'transfer withdrawal';
 insert into public.wms_count_adjustment_document(tenant_id,organization_id,kind,document_no,document_type_id,business_type_id,status)
 values(d.tenant_id,d.organization_id,'gain','WITHDRAW-TEST-COUNT',d.document_type_id,d.business_type_id,'submitted') returning id into v_id;
 perform public.wms_change_count_adjustment_status_secure(v_id,'withdraw');
 assert(select status='draft' from public.wms_count_adjustment_document where id=v_id),'count withdrawal';
 insert into public.wms_production_material_document(tenant_id,organization_id,kind,document_no,document_type_id,business_type_id,warehouse_id,status)
 values(d.tenant_id,d.organization_id,'issue','WITHDRAW-TEST-PRODUCTION',d.document_type_id,d.business_type_id,v_warehouse,'submitted') returning id into v_id;
 perform public.wms_change_production_material_status_secure(v_id,'withdraw');
 assert(select status='draft' from public.wms_production_material_document where id=v_id),'production withdrawal';
 assert (select count(*)>=6 from public.sys_audit_log where command_tag='WITHDRAW' and auth_user_id=auth.uid()),'audit missing';
 -- Workflow cancellation, callback and decision exclusion share the instance lock.
 begin perform public.withdraw_workflow(v_instance,'test'); raise exception 'non-initiator allowed'; exception when raise_exception then assert sqlerrm='流程不存在或仅发起人可以撤回'; end;
 perform set_config('request.jwt.claims','{"sub":"ab881b32-87d4-4dce-9014-ce488b8069df","role":"authenticated"}',true);
 update public.wf_task set status='approved' where instance_id=v_instance;
 begin perform public.withdraw_workflow(v_instance,'test'); raise exception 'handled task allowed'; exception when raise_exception then assert sqlerrm='已有审批人处理，不能直接撤回'; end;
 update public.wf_task set status='pending' where instance_id=v_instance;
 -- A blocked predecessor must roll back the cancellation, not report success.
 update public.wf_business_callback_outbox set status='retry_wait' where instance_id=v_instance and target_status='running';
 begin perform public.withdraw_workflow(v_instance,'test'); raise exception 'failed callback allowed'; exception when check_violation then null; end;
 assert(select status='running' from public.wf_instance where id=v_instance),'failed callback changed instance';
 assert exists(select 1 from public.wf_task where instance_id=v_instance and status='pending'),'failed callback cancelled tasks';
 update public.wf_business_callback_outbox set status='succeeded' where instance_id=v_instance and target_status='running';
 perform public.withdraw_workflow(v_instance,'test');
 assert(select status='withdrawn' from public.wf_instance where id=v_instance),'workflow withdrawal';
 assert not exists(select 1 from public.wf_task where instance_id=v_instance and status='pending'),'pending tasks remain';
 assert exists(select 1 from public.wf_action where instance_id=v_instance and action='withdraw'),'workflow audit missing';
 assert exists(select 1 from public.wf_business_callback_outbox where instance_id=v_instance and target_status='withdrawn' and status='succeeded'),'callback missing';
 assert(select status='draft' from public.scm_sales_document where id='7e3290e8-3d53-4608-8756-f39393a8d101'),'business not editable';
end $test$;
-- Platform-selected cannot mutate a different tenant.
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"7529f951-938e-4e2c-ac0d-316c136ae1f9"}',true);
DO $test$ begin
 begin
   perform public.wms_change_initial_stock_status_secure('32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4','withdraw');
   assert(select status='draft' from public.wms_initial_stock_document where id='32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4'),'selected own withdrawal';
   raise exception 'restore selected fixture' using errcode='ZX001';
 exception when sqlstate 'ZX001' then null; end;
end $test$;
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
DO $test$ begin
 begin perform public.wms_change_initial_stock_status_secure('32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4','withdraw'); raise exception 'selected tenant leak'; exception when insufficient_privilege then null; end;
end $test$;
-- Give the ordinary fixture the exact action only for this transaction.
select set_config('request.headers','{}',true);
delete from public.sys_role_menu rm using public.sys_role r,public.sys_user u,public.sys_menu m
where rm.role_id=r.id and rm.menu_id=m.id and r.role_code=any(u.user_roles) and r.tenant_id=u.tenant_id
and u.id='51080ef5-46a4-4d0c-a229-c97c6fccda93' and m.name='WmsInitialStock:Withdraw';
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
DO $test$ begin
 begin perform public.wms_change_initial_stock_status_secure('32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4','withdraw'); raise exception 'missing permission allowed'; exception when insufficient_privilege then null; end;
end $test$;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
insert into public.sys_role_menu(role_id,menu_id,tenant_id)
select r.id,m.id,r.tenant_id from public.sys_role r join public.sys_user u on r.role_code=any(u.user_roles) and r.tenant_id=u.tenant_id
cross join public.sys_menu m
where u.id='51080ef5-46a4-4d0c-a229-c97c6fccda93' and m.name='WmsInitialStock:Withdraw'
on conflict(role_id,menu_id) do nothing;
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
DO $test$ begin
 perform public.wms_change_initial_stock_status_secure('32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4','withdraw');
 assert(select status='draft' from public.wms_initial_stock_document where id='32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4'),'ordinary own';
end $test$;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
update public.wms_initial_stock_document set status='submitted' where id='32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4';
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
DO $test$ begin
 perform public.wms_change_initial_stock_status_secure('32a7e7ac-5a78-42bc-9de2-7b4b55e9ecd4','withdraw');
 assert(app_private.current_read_tenant_id()='7529f951-938e-4e2c-ac0d-316c136ae1f9'::uuid),'forged scope honored';
end $test$;
ROLLBACK;
