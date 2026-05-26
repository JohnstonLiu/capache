alter table public.folders
  add column if not exists parent_id uuid references public.folders(id) on delete set null;

create index if not exists folders_user_parent_name_idx
  on public.folders (user_id, parent_id, lower(name));

drop policy if exists "Users can insert their folders" on public.folders;
create policy "Users can insert their folders"
  on public.folders
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and (
      parent_id is null
      or (
        parent_id <> id
        and exists (
          select 1
          from public.folders parent
          where parent.id = folders.parent_id
            and parent.user_id = auth.uid()
        )
      )
    )
  );

drop policy if exists "Users can update their folders" on public.folders;
create policy "Users can update their folders"
  on public.folders
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and (
      parent_id is null
      or (
        parent_id <> id
        and exists (
          select 1
          from public.folders parent
          where parent.id = folders.parent_id
            and parent.user_id = auth.uid()
        )
      )
    )
  );
