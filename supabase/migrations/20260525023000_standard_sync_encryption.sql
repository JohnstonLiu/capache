create table if not exists public.sync_keys (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  key_data text not null,
  key_version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.sync_keys enable row level security;

drop policy if exists "Users can select their sync key" on public.sync_keys;
create policy "Users can select their sync key"
  on public.sync_keys
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their sync key" on public.sync_keys;
create policy "Users can insert their sync key"
  on public.sync_keys
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their sync key" on public.sync_keys;
create policy "Users can update their sync key"
  on public.sync_keys
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their sync key" on public.sync_keys;
create policy "Users can delete their sync key"
  on public.sync_keys
  for delete
  to authenticated
  using (auth.uid() = user_id);

alter table public.notes
  add column if not exists encrypted_payload text,
  add column if not exists encryption_version integer not null default 0;

create index if not exists notes_user_encryption_version_idx
  on public.notes (user_id, encryption_version);

alter table public.note_history
  add column if not exists encrypted_payload text,
  add column if not exists encryption_version integer not null default 0;

create index if not exists note_history_user_encryption_version_idx
  on public.note_history (user_id, encryption_version);

drop policy if exists "Users can update their note history" on public.note_history;
create policy "Users can update their note history"
  on public.note_history
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.notes
      where notes.id = note_history.note_id
        and notes.user_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.sync_keys to authenticated;
grant update on public.note_history to authenticated;
