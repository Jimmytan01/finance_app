create table if not exists public.category_budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id text not null,
  year integer not null check (year > 0),
  month integer not null check (month between 1 and 12),
  limit_amount numeric(14, 2) not null check (limit_amount > 0),
  notifications_enabled boolean not null default true,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint category_budgets_user_category_period_key
    unique (user_id, category_id, year, month)
);

alter table public.category_budgets enable row level security;

create policy "Users can read their category budgets"
  on public.category_budgets for select
  using (auth.uid() = user_id);

create policy "Users can insert their category budgets"
  on public.category_budgets for insert
  with check (auth.uid() = user_id);

create policy "Users can update their category budgets"
  on public.category_budgets for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their category budgets"
  on public.category_budgets for delete
  using (auth.uid() = user_id);
