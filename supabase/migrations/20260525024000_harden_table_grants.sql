revoke all privileges on table public.notes from anon;
revoke all privileges on table public.folders from anon;
revoke all privileges on table public.note_history from anon;
revoke all privileges on table public.sync_keys from anon;

revoke truncate, references, trigger on table public.notes from authenticated;
revoke truncate, references, trigger on table public.folders from authenticated;
revoke truncate, references, trigger on table public.note_history from authenticated;
revoke truncate, references, trigger on table public.sync_keys from authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on table public.notes to authenticated;
grant select, insert, update, delete on table public.folders to authenticated;
grant select, insert, update, delete on table public.note_history to authenticated;
grant select, insert, update, delete on table public.sync_keys to authenticated;
