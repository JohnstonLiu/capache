create table if not exists public.widget_refresh_tokens (
  token_hash text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  platform text not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists widget_refresh_tokens_user_idx
  on public.widget_refresh_tokens (user_id, updated_at desc);

alter table public.widget_refresh_tokens enable row level security;

drop policy if exists "Users can select their widget refresh tokens" on public.widget_refresh_tokens;
create policy "Users can select their widget refresh tokens"
  on public.widget_refresh_tokens
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their widget refresh tokens" on public.widget_refresh_tokens;
create policy "Users can insert their widget refresh tokens"
  on public.widget_refresh_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their widget refresh tokens" on public.widget_refresh_tokens;
create policy "Users can update their widget refresh tokens"
  on public.widget_refresh_tokens
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their widget refresh tokens" on public.widget_refresh_tokens;
create policy "Users can delete their widget refresh tokens"
  on public.widget_refresh_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id);

create table if not exists public.widget_push_tokens (
  token text primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  platform text not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists widget_push_tokens_user_environment_idx
  on public.widget_push_tokens (user_id, environment, updated_at desc);

alter table public.widget_push_tokens enable row level security;

drop policy if exists "Users can select their widget push tokens" on public.widget_push_tokens;
create policy "Users can select their widget push tokens"
  on public.widget_push_tokens
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their widget push tokens" on public.widget_push_tokens;
create policy "Users can insert their widget push tokens"
  on public.widget_push_tokens
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their widget push tokens" on public.widget_push_tokens;
create policy "Users can update their widget push tokens"
  on public.widget_push_tokens
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their widget push tokens" on public.widget_push_tokens;
create policy "Users can delete their widget push tokens"
  on public.widget_push_tokens
  for delete
  to authenticated
  using (auth.uid() = user_id);

revoke all privileges on table public.widget_refresh_tokens from anon;
revoke all privileges on table public.widget_push_tokens from anon;

revoke truncate, references, trigger on table public.widget_refresh_tokens from authenticated;
revoke truncate, references, trigger on table public.widget_push_tokens from authenticated;

grant select, insert, update, delete on table public.widget_refresh_tokens to authenticated;
grant select, insert, update, delete on table public.widget_push_tokens to authenticated;
