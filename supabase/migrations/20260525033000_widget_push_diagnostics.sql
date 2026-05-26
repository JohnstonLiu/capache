alter table public.widget_push_tokens
  add column if not exists last_push_at timestamptz,
  add column if not exists last_push_success_at timestamptz,
  add column if not exists last_push_status integer,
  add column if not exists last_push_reason text,
  add column if not exists last_push_error text,
  add column if not exists last_push_environment text
    check (last_push_environment is null or last_push_environment in ('sandbox', 'production')),
  add column if not exists last_push_apns_id text;

create table if not exists public.widget_push_receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token_hash text not null,
  environment text not null check (environment in ('sandbox', 'production')),
  topic text not null,
  sent_at timestamptz not null default now(),
  apns_status integer,
  apns_reason text,
  apns_error text,
  apns_id text,
  removed boolean not null default false
);

create index if not exists widget_push_receipts_user_sent_idx
  on public.widget_push_receipts (user_id, sent_at desc);

create index if not exists widget_push_receipts_token_hash_idx
  on public.widget_push_receipts (token_hash, sent_at desc);

alter table public.widget_push_receipts enable row level security;

drop policy if exists "Users can select their widget push receipts" on public.widget_push_receipts;
create policy "Users can select their widget push receipts"
  on public.widget_push_receipts
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can delete their widget push receipts" on public.widget_push_receipts;
create policy "Users can delete their widget push receipts"
  on public.widget_push_receipts
  for delete
  to authenticated
  using (auth.uid() = user_id);

revoke all privileges on table public.widget_push_receipts from anon;
revoke insert, update, truncate, references, trigger on table public.widget_push_receipts from authenticated;
grant select, delete on table public.widget_push_receipts to authenticated;
grant all privileges on table public.widget_push_receipts to service_role;
