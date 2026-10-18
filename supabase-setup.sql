-- Mission 26 Supabase setup
-- Safe to rerun. Existing application rows are preserved.
-- Run in Supabase Dashboard > SQL Editor as the project owner.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
    id text primary key references auth.users(id) on delete cascade,
    name text not null default 'Player',
    username text not null unique,
    email text,
    bio text default '',
    avatar_url text default 'bengal_tiger',
    custom_photo_url text,
    coins bigint not null default 1000 check (coins >= 0),
    games_played integer not null default 0,
    games_won integer not null default 0,
    games_lost integer not null default 0,
    referral_code text unique,
    referred_by text,
    total_referrals integer not null default 0,
    referral_coins integer not null default 0,
    rank_title text default 'Rookie',
    level integer not null default 1,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.profiles
    add column if not exists email text,
    add column if not exists bio text default '',
    add column if not exists avatar_url text default 'bengal_tiger',
    add column if not exists custom_photo_url text,
    add column if not exists coins bigint not null default 1000,
    add column if not exists games_played integer not null default 0,
    add column if not exists games_won integer not null default 0,
    add column if not exists games_lost integer not null default 0,
    add column if not exists referral_code text,
    add column if not exists referred_by text,
    add column if not exists total_referrals integer not null default 0,
    add column if not exists referral_coins integer not null default 0,
    add column if not exists rank_title text default 'Rookie',
    add column if not exists level integer not null default 1,
    add column if not exists created_at timestamptz not null default now(),
    add column if not exists updated_at timestamptz not null default now();

create unique index if not exists profiles_username_unique on public.profiles(username);
create unique index if not exists profiles_referral_code_unique on public.profiles(referral_code)
    where referral_code is not null;
create index if not exists profiles_coins_leaderboard on public.profiles(coins desc);
create index if not exists profiles_wins_leaderboard on public.profiles(games_won desc);

create or replace function public.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
    base_name text;
    chosen_username text;
begin
    base_name := coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1), 'player');
    chosen_username := lower(regexp_replace(
        coalesce(nullif(new.raw_user_meta_data ->> 'username', ''), base_name),
        '[^a-zA-Z0-9_]', '_', 'g'
    ));
    if chosen_username = '' then
        chosen_username := 'player';
    end if;
    if exists (select 1 from public.profiles p where p.username = chosen_username) then
        chosen_username := left(chosen_username, 20) || '_' || left(replace(new.id::text, '-', ''), 8);
    end if;

    insert into public.profiles (
        id, name, username, email, avatar_url, coins, referral_code, rank_title, level
    ) values (
        new.id::text,
        base_name,
        chosen_username,
        new.email,
        coalesce(new.raw_user_meta_data ->> 'avatar_url', 'bengal_tiger'),
        1000,
        'M26-' || upper(left(replace(new.id::text, '-', ''), 8)),
        'Rookie',
        1
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created_mission26 on auth.users;
create trigger on_auth_user_created_mission26
    after insert on auth.users
    for each row execute function public.create_profile_for_auth_user();

create table if not exists public.chat_messages (
    id text primary key,
    sender_id text not null,
    sender_name text not null,
    sender_avatar text not null default 'bengal_tiger',
    sender_photo_url text,
    message text not null check (length(message) between 1 and 2000),
    game_invite_code varchar(10),
    created_at timestamptz not null default now()
);
create index if not exists chat_messages_created_at on public.chat_messages(created_at desc);

create table if not exists public.private_messages (
    id uuid primary key default gen_random_uuid(),
    sender_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
    recipient_id uuid not null references auth.users(id) on delete cascade,
    message text not null check (length(message) between 1 and 4000),
    created_at timestamptz not null default now(),
    constraint private_message_not_self check (sender_id <> recipient_id)
);
alter table public.private_messages alter column sender_id set default auth.uid();
create index if not exists private_messages_pair_created
    on public.private_messages(sender_id, recipient_id, created_at desc);

create table if not exists public.matchmaking_rooms (
    room_id text primary key,
    room_code varchar(10) not null unique,
    game_type text not null,
    host_user_id uuid not null references auth.users(id) on delete cascade,
    host_name text not null,
    host_username text not null,
    host_avatar text not null default 'bengal_tiger',
    host_ready boolean not null default true,
    guest_user_id uuid references auth.users(id) on delete set null,
    guest_name text,
    guest_username text,
    guest_avatar text,
    guest_ready boolean not null default false,
    status text not null default 'WAITING'
        check (status in ('WAITING', 'STARTING', 'IN_GAME', 'CLOSED')),
    stake_coins integer not null default 50 check (stake_coins >= 0),
    is_private boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint room_players_differ check (guest_user_id is null or guest_user_id <> host_user_id)
);
create index if not exists matchmaking_rooms_public_waiting
    on public.matchmaking_rooms(game_type, created_at desc)
    where status = 'WAITING' and is_private = false;

create table if not exists public.game_match_states (
    room_code varchar(10) primary key references public.matchmaking_rooms(room_code) on delete cascade,
    game_type text not null,
    state jsonb not null default '{}'::jsonb,
    revision bigint not null default 0,
    updated_by uuid not null references auth.users(id),
    updated_at timestamptz not null default now()
);

create table if not exists public.withdrawals (
    id text primary key,
    user_id text not null references public.profiles(id) on delete cascade,
    method text not null,
    account_details text not null,
    coin_amount bigint not null check (coin_amount > 0),
    fiat_amount numeric(10, 2) not null check (fiat_amount >= 0),
    currency text not null default 'BDT',
    status text not null default 'PENDING'
        check (status in ('PENDING', 'APPROVED', 'REJECTED', 'PAID')),
    transaction_id text,
    created_at timestamptz not null default now(),
    processed_at timestamptz
);
alter table public.withdrawals drop constraint if exists withdrawals_status_check;
alter table public.withdrawals
    add constraint withdrawals_status_check
    check (status in ('PENDING', 'APPROVED', 'REJECTED', 'PAID'));
create index if not exists withdrawals_user_created on public.withdrawals(user_id, created_at desc);

create table if not exists public.transactions (
    id text primary key,
    user_id text not null references public.profiles(id) on delete cascade,
    title text not null,
    description text not null default '',
    amount bigint not null,
    type text not null,
    category text not null,
    balance_after bigint not null,
    reference_id text,
    status text not null default 'COMPLETED',
    created_at timestamptz not null default now()
);
create index if not exists transactions_user_created on public.transactions(user_id, created_at desc);

create table if not exists public.community_posts (
    id text primary key,
    author_id text not null references public.profiles(id) on delete cascade,
    author_name text not null,
    author_username text not null,
    author_avatar text not null default 'bengal_tiger',
    author_photo_url text,
    content text not null,
    image_url text,
    video_url text,
    likes_count integer not null default 0,
    comments_count integer not null default 0,
    game_tag text default 'Esports',
    created_at timestamptz not null default now()
);
create index if not exists community_posts_created on public.community_posts(created_at desc);

create table if not exists public.referrals (
    id text primary key,
    referrer_code text not null,
    referrer_id text not null references public.profiles(id) on delete cascade,
    referee_id text not null unique references public.profiles(id) on delete cascade,
    referrer_bonus integer not null default 250,
    referee_bonus integer not null default 100,
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.chat_messages enable row level security;
alter table public.private_messages enable row level security;
alter table public.matchmaking_rooms enable row level security;
alter table public.game_match_states enable row level security;
alter table public.withdrawals enable row level security;
alter table public.transactions enable row level security;
alter table public.community_posts enable row level security;
alter table public.referrals enable row level security;

-- Remove old permissive policies installed by earlier Mission 26 scripts.
do $$
declare
    policy_row record;
begin
    for policy_row in
        select schemaname, tablename, policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = any(array[
              'profiles', 'chat_messages', 'private_messages', 'matchmaking_rooms',
              'game_match_states', 'withdrawals', 'transactions',
              'community_posts', 'referrals'
          ])
    loop
        execute format('drop policy if exists %I on %I.%I',
            policy_row.policyname, policy_row.schemaname, policy_row.tablename);
    end loop;
end;
$$;

create policy profiles_anon_select on public.profiles
    for select to anon using (true);
create policy profiles_owner_select on public.profiles
    for select to authenticated using (id = (select auth.uid())::text);
create policy profiles_owner_update on public.profiles
    for update to authenticated
    using (id = (select auth.uid())::text)
    with check (id = (select auth.uid())::text);

create or replace view public.public_profiles as
    select id, name, username, avatar_url, coins, games_played, games_won,
           games_lost, rank_title, level, created_at, updated_at
    from public.profiles;
grant select on public.public_profiles to anon, authenticated;
grant select (id, name, username, avatar_url, coins, games_played, games_won,
              games_lost, rank_title, level, created_at, updated_at)
    on public.profiles to anon;
grant select on public.profiles to authenticated;
revoke insert, delete on public.profiles from anon, authenticated;
revoke update on public.profiles from anon, authenticated;
grant update (name, username, bio, avatar_url, custom_photo_url, updated_at)
    on public.profiles to authenticated;

create policy chat_authenticated_read on public.chat_messages
    for select to authenticated using (true);
create policy chat_owner_insert on public.chat_messages
    for insert to authenticated
    with check (sender_id = (select auth.uid())::text);

create policy private_messages_participant_read on public.private_messages
    for select to authenticated
    using (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()));
create policy private_messages_sender_insert on public.private_messages
    for insert to authenticated
    with check (sender_id = (select auth.uid()));

create policy matchmaking_authenticated_read on public.matchmaking_rooms
    for select to authenticated using (true);
create policy matchmaking_member_update on public.matchmaking_rooms
    for update to authenticated
    using (host_user_id = (select auth.uid()) or guest_user_id = (select auth.uid()))
    with check (host_user_id = (select auth.uid()) or guest_user_id = (select auth.uid()));

create policy match_state_participant_read on public.game_match_states
    for select to authenticated
    using (exists (
        select 1 from public.matchmaking_rooms r
        where r.room_code = game_match_states.room_code
          and (r.host_user_id = (select auth.uid()) or r.guest_user_id = (select auth.uid()))
    ));
create policy match_state_participant_write on public.game_match_states
    for all to authenticated
    using (exists (
        select 1 from public.matchmaking_rooms r
        where r.room_code = game_match_states.room_code
          and (r.host_user_id = (select auth.uid()) or r.guest_user_id = (select auth.uid()))
    ))
    with check (
        updated_by = (select auth.uid())
        and exists (
            select 1 from public.matchmaking_rooms r
            where r.room_code = game_match_states.room_code
              and (r.host_user_id = (select auth.uid()) or r.guest_user_id = (select auth.uid()))
        )
    );

create policy withdrawals_owner_read on public.withdrawals
    for select to authenticated using (user_id = (select auth.uid())::text);
create policy transactions_owner_read on public.transactions
    for select to authenticated using (user_id = (select auth.uid())::text);
create policy community_authenticated_read on public.community_posts
    for select to authenticated using (true);
create policy community_owner_insert on public.community_posts
    for insert to authenticated with check (author_id = (select auth.uid())::text);
create policy referrals_participant_read on public.referrals
    for select to authenticated
    using (referrer_id = (select auth.uid())::text or referee_id = (select auth.uid())::text);

revoke all on public.withdrawals, public.transactions, public.referrals from anon, authenticated;
grant select on public.withdrawals, public.transactions, public.referrals to authenticated;
revoke insert, update, delete on public.withdrawals, public.transactions, public.referrals
    from anon, authenticated;
grant select, insert on public.chat_messages to authenticated;
grant select on public.private_messages to authenticated;
grant insert (recipient_id, message) on public.private_messages to authenticated;
grant select on public.matchmaking_rooms to authenticated;
grant update (host_ready, guest_ready, status, updated_at) on public.matchmaking_rooms to authenticated;
grant select, insert, update on public.game_match_states to authenticated;
grant select, insert on public.community_posts to authenticated;

create or replace function public.make_tic_tac_toe_move(
    p_room_code text,
    p_cell_index integer
)
returns setof public.game_match_states
language plpgsql
security definer
set search_path = ''
as $$
declare
    room_row public.matchmaking_rooms%rowtype;
    match_row public.game_match_states%rowtype;
    board_value jsonb;
    new_board jsonb;
    new_state jsonb;
    player_symbol text;
    winner_symbol text;
    is_draw boolean;
    next_symbol text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if p_cell_index < 0 or p_cell_index > 8 then
        raise exception 'Invalid Tic-Tac-Toe cell';
    end if;

    select * into room_row
    from public.matchmaking_rooms
    where room_code = upper(trim(p_room_code))
    for update;
    if not found or room_row.game_type <> 'TIC_TAC_TOE'
       or room_row.guest_user_id is null
       or room_row.status not in ('STARTING', 'IN_GAME')
       or (room_row.host_user_id <> auth.uid() and room_row.guest_user_id <> auth.uid()) then
        raise exception 'Tic-Tac-Toe room is not available to this player';
    end if;

    player_symbol := case when room_row.host_user_id = auth.uid() then 'X' else 'O' end;
    insert into public.game_match_states (room_code, game_type, state, revision, updated_by)
    values (
        room_row.room_code,
        'TIC_TAC_TOE',
        pg_catalog.jsonb_build_object(
            'board', '["","","","","","","","",""]'::jsonb,
            'nextPlayer', 'X',
            'winner', null,
            'draw', false
        ),
        0,
        auth.uid()
    )
    on conflict (room_code) do nothing;

    select * into match_row
    from public.game_match_states
    where room_code = room_row.room_code
    for update;

    board_value := match_row.state -> 'board';
    if match_row.game_type <> 'TIC_TAC_TOE'
       or pg_catalog.jsonb_typeof(board_value) <> 'array'
       or pg_catalog.jsonb_array_length(board_value) <> 9 then
        raise exception 'Invalid Tic-Tac-Toe match state';
    end if;
    if match_row.state ->> 'winner' is not null
       and match_row.state ->> 'winner' <> '' then
        raise exception 'Tic-Tac-Toe match is already finished';
    end if;
    if coalesce((match_row.state ->> 'draw')::boolean, false) then
        raise exception 'Tic-Tac-Toe match is already finished';
    end if;
    if match_row.state ->> 'nextPlayer' <> player_symbol then
        raise exception 'It is not your turn';
    end if;
    if board_value ->> p_cell_index <> '' then
        raise exception 'That Tic-Tac-Toe cell is already occupied';
    end if;

    new_board := pg_catalog.jsonb_set(
        board_value,
        array[p_cell_index::text],
        pg_catalog.to_jsonb(player_symbol),
        false
    );
    select new_board ->> a
    into winner_symbol
    from (values
        (0, 1, 2), (3, 4, 5), (6, 7, 8),
        (0, 3, 6), (1, 4, 7), (2, 5, 8),
        (0, 4, 8), (2, 4, 6)
    ) as winning_lines(a, b, c)
    where new_board ->> a = new_board ->> b
      and new_board ->> b = new_board ->> c
      and new_board ->> a <> ''
    limit 1;

    is_draw := winner_symbol is null and not exists (
        select 1
        from pg_catalog.generate_series(0, 8) as cells(cell_index)
        where new_board ->> cell_index = ''
    );
    next_symbol := case
        when winner_symbol is not null or is_draw then player_symbol
        when player_symbol = 'X' then 'O'
        else 'X'
    end;
    new_state := pg_catalog.jsonb_build_object(
        'board', new_board,
        'nextPlayer', next_symbol,
        'winner', winner_symbol,
        'draw', is_draw
    );

    update public.game_match_states
    set state = new_state,
        revision = revision + 1,
        updated_by = auth.uid(),
        updated_at = now()
    where room_code = room_row.room_code
    returning * into match_row;

    update public.matchmaking_rooms
    set status = 'IN_GAME', updated_at = now()
    where room_code = room_row.room_code;

    return next match_row;
end;
$$;

create or replace function public.create_matchmaking_room(
    p_game_type text,
    p_host_name text,
    p_host_username text,
    p_host_avatar text,
    p_is_private boolean default false,
    p_stake_coins integer default 50
)
returns setof public.matchmaking_rooms
language plpgsql
security definer
set search_path = ''
as $$
declare
    new_code text;
    new_room_id text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if length(trim(p_game_type)) = 0 or p_stake_coins < 0 then
        raise exception 'Invalid room settings';
    end if;

    loop
        new_code := lpad((floor(random() * 1000000))::integer::text, 6, '0');
        exit when not exists (
            select 1 from public.matchmaking_rooms r where r.room_code = new_code
        );
    end loop;
    new_room_id := gen_random_uuid()::text;

    return query
    insert into public.matchmaking_rooms (
        room_id, room_code, game_type, host_user_id, host_name,
        host_username, host_avatar, is_private, stake_coins
    ) values (
        new_room_id, new_code, p_game_type, auth.uid(), p_host_name,
        p_host_username, p_host_avatar, p_is_private, p_stake_coins
    )
    returning *;
end;
$$;

create or replace function public.join_matchmaking_room(
    p_room_code text,
    p_guest_name text,
    p_guest_username text,
    p_guest_avatar text
)
returns setof public.matchmaking_rooms
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    return query
    update public.matchmaking_rooms r
    set guest_user_id = auth.uid(),
        guest_name = p_guest_name,
        guest_username = p_guest_username,
        guest_avatar = p_guest_avatar,
        guest_ready = true,
        status = case when r.host_ready then 'STARTING' else 'WAITING' end,
        updated_at = now()
    where r.room_code = upper(trim(p_room_code))
      and r.status = 'WAITING'
      and r.guest_user_id is null
      and r.host_user_id <> auth.uid()
    returning r.*;

    if not found then
        raise exception 'Room not found, full, or unavailable';
    end if;
end;
$$;

create or replace function public.find_or_create_matchmaking_room(
    p_game_type text,
    p_player_name text,
    p_player_username text,
    p_player_avatar text
)
returns setof public.matchmaking_rooms
language plpgsql
security definer
set search_path = ''
as $$
declare
    selected_room public.matchmaking_rooms%rowtype;
    new_code text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if nullif(trim(p_game_type), '') is null then
        raise exception 'Game type is required';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(p_game_type)::bigint);

    select * into selected_room
    from public.matchmaking_rooms r
    where r.game_type = p_game_type
      and r.status in ('WAITING', 'STARTING')
      and not r.is_private
      and (r.host_user_id = auth.uid() or r.guest_user_id = auth.uid())
    order by r.created_at desc
    limit 1
    for update;

    if found then
        return next selected_room;
        return;
    end if;

    select * into selected_room
    from public.matchmaking_rooms r
    where r.game_type = p_game_type
      and r.status = 'WAITING'
      and not r.is_private
      and r.guest_user_id is null
      and r.host_user_id <> auth.uid()
    order by r.created_at asc
    limit 1
    for update skip locked;

    if found then
        update public.matchmaking_rooms r
        set guest_user_id = auth.uid(),
            guest_name = p_player_name,
            guest_username = p_player_username,
            guest_avatar = p_player_avatar,
            guest_ready = true,
            status = case when r.host_ready then 'STARTING' else 'WAITING' end,
            updated_at = now()
        where r.room_id = selected_room.room_id
        returning * into selected_room;
        return next selected_room;
        return;
    end if;

    loop
        new_code := pg_catalog.lpad((pg_catalog.floor(pg_catalog.random() * 1000000))::integer::text, 6, '0');
        exit when not exists (
            select 1 from public.matchmaking_rooms r where r.room_code = new_code
        );
    end loop;

    return query
    insert into public.matchmaking_rooms (
        room_id, room_code, game_type, host_user_id, host_name,
        host_username, host_avatar, is_private, stake_coins
    ) values (
        extensions.gen_random_uuid()::text, new_code, p_game_type, auth.uid(),
        p_player_name, p_player_username, p_player_avatar, false, 50
    )
    returning *;
end;
$$;

create or replace function public.apply_coin_transaction(
    p_id text,
    p_title text,
    p_description text,
    p_amount bigint,
    p_type text,
    p_category text,
    p_reference_id text,
    p_status text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_balance bigint;
    new_balance bigint;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if p_amount <= 0 or p_type not in ('CREDIT', 'DEBIT') then
        raise exception 'Invalid coin transaction';
    end if;

    select p.coins into current_balance
    from public.profiles p
    where p.id = auth.uid()::text
    for update;
    if not found then
        raise exception 'Player profile not found';
    end if;

    if exists (
        select 1 from public.transactions t
        where t.id = p_id and t.user_id = auth.uid()::text
    ) then
        return current_balance;
    end if;

    new_balance := current_balance + case when p_type = 'CREDIT' then p_amount else -p_amount end;
    if new_balance < 0 then
        raise exception 'Insufficient coin balance';
    end if;

    update public.profiles
    set coins = new_balance, updated_at = now()
    where id = auth.uid()::text;

    insert into public.transactions (
        id, user_id, title, description, amount, type, category,
        balance_after, reference_id, status
    ) values (
        p_id, auth.uid()::text, p_title, p_description, p_amount,
        p_type, p_category, new_balance, p_reference_id, p_status
    );

    return new_balance;
end;
$$;

create or replace function public.record_match_outcome(p_won boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    update public.profiles
    set games_played = games_played + 1,
        games_won = games_won + case when p_won then 1 else 0 end,
        games_lost = games_lost + case when p_won then 0 else 1 end,
        updated_at = now()
    where id = auth.uid()::text;

    if not found then
        raise exception 'Player profile not found';
    end if;
end;
$$;

create or replace function public.leave_matchmaking_room(p_room_code text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
    update public.matchmaking_rooms
    set status = 'CLOSED', updated_at = now()
    where room_code = upper(trim(p_room_code))
      and host_user_id = auth.uid();

    update public.matchmaking_rooms
    set guest_user_id = null, guest_name = null, guest_username = null,
        guest_avatar = null, guest_ready = false, status = 'WAITING', updated_at = now()
    where room_code = upper(trim(p_room_code))
      and guest_user_id = auth.uid();
end;
$$;

create or replace function public.set_matchmaking_room_ready(
    p_room_code text,
    p_is_ready boolean
)
returns setof public.matchmaking_rooms
language plpgsql
security definer
set search_path = ''
as $$
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;

    return query
    update public.matchmaking_rooms r
    set host_ready = case when r.host_user_id = auth.uid() then p_is_ready else r.host_ready end,
        guest_ready = case when r.guest_user_id = auth.uid() then p_is_ready else r.guest_ready end,
        status = case
            when p_is_ready
             and (r.host_user_id = auth.uid() or r.host_ready)
             and (r.guest_user_id = auth.uid() or r.guest_ready)
            then 'STARTING'
            when r.status = 'STARTING' then 'WAITING'
            else r.status
        end,
        updated_at = now()
    where r.room_code = upper(trim(p_room_code))
      and (r.host_user_id = auth.uid() or r.guest_user_id = auth.uid())
      and r.status in ('WAITING', 'STARTING')
    returning r.*;

    if not found then
        raise exception 'Room not found or unavailable';
    end if;
end;
$$;

create or replace function public.request_withdrawal(
    p_method text,
    p_account_details text,
    p_coin_amount bigint
)
returns setof public.withdrawals
language plpgsql
security definer
set search_path = ''
as $$
declare
    current_balance bigint;
    payout_currency text;
    payout_value numeric(10, 2);
    fee_percent numeric(5, 2);
    withdrawal_id text := gen_random_uuid()::text;
begin
    if auth.uid() is null then
        raise exception 'Authentication required';
    end if;
    if p_coin_amount <= 0 or length(trim(p_account_details)) = 0 then
        raise exception 'Invalid withdrawal request';
    end if;

    if p_method in ('bKash Personal', 'bKash Agent', 'Nagad Personal') then
        if p_coin_amount < 5000 then
            raise exception 'Minimum withdrawal for this method is 5000 coins';
        end if;
        payout_currency := 'BDT';
        fee_percent := case p_method
            when 'bKash Personal' then 1.8
            when 'bKash Agent' then 1.5
            else 1.2
        end;
        payout_value := round((p_coin_amount::numeric / 1000 * 22) * (1 - fee_percent / 100), 2);
    elsif p_method in ('USDT (BEP20)', 'USDT (Solana)') then
        if p_coin_amount < 1000 then
            raise exception 'Minimum withdrawal for this method is 1000 coins';
        end if;
        payout_currency := 'USDT';
        payout_value := round(p_coin_amount::numeric / 1000 * 0.18, 2);
    else
        raise exception 'Unsupported withdrawal method';
    end if;

    select p.coins into current_balance
    from public.profiles p
    where p.id = auth.uid()::text
    for update;
    if current_balance is null or current_balance < p_coin_amount then
        raise exception 'Insufficient coin balance';
    end if;

    update public.profiles
    set coins = coins - p_coin_amount,
        updated_at = now()
    where id = auth.uid()::text;

    insert into public.transactions (
        id, user_id, title, description, amount, type, category,
        balance_after, reference_id, status
    ) values (
        gen_random_uuid()::text,
        auth.uid()::text,
        'Cashout request',
        'Withdrawal request submitted for manual processing',
        p_coin_amount,
        'DEBIT',
        'CASHOUT_WITHDRAWAL',
        current_balance - p_coin_amount,
        withdrawal_id,
        'PENDING'
    );

    return query
    insert into public.withdrawals (
        id, user_id, method, account_details, coin_amount,
        fiat_amount, currency, status, transaction_id
    ) values (
        withdrawal_id, auth.uid()::text, p_method, trim(p_account_details),
        p_coin_amount, payout_value, payout_currency, 'PENDING', withdrawal_id
    )
    returning *;
end;
$$;

create or replace function public.admin_set_withdrawal_status(
    p_withdrawal_id text,
    p_new_status text,
    p_payout_transaction_id text default null
)
returns setof public.withdrawals
language plpgsql
security definer
set search_path = ''
as $$
declare
    withdrawal_row public.withdrawals%rowtype;
    current_balance bigint;
    new_balance bigint;
begin
    if session_user not in ('postgres', 'supabase_admin')
       and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
        raise exception 'Withdrawal administrator access required';
    end if;
    if p_new_status not in ('APPROVED', 'REJECTED', 'PAID') then
        raise exception 'Unsupported withdrawal status';
    end if;

    select * into withdrawal_row
    from public.withdrawals
    where id = p_withdrawal_id
    for update;
    if not found then
        raise exception 'Withdrawal request not found';
    end if;
    if withdrawal_row.status = p_new_status then
        return next withdrawal_row;
        return;
    end if;
    if not (
        (withdrawal_row.status = 'PENDING' and p_new_status in ('APPROVED', 'REJECTED'))
        or (withdrawal_row.status = 'APPROVED' and p_new_status = 'PAID')
    ) then
        raise exception 'Invalid withdrawal status transition: % -> %',
            withdrawal_row.status, p_new_status;
    end if;

    if p_new_status = 'REJECTED' then
        select coins into current_balance
        from public.profiles
        where id = withdrawal_row.user_id
        for update;
        if not found then
            raise exception 'Withdrawal owner profile not found';
        end if;
        new_balance := current_balance + withdrawal_row.coin_amount;
        update public.profiles
        set coins = new_balance, updated_at = now()
        where id = withdrawal_row.user_id;

        insert into public.transactions (
            id, user_id, title, description, amount, type, category,
            balance_after, reference_id, status
        ) values (
            'withdrawal-refund:' || withdrawal_row.id,
            withdrawal_row.user_id,
            'Cashout request refunded',
            'Withdrawal request was rejected; coins returned to your balance',
            withdrawal_row.coin_amount,
            'CREDIT',
            'CASHOUT_WITHDRAWAL',
            new_balance,
            withdrawal_row.id,
            'COMPLETED'
        );
    end if;

    update public.withdrawals
    set status = p_new_status,
        transaction_id = case
            when p_new_status = 'PAID' and nullif(trim(p_payout_transaction_id), '') is not null
                then trim(p_payout_transaction_id)
            else transaction_id
        end,
        processed_at = case when p_new_status in ('REJECTED', 'PAID') then now() else processed_at end
    where id = withdrawal_row.id
    returning * into withdrawal_row;

    update public.transactions
    set status = p_new_status
    where reference_id = withdrawal_row.id
      and type = 'DEBIT'
      and category = 'CASHOUT_WITHDRAWAL';

    return next withdrawal_row;
end;
$$;

revoke all on function public.create_matchmaking_room(text, text, text, text, boolean, integer) from public;
revoke all on function public.join_matchmaking_room(text, text, text, text) from public;
revoke all on function public.find_or_create_matchmaking_room(text, text, text, text) from public;
revoke all on function public.make_tic_tac_toe_move(text, integer) from public;
revoke all on function public.apply_coin_transaction(text, text, text, bigint, text, text, text, text) from public;
revoke all on function public.record_match_outcome(boolean) from public;
revoke all on function public.leave_matchmaking_room(text) from public;
revoke all on function public.set_matchmaking_room_ready(text, boolean) from public;
revoke all on function public.request_withdrawal(text, text, bigint) from public;
revoke all on function public.admin_set_withdrawal_status(text, text, text) from public;
grant execute on function public.create_matchmaking_room(text, text, text, text, boolean, integer) to authenticated;
grant execute on function public.join_matchmaking_room(text, text, text, text) to authenticated;
grant execute on function public.find_or_create_matchmaking_room(text, text, text, text) to authenticated;
grant execute on function public.make_tic_tac_toe_move(text, integer) to authenticated;
grant execute on function public.apply_coin_transaction(text, text, text, bigint, text, text, text, text) to authenticated;
grant execute on function public.record_match_outcome(boolean) to authenticated;
grant execute on function public.leave_matchmaking_room(text) to authenticated;
grant execute on function public.set_matchmaking_room_ready(text, boolean) to authenticated;
grant execute on function public.request_withdrawal(text, text, bigint) to authenticated;
grant execute on function public.admin_set_withdrawal_status(text, text, text) to authenticated;

do $$
declare
    table_name text;
begin
    foreach table_name in array array[
        'profiles', 'chat_messages', 'private_messages', 'matchmaking_rooms',
        'game_match_states', 'withdrawals', 'transactions',
        'community_posts', 'referrals'
    ] loop
        if not exists (
            select 1
            from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = table_name
        ) then
            execute format('alter publication supabase_realtime add table public.%I', table_name);
        end if;
    end loop;
end;
$$;
