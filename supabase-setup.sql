-- Cole TUDO isto no Supabase: SQL Editor > New query > Run

create table households(
  id uuid primary key default gen_random_uuid(),
  code text unique not null default substr(md5(random()::text||clock_timestamp()::text),1,8),
  created_at timestamptz default now());

create table members(
  user_id uuid primary key references auth.users on delete cascade,
  household uuid not null references households on delete cascade,
  slot text not null check (slot in ('eu','ela')),
  name text not null default '',
  unique(household,slot));

create table items(
  household uuid not null references households on delete cascade,
  id text not null,
  kind text not null check (kind in ('task','rot')),
  owner uuid not null references auth.users,
  priv boolean not null default false,
  deleted boolean not null default false,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  primary key(household,id));

create function my_household() returns uuid language sql stable security definer set search_path=public as
$$ select household from members where user_id=auth.uid() $$;

alter table households enable row level security;
alter table members enable row level security;
alter table items enable row level security;

create policy hh_sel on households for select using (id=my_household());
create policy mem_sel on members for select using (household=my_household());
create policy mem_upd on members for update using (user_id=auth.uid());
-- tarefas privadas só aparecem para quem criou
create policy it_sel on items for select using (household=my_household() and (not priv or owner=auth.uid()));
create policy it_ins on items for insert with check (household=my_household() and owner=auth.uid());
create policy it_upd on items for update using (household=my_household() and (not priv or owner=auth.uid()))
  with check (household=my_household() and (not priv or owner=auth.uid()));

create function create_household(nick text) returns text language plpgsql security definer set search_path=public as $$
declare h uuid; c text;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  if exists(select 1 from members where user_id=auth.uid()) then raise exception 'Você já tem uma casa'; end if;
  insert into households default values returning id, code into h, c;
  insert into members(user_id,household,slot,name) values(auth.uid(),h,'eu',nick);
  return c;
end $$;

create function join_household(invite text, nick text) returns void language plpgsql security definer set search_path=public as $$
declare h uuid;
begin
  if auth.uid() is null then raise exception 'Faça login'; end if;
  if exists(select 1 from members where user_id=auth.uid()) then raise exception 'Você já tem uma casa'; end if;
  select id into h from households where code=lower(trim(invite));
  if h is null then raise exception 'Código inválido'; end if;
  if exists(select 1 from members where household=h and slot='ela') then raise exception 'Esta casa já tem duas pessoas'; end if;
  insert into members(user_id,household,slot,name) values(auth.uid(),h,'ela',nick);
end $$;

alter publication supabase_realtime add table public.items;
