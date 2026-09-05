-- New foreign-key relationships are discovered by PostgREST through its schema cache.
-- Reload it during deployment so the nested sys_dict_type relationship is available immediately.
notify pgrst, 'reload schema';
