alter table public.widget_refresh_tokens
  add column if not exists last_snapshot_at timestamptz,
  add column if not exists last_snapshot_note_id uuid,
  add column if not exists last_snapshot_status integer,
  add column if not exists last_snapshot_error text;

create table if not exists public.widget_snapshot_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null references public.widget_refresh_tokens(token_hash) on delete cascade,
  note_id uuid,
  requested_at timestamptz not null default now(),
  status integer not null,
  error text
);

create index if not exists widget_snapshot_receipts_user_requested_idx
  on public.widget_snapshot_receipts (user_id, requested_at desc);

create index if not exists widget_snapshot_receipts_token_hash_idx
  on public.widget_snapshot_receipts (token_hash, requested_at desc);

alter table public.widget_snapshot_receipts enable row level security;

drop policy if exists "Users can select their widget snapshot receipts" on public.widget_snapshot_receipts;
create policy "Users can select their widget snapshot receipts"
  on public.widget_snapshot_receipts
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can delete their widget snapshot receipts" on public.widget_snapshot_receipts;
create policy "Users can delete their widget snapshot receipts"
  on public.widget_snapshot_receipts
  for delete
  to authenticated
  using (auth.uid() = user_id);

revoke all privileges on table public.widget_snapshot_receipts from anon;
revoke insert, update, truncate, references, trigger on table public.widget_snapshot_receipts from authenticated;
grant select, delete on table public.widget_snapshot_receipts to authenticated;
grant all privileges on table public.widget_snapshot_receipts to service_role;
