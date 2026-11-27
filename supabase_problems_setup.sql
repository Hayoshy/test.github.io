-- Выполните один раз в Supabase → SQL Editor (после supabase_auth_setup.sql).
-- Создаёт: метки (problems), голоса (problem_votes), хранилище медиа и
-- представление problems_feed, которое считает голоса и итоговый статус.

-- 0. На случай, если supabase_auth_setup.sql ещё не запускали.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  role text not null default 'user',
  avatar_url text,
  created_at timestamptz not null default now()
);

-- 1. Метки на карте -----------------------------------------------------
-- Тип category_id берём у существующей таблицы categories, чтобы внешний ключ
-- сошёлся при любом типе id (int, bigint, uuid).
do $$
declare
  cat_type text;
begin
  select format_type(a.atttypid, a.atttypmod)
    into cat_type
    from pg_attribute a
   where a.attrelid = 'public.categories'::regclass
     and a.attname = 'id'
     and not a.attisdropped;

  execute format($f$
    create table if not exists public.problems (
      id                bigint generated always as identity primary key,
      user_id           uuid not null default auth.uid() references auth.users(id) on delete cascade,
      category_id       %s not null references public.categories(id),
      lat               double precision not null check (lat between -90 and 90),
      lng               double precision not null check (lng between -180 and 180),
      address           text,
      district          text,
      works_in_progress boolean not null default false,
      comment           text check (char_length(comment) <= 1000),
      media             jsonb not null default '[]'::jsonb,
      created_at        timestamptz not null default now()
    )
  $f$, cat_type);
end
$$;

create index if not exists problems_created_at_idx on public.problems (created_at desc);
create index if not exists problems_user_idx on public.problems (user_id);

-- 2. Голоса «проблема решена?» ------------------------------------------
-- Первичный ключ (problem_id, user_id): один голос на событие, его можно менять.
create table if not exists public.problem_votes (
  problem_id bigint not null references public.problems(id) on delete cascade,
  user_id    uuid   not null default auth.uid() references auth.users(id) on delete cascade,
  solved     boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (problem_id, user_id)
);

create or replace function public.touch_vote()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists problem_votes_touch on public.problem_votes;
create trigger problem_votes_touch
before update on public.problem_votes
for each row execute procedure public.touch_vote();

-- 3. Права и RLS ----------------------------------------------------------
alter table public.problems enable row level security;
alter table public.problem_votes enable row level security;

grant select on public.problems to anon, authenticated;
grant insert, delete on public.problems to authenticated;
grant select, insert, update on public.problem_votes to authenticated;

-- Метки видны всем, в том числе без входа.
drop policy if exists "Problems are public" on public.problems;
create policy "Problems are public"
on public.problems for select to anon, authenticated
using (true);

drop policy if exists "Users add own problems" on public.problems;
create policy "Users add own problems"
on public.problems for insert to authenticated
with check (user_id = auth.uid());

drop policy if exists "Users delete own problems" on public.problems;
create policy "Users delete own problems"
on public.problems for delete to authenticated
using (user_id = auth.uid());

-- Свой голос виден только автору голоса, а общие счётчики отдаёт problems_feed.
drop policy if exists "Users read own votes" on public.problem_votes;
create policy "Users read own votes"
on public.problem_votes for select to authenticated
using (user_id = auth.uid());

-- Голосовать можно только пока идут 14 дней с момента создания метки.
drop policy if exists "Users vote while open" on public.problem_votes;
create policy "Users vote while open"
on public.problem_votes for insert to authenticated
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.problems p
     where p.id = problem_id
       and p.created_at + interval '14 days' > now()
  )
);

drop policy if exists "Users change vote while open" on public.problem_votes;
create policy "Users change vote while open"
on public.problem_votes for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and exists (
    select 1 from public.problems p
     where p.id = problem_id
       and p.created_at + interval '14 days' > now()
  )
);

-- 4. Лента событий: счётчики голосов и статус ----------------------------
-- Статус считается на лету, поэтому cron не нужен:
--   solved      — прошло 14 дней и «да» больше, чем «нет»;
--   in_progress — работы ведутся;
--   unsolved    — всё остальное.
-- Представление работает с правами владельца, поэтому счётчики и имя автора
-- доступны всем, хотя сами строки problem_votes и profiles закрыты RLS.
drop view if exists public.problems_feed;
create view public.problems_feed as
select
  p.id,
  p.user_id,
  pr.username                                   as author,
  p.category_id,
  c.name                                        as category_name,
  p.lat,
  p.lng,
  p.address,
  p.district,
  p.works_in_progress,
  p.comment,
  p.media,
  p.created_at,
  p.created_at + interval '14 days'             as voting_ends_at,
  (p.created_at + interval '14 days' > now())   as voting_open,
  coalesce(v.yes_votes, 0)::int                 as yes_votes,
  coalesce(v.no_votes, 0)::int                  as no_votes,
  case
    when p.created_at + interval '14 days' <= now()
         and coalesce(v.yes_votes, 0) > coalesce(v.no_votes, 0) then 'solved'
    when p.works_in_progress then 'in_progress'
    else 'unsolved'
  end                                           as status
from public.problems p
join public.categories c on c.id = p.category_id
left join public.profiles pr on pr.id = p.user_id
left join lateral (
  select
    count(*) filter (where solved)     as yes_votes,
    count(*) filter (where not solved) as no_votes
  from public.problem_votes pv
  where pv.problem_id = p.id
) v on true;

grant select on public.problems_feed to anon, authenticated;


-- 5. Обновить кэш API, иначе будет ошибка «таблица не найдена»
notify pgrst, 'reload schema';
