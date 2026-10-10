-- Reaction Lab: database setup for Supabase (accounts, unique usernames, leaderboards, anti-cheat).
-- Run this once in Supabase: SQL Editor > New query > paste > Run.
-- Scores can ONLY be written through submit_score(), which checks them on the server.

-- 1. Profiles: one unique username per account (case-insensitive).
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  created_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[A-Za-z0-9_]{3,16}$')
);
create unique index if not exists profiles_username_lower on public.profiles (lower(username));
alter table public.profiles enable row level security;
drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles for select using (true);
drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert" on public.profiles for insert with check (auth.uid() = id);
-- usernames cannot be changed after sign-up, so there is no update policy.

-- 2. Scores: no insert policy, so the browser cannot write here directly.
create table if not exists public.scores (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null,
  score numeric not null,
  created_at timestamptz not null default now()
);
create index if not exists scores_game_user on public.scores (game, user_id);
alter table public.scores enable row level security;
drop policy if exists "scores readable" on public.scores;
create policy "scores readable" on public.scores for select using (true);

-- 3. Plausible limits per game. Anything outside these is rejected as impossible.
create table if not exists public.game_limits (
  game text primary key,
  min_score numeric not null,
  max_score numeric not null,
  higher_is_better boolean not null
);
alter table public.game_limits enable row level security;
drop policy if exists "limits readable" on public.game_limits;
create policy "limits readable" on public.game_limits for select using (true);

insert into public.game_limits (game, min_score, max_score, higher_is_better) values
  ('seq', 0, 60, true), ('num', 0, 40, true), ('word', 0, 20, true), ('vis', 0, 16, true),
  ('ord', 1500, 60000, false), ('pop', 120, 2000, false), ('type', 0, 250, true), ('cps', 0, 16, true),
  ('space', 0, 90, true), ('track', 0, 100, true), ('colour', 0, 60, true), ('peri', 0, 20, true),
  ('multi', 0, 6, true), ('ghost', 0, 8, true), ('dual', 0, 12, true), ('blink', 0, 30, true),
  ('nerve', 0, 300, false), ('colortrap', 0, 15, true), ('flip', 0, 12, true), ('mirror', 0, 10, true),
  ('pulse', 0, 1000, false), ('schulte', 4000, 120000, false), ('bullseye', 0, 150, false),
  ('cascade', 0, 20, true), ('sprint', 0, 500, true), ('targetrush', 0, 40, true),
  ('speedround', 0, 30, true), ('dodge', 0, 20, true), ('impossible', 0, 60, true)
on conflict (game) do update set
  min_score = excluded.min_score, max_score = excluded.max_score, higher_is_better = excluded.higher_is_better;

-- 4. Is a username free? (callable before sign-up)
create or replace function public.username_available(p_username text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(p_username));
$$;

-- 5. Submit a score: signed-in users only, validated, and rate limited.
create or replace function public.submit_score(p_game text, p_score numeric)
returns void language plpgsql security definer set search_path = public as $$
declare lim public.game_limits%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in to submit scores'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception 'Create a username first'; end if;
  select * into lim from public.game_limits where game = p_game;
  if not found then raise exception 'Unknown game'; end if;
  if p_score is null or p_score < lim.min_score or p_score > lim.max_score then raise exception 'Score out of range'; end if;
  if exists (select 1 from public.scores where user_id = auth.uid() and game = p_game and created_at > now() - interval '4 seconds') then
    raise exception 'Too fast, slow down';
  end if;
  if (select count(*) from public.scores where user_id = auth.uid() and created_at > now() - interval '1 day') >= 300 then
    raise exception 'Daily limit reached';
  end if;
  insert into public.scores (user_id, game, score) values (auth.uid(), p_game, p_score);
end;
$$;

-- 6. Leaderboard: each player's best score for a game.
create or replace function public.top_scores(p_game text, p_limit int default 20)
returns table (username text, score numeric)
language sql stable security definer set search_path = public as $$
  select p.username,
         case when l.higher_is_better then max(s.score) else min(s.score) end as score
  from public.scores s
  join public.profiles p on p.id = s.user_id
  join public.game_limits l on l.game = s.game
  where s.game = p_game
  group by p.username, l.higher_is_better
  order by case when l.higher_is_better then max(s.score) end desc nulls last,
           case when not l.higher_is_better then min(s.score) end asc nulls last
  limit least(p_limit, 50);
$$;

revoke all on function public.submit_score(text, numeric) from public;
grant execute on function public.submit_score(text, numeric) to authenticated;
grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function public.top_scores(text, int) to anon, authenticated;
