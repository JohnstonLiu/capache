alter table public.notes replica identity full;
alter table public.folders replica identity full;
alter table public.note_history replica identity full;

do $$
begin
  if exists (
    select 1
    from pg_publication
    where pubname = 'supabase_realtime'
  ) then
    begin
      alter publication supabase_realtime add table public.notes;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.folders;
    exception
      when duplicate_object then null;
    end;

    begin
      alter publication supabase_realtime add table public.note_history;
    exception
      when duplicate_object then null;
    end;
  end if;
end $$;
