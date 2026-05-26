create extension if not exists pgcrypto;

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rtf_data text not null default '',
  plain_text text not null default '',
  updated_at timestamptz not null default now()
);

create index if not exists notes_user_updated_idx
  on public.notes (user_id, updated_at desc);

alter table public.notes enable row level security;

drop policy if exists "Users can select their notes" on public.notes;
create policy "Users can select their notes"
  on public.notes
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their notes" on public.notes;
create policy "Users can insert their notes"
  on public.notes
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their notes" on public.notes;
create policy "Users can update their notes"
  on public.notes
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their notes" on public.notes;
create policy "Users can delete their notes"
  on public.notes
  for delete
  to authenticated
  using (auth.uid() = user_id);

create table if not exists public.note_history (
  id uuid primary key default gen_random_uuid(),
  note_id uuid not null references public.notes(id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rtf_data text not null default '',
  plain_text text not null default '',
  created_at timestamptz not null default now(),
  content_hash text not null
);

create index if not exists note_history_user_note_created_idx
  on public.note_history (user_id, note_id, created_at desc);

alter table public.note_history enable row level security;

drop policy if exists "Users can select their note history" on public.note_history;
create policy "Users can select their note history"
  on public.note_history
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their note history" on public.note_history;
create policy "Users can insert their note history"
  on public.note_history
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.notes
      where notes.id = note_history.note_id
        and notes.user_id = auth.uid()
    )
  );

drop policy if exists "Users can delete their note history" on public.note_history;
create policy "Users can delete their note history"
  on public.note_history
  for delete
  to authenticated
  using (auth.uid() = user_id);

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.notes to authenticated;
grant select, insert, delete on public.note_history to authenticated;
