create table if not exists public.transaction_receipts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  transaction_id uuid not null,
  storage_path text,
  mime_type text,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists transaction_receipts_one_active_per_transaction
  on public.transaction_receipts (user_id, transaction_id)
  where is_deleted = false;

alter table public.transaction_receipts enable row level security;

create policy "Users can read their transaction receipts"
  on public.transaction_receipts for select
  using (auth.uid() = user_id);

create policy "Users can insert their transaction receipts"
  on public.transaction_receipts for insert
  with check (auth.uid() = user_id);

create policy "Users can update their transaction receipts"
  on public.transaction_receipts for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete their transaction receipts"
  on public.transaction_receipts for delete
  using (auth.uid() = user_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'transaction-receipts',
  'transaction-receipts',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy "Users can read their receipt objects"
  on storage.objects for select
  using (
    bucket_id = 'transaction-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can upload their receipt objects"
  on storage.objects for insert
  with check (
    bucket_id = 'transaction-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can update their receipt objects"
  on storage.objects for update
  using (
    bucket_id = 'transaction-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'transaction-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Users can delete their receipt objects"
  on storage.objects for delete
  using (
    bucket_id = 'transaction-receipts'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
