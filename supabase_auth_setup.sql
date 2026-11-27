-- Выполните этот SQL один раз в Supabase → SQL Editor.
-- Создаёт профиль автоматически после успешной регистрации в Auth.
-- Если profiles уже содержит эти поля/ограничения, скрипт их не удаляет.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  role text not null default 'user',
  avatar_url text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

grant select, insert, update on public.profiles to authenticated;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
on public.profiles for select to authenticated
using (auth.uid() = id);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
on public.profiles for insert to authenticated
with check (auth.uid() = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

-- Функция/триггер: создаёт строку profiles при создании auth.users.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'username',
             new.raw_user_meta_data ->> 'display_name',
             split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();
