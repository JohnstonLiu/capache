create table if not exists public.folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists folders_user_name_idx
  on public.folders (user_id, lower(name));

alter table public.folders enable row level security;

drop policy if exists "Users can select their folders" on public.folders;
create policy "Users can select their folders"
  on public.folders
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their folders" on public.folders;
create policy "Users can insert their folders"
  on public.folders
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their folders" on public.folders;
create policy "Users can update their folders"
  on public.folders
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their folders" on public.folders;
create policy "Users can delete their folders"
  on public.folders
  for delete
  to authenticated
  using (auth.uid() = user_id);

alter table public.notes
  add column if not exists title text not null default '',
  add column if not exists folder_id uuid references public.folders(id) on delete set null,
  add column if not exists is_pinned boolean not null default false,
  add column if not exists is_archived boolean not null default false;

create index if not exists notes_user_folder_updated_idx
  on public.notes (user_id, folder_id, updated_at desc);

create index if not exists notes_user_archive_pin_updated_idx
  on public.notes (user_id, is_archived, is_pinned desc, updated_at desc);

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
  );

grant select, insert, update, delete on public.folders to authenticated;
