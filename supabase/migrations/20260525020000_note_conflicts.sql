alter table public.notes
  add column if not exists content_hash text not null default '',
  add column if not exists is_conflict boolean not null default false,
  add column if not exists conflict_parent_id uuid references public.notes(id) on delete set null,
  add column if not exists conflict_created_at timestamptz;

create index if not exists notes_user_conflict_updated_idx
  on public.notes (user_id, is_conflict, updated_at desc);

drop policy if exists "Users can insert their notes" on public.notes;
create policy "Users can insert their notes"
  on public.notes
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and (
      folder_id is null
      or exists (
        select 1
        from public.folders
        where folders.id = notes.folder_id
          and folders.user_id = auth.uid()
      )
    )
    and (
      conflict_parent_id is null
      or exists (
        select 1
        from public.notes parent
        where parent.id = notes.conflict_parent_id
          and parent.user_id = auth.uid()
      )
    )
  );

drop policy if exists "Users can update their notes" on public.notes;
create policy "Users can update their notes"
  on public.notes
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (
      folder_id is null
      or exists (
        select 1
        from public.folders
        where folders.id = notes.folder_id
          and folders.user_id = auth.uid()
      )
    )
    and (
      conflict_parent_id is null
      or exists (
        select 1
        from public.notes parent
        where parent.id = notes.conflict_parent_id
          and parent.user_id = auth.uid()
      )
    )
  );
