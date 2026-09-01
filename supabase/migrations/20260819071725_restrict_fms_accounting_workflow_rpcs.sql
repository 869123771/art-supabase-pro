revoke all on function public.initialize_fms_accounting_defaults(uuid) from public;
revoke all on function public.initialize_fms_accounting_defaults(uuid) from anon;
grant execute on function public.initialize_fms_accounting_defaults(uuid) to authenticated;

revoke all on function public.generate_fms_profit_loss_carryforward(uuid) from public;
revoke all on function public.generate_fms_profit_loss_carryforward(uuid) from anon;
grant execute on function public.generate_fms_profit_loss_carryforward(uuid) to authenticated;;
