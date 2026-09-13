-- Schema voor de webapp (leden, aanwezigheden, opstellingen, statistieken, logboek).
-- Uitvoeren in Supabase > SQL Editor, NA supabase/schema.sql. Mag opnieuw uitgevoerd worden.

-- ------------------------------------------------------------------ leden

create table if not exists members (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid unique references auth.users (id) on delete set null,
  naam           text not null,          -- afgeleid: voornaam + achternaam (trigger members_naam)
  voornaam       text,
  achternaam     text,
  speelt         boolean not null default false,  -- afgeleid: telt mee als speler (speler, spelercoach, verantwoordelijke)
  functie        text not null default 'speler'
                 check (functie in ('speler', 'spelercoach', 'coach', 'verantwoordelijke', 'supporter')),
  email          text not null,
  telefoon       text,
  geboortedatum  date,
  adres          text,
  status         text not null default 'wacht_op_goedkeuring'
                 check (status in ('wacht_op_goedkeuring', 'actief', 'inactief')),
  is_admin       boolean not null default false,
  is_hoofdadmin  boolean not null default false,
  aangemaakt_op  timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index if not exists members_een_hoofdadmin on members (is_hoofdadmin) where is_hoofdadmin;
alter table members add column if not exists voornaam text;
alter table members add column if not exists achternaam text;
alter table members add column if not exists speelt boolean not null default false;
alter table members add column if not exists nationaliteit text;
alter table members add column if not exists nr integer;                 -- volgnummer op de spelerslijst
alter table members add column if not exists ingeschreven boolean;       -- ingeschreven bij de federatie
alter table members add column if not exists mail_inschrijving boolean;
alter table members add column if not exists bron text not null default 'registratie';  -- import | registratie | admin
create index if not exists members_email_idx on members (lower(email));
drop table if exists members_gevoelig cascade;  -- rijksregisternummer wordt niet bijgehouden

update members
   set voornaam = split_part(naam, ' ', 1),
       achternaam = nullif(trim(substr(naam, length(split_part(naam, ' ', 1)) + 1)), '')
 where voornaam is null;

-- Afgeleide velden: volledige naam uit voornaam + achternaam, en 'speelt' uit de functie
-- (speler, spelercoach en verantwoordelijke tellen mee als speler; coach en supporter niet).
create or replace function members_naam() returns trigger
language plpgsql as $$
begin
  new.naam := trim(concat_ws(' ', nullif(trim(coalesce(new.voornaam, '')), ''), nullif(trim(coalesce(new.achternaam, '')), '')));
  if new.naam = '' then
    new.naam := split_part(new.email, '@', 1);
  end if;
  new.speelt := new.functie in ('speler', 'spelercoach', 'verantwoordelijke');
  return new;
end $$;
drop trigger if exists members_naam on members;
create trigger members_naam before insert or update on members
  for each row execute function members_naam();

-- Supporters staan apart van members en krijgen geen clubrol.
create table if not exists public.supporter_profiles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 naam text not null check(length(naam) between 1 and 100),
 actief boolean not null default true, created_at timestamptz not null default now()
);
alter table public.supporter_profiles enable row level security;
revoke all on public.supporter_profiles from anon,authenticated;
grant select on public.supporter_profiles to authenticated;
grant all on public.supporter_profiles to service_role;
drop policy if exists eigen_supporter on public.supporter_profiles;
create policy eigen_supporter on public.supporter_profiles for select to authenticated using(user_id=auth.uid());

-- Bij registratie (auth.users) het account koppelen aan een bestaand lid, of een nieuw lid aanmaken.
-- 1. Lid zonder account met hetzelfde e-mailadres: koppelen, gegevens blijven, geen goedkeuring nodig.
-- 2. Lid zonder account met dezelfde voor- en achternaam: koppelen, maar een admin moet goedkeuren
--    (tot dan blijven de persoonlijke gegevens onzichtbaar, zie mijn_lid()).
-- 3. Anders: nieuw lid dat wacht op goedkeuring. Geen automatische adminrechten in de testomgeving.
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  eerste boolean;
  v_functie text := coalesce(new.raw_user_meta_data->>'functie', 'speler');
  v_voornaam text := nullif(trim(coalesce(new.raw_user_meta_data->>'voornaam', '')), '');
  v_achternaam text := nullif(trim(coalesce(new.raw_user_meta_data->>'achternaam', '')), '');
  v_id uuid;
begin
  if new.raw_user_meta_data->>'account_type'='supporter' then
    insert into supporter_profiles(user_id,naam) values(new.id,left(coalesce(nullif(trim(new.raw_user_meta_data->>'naam'),''),'Supporter'),100));
    return new;
  end if;
  if v_functie not in ('speler', 'spelercoach', 'coach', 'verantwoordelijke', 'supporter') then
    v_functie := 'speler';
  end if;
  select id into v_id from members
   where user_id is null and lower(email) = lower(new.email)
   order by aangemaakt_op limit 1;
  if v_id is not null then
    update members
       set user_id = new.id,
           status = case when status = 'inactief' then 'wacht_op_goedkeuring' else status end
     where id = v_id;
    return new;
  end if;
  if v_voornaam is not null and v_achternaam is not null then
    select id into v_id from members
     where user_id is null and lower(voornaam) = lower(v_voornaam) and lower(achternaam) = lower(v_achternaam)
     order by aangemaakt_op limit 1;
    if v_id is not null then
      update members set user_id = new.id, status = 'wacht_op_goedkeuring' where id = v_id;
      return new;
    end if;
  end if;
  -- Testomgeving: registratie geeft nooit automatisch beheerdersrechten.
  eerste := false;
  insert into members (user_id, naam, voornaam, achternaam, email, functie, status, is_admin, is_hoofdadmin, bron)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'naam'), ''), split_part(new.email, '@', 1)),
    v_voornaam, v_achternaam, new.email,
    case when eerste then 'verantwoordelijke' else v_functie end,
    case when eerste then 'actief' else 'wacht_op_goedkeuring' end,
    eerste, eerste, 'registratie'
  );
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Hulpfuncties (security definer: omzeilen RLS zodat policies op members niet recursief worden).
create or replace function my_member_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from members where user_id = auth.uid()
$$;
create or replace function my_functie() returns text
language sql stable security definer set search_path = public as $$
  select functie from members where user_id = auth.uid() and status = 'actief'
$$;
create or replace function is_actief() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'actief' from members where user_id = auth.uid()), false)
$$;
create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin and status = 'actief' from members where user_id = auth.uid()), false)
$$;
create or replace function is_hoofdadmin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_hoofdadmin and status = 'actief' from members where user_id = auth.uid()), false)
$$;
-- Staf: coach, spelercoach, verantwoordelijke of admin.
create or replace function is_staf() returns boolean
language sql stable security definer set search_path = public as $$
  select is_admin() or coalesce(my_functie() in ('coach', 'spelercoach', 'verantwoordelijke'), false)
$$;
create or replace function is_supporter() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(my_functie() = 'supporter', false)
$$;

-- Bewaking van wijzigingen aan leden: wie mag wat veranderen.
create or replace function members_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  ik members;
begin
  if auth.uid() is null or current_setting('steca.ontkoppelen', true) = 'ja' then
    -- service-role, SQL Editor, of admin_ontkoppel_account dat een account loskoppelt: alles mag
    new.updated_at := now();
    return new;
  end if;
  select * into ik from members where user_id = auth.uid();
  if ik.id is null or ik.status <> 'actief' then
    if new.user_id is distinct from auth.uid() then
      raise exception 'niet toegestaan';
    end if;
  end if;
  if not coalesce(ik.is_admin, false) then
    if new.user_id is distinct from auth.uid() then
      raise exception 'je mag alleen je eigen gegevens wijzigen';
    end if;
    if new.functie <> old.functie or new.status <> old.status or new.is_admin <> old.is_admin
       or new.is_hoofdadmin <> old.is_hoofdadmin or new.email <> old.email
       or new.user_id is distinct from old.user_id then
      raise exception 'functie, status en rechten kunnen alleen door een admin gewijzigd worden';
    end if;
  else
    if old.is_hoofdadmin and not ik.is_hoofdadmin then
      raise exception 'de gegevens van de hoofdadmin kunnen alleen door de hoofdadmin zelf gewijzigd worden';
    end if;
    if new.is_hoofdadmin <> old.is_hoofdadmin then
      raise exception 'de hoofdadmin-vlag kan niet gewijzigd worden';
    end if;
    if new.user_id is distinct from old.user_id and new.user_id is not null then
      -- een admin mag een koppeling wel verwijderen (account weg), maar nooit zelf leggen of verleggen
      raise exception 'de koppeling met het account kan niet gewijzigd worden';
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists members_guard on members;
create trigger members_guard before update on members
  for each row execute function members_guard();

-- Eigen lidgegevens voor de app. Zolang het lid niet actief is, blijven de persoonlijke velden leeg:
-- een registratie die op naam gekoppeld is, mag die gegevens pas zien na goedkeuring.
create or replace function mijn_lid() returns members
language plpgsql stable security definer set search_path = public as $$
declare
  r members;
begin
  select * into r from members where user_id = auth.uid();
  if r.id is not null and r.status <> 'actief' then
    r.telefoon := null; r.geboortedatum := null; r.adres := null; r.nationaliteit := null; r.nr := null;
  end if;
  return r;
end $$;
revoke all on function mijn_lid() from public, anon;
grant execute on function mijn_lid() to authenticated;

-- Beperkte weergave voor supporters: alleen naam en functie.
create or replace view members_basis as
  select id, naam, functie, status, is_admin, is_hoofdadmin, voornaam, achternaam, speelt,
         (user_id is not null) as heeft_account
  from members;
revoke all on members_basis from anon;
grant select on members_basis to authenticated;

-- --------------------------------------------------------------- logboek

create table if not exists audit_log (
  id         bigserial primary key,
  tabel      text not null,
  rij_id     text not null,
  actie      text not null,
  oud        jsonb,
  nieuw      jsonb,
  door       uuid,          -- members.id
  door_user  uuid,          -- auth.users.id
  op         timestamptz not null default now()
);
create index if not exists audit_log_tabel_rij_idx on audit_log (tabel, rij_id, op desc);

create or replace function log_wijziging() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := coalesce(to_jsonb(new), to_jsonb(old));
  rij text := coalesce(j->>'id', concat_ws('|', j->>'match_key', j->>'lineup_id', j->>'member_id', j->>'positie'));
begin
  insert into audit_log (tabel, rij_id, actie, oud, nieuw, door, door_user)
  values (TG_TABLE_NAME, rij, TG_OP, to_jsonb(old), to_jsonb(new), my_member_id(), auth.uid());
  return coalesce(new, old);
end $$;
drop trigger if exists members_log on members;
create trigger members_log after insert or update or delete on members
  for each row execute function log_wijziging();

-- ---------------------------------------------------------- aanwezigheden

create table if not exists attendance (
  match_key  text not null references matches (match_key) on delete cascade,
  member_id  uuid not null references members (id) on delete cascade,
  status     text not null check (status in ('aanwezig', 'afwezig', 'onzeker')),
  gezet_door uuid references members (id),
  updated_at timestamptz not null default now(),
  primary key (match_key, member_id)
);
create or replace function attendance_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.gezet_door := my_member_id();
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists attendance_stamp on attendance;
create trigger attendance_stamp before insert or update on attendance
  for each row execute function attendance_stamp();
drop trigger if exists attendance_log on attendance;
create trigger attendance_log after insert or update or delete on attendance
  for each row execute function log_wijziging();

-- Lijst zoals ze 24 uur voor de aftrap was (alleen admins), afgeleid uit het logboek.
create or replace function aanwezigheden_24u_voor(p_match_key text)
returns table (member_id uuid, naam text, functie text, status text, gezet_op timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  grens timestamptz;
begin
  if not is_admin() then
    raise exception 'alleen admins';
  end if;
  select ((m.datum + coalesce(nullif(m.uur, '')::time, '15:00'::time)) at time zone 'Europe/Brussels') - interval '24 hours'
    into grens from matches m where m.match_key = p_match_key;
  if grens is null then
    raise exception 'wedstrijd zonder datum';
  end if;
  return query
    with laatste as (
      select distinct on (l.nieuw->>'member_id')
             (l.nieuw->>'member_id')::uuid as mid, l.nieuw->>'status' as st, l.op
      from audit_log l
      where l.tabel = 'attendance' and l.actie in ('INSERT', 'UPDATE')
        and l.nieuw->>'match_key' = p_match_key and l.op <= grens
      order by l.nieuw->>'member_id', l.op desc)
    select mm.id, mm.naam, mm.functie, la.st, la.op
    from laatste la join members mm on mm.id = la.mid
    order by la.st, mm.naam;
end $$;

-- ------------------------------------------------------------ opstelling

create table if not exists lineups (
  id           uuid primary key default gen_random_uuid(),
  match_key    text not null unique references matches (match_key) on delete cascade,
  formatie     text not null default '4-3-3' check (formatie in ('4-3-3', '4-4-2', '3-4-3')),
  gemaakt_door uuid references members (id),
  updated_at   timestamptz not null default now()
);
create table if not exists lineup_players (
  lineup_id  uuid not null references lineups (id) on delete cascade,
  member_id  uuid not null references members (id) on delete cascade,
  positie    text not null,   -- positiecode van de formatie (GK, RB, ...) of BANK1..BANK4
  primary key (lineup_id, positie),
  unique (lineup_id, member_id)
);
create or replace function lineups_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.gemaakt_door := coalesce(my_member_id(), new.gemaakt_door);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists lineups_stamp on lineups;
create trigger lineups_stamp before insert or update on lineups
  for each row execute function lineups_stamp();
create or replace function lineup_players_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from members where id = new.member_id and status = 'actief' and (speelt or is_admin or is_hoofdadmin)) then
    raise exception 'Alleen actieve spelers of testbeheerders kunnen opgesteld worden';
  end if;
  perform 1 from attendance a join lineups l on l.match_key = a.match_key
    where l.id = new.lineup_id and a.member_id = new.member_id and a.status = 'aanwezig'
    for share of a;
  if not found then
    raise exception 'Alleen spelers die voor deze match op aanwezig staan kunnen opgesteld worden. Vernieuw de aanwezigheden.';
  end if;
  return new;
end $$;
drop trigger if exists lineup_players_check on lineup_players;
create trigger lineup_players_check before insert or update on lineup_players
  for each row execute function lineup_players_check();

-- Eén transactie: een gewijzigde aanwezigheid mag de vorige opstelling niet wissen.
create or replace function bewaar_opstelling(p_match_key text, p_formatie text, p_keuze jsonb) returns void
language plpgsql security invoker set search_path = public as $$
declare
  v_lineup uuid;
begin
  if not is_actief() or not is_staf() then
    raise exception 'Alleen bevoegde staf mag een opstelling maken.';
  end if;
  if p_keuze is null or jsonb_typeof(p_keuze) <> 'object' then
    raise exception 'Ongeldige opstelling.';
  end if;
  insert into lineups (match_key, formatie) values (p_match_key, p_formatie)
    on conflict (match_key) do update set formatie = excluded.formatie
    returning id into v_lineup;
  delete from lineup_players where lineup_id = v_lineup;
  insert into lineup_players (lineup_id, positie, member_id)
    select v_lineup, key, value::uuid from jsonb_each_text(p_keuze)
    where value is not null and value <> '';
end $$;
revoke all on function bewaar_opstelling(text, text, jsonb) from public, anon;
grant execute on function bewaar_opstelling(text, text, jsonb) to authenticated;
drop trigger if exists lineups_log on lineups;
create trigger lineups_log after insert or update or delete on lineups
  for each row execute function log_wijziging();
drop trigger if exists lineup_players_log on lineup_players;
create trigger lineup_players_log after insert or update or delete on lineup_players
  for each row execute function log_wijziging();

-- ---------------------------------------------------------- statistieken

create table if not exists match_stats (
  match_key      text not null references matches (match_key) on delete cascade,
  member_id      uuid not null references members (id) on delete cascade,
  gespeeld       boolean not null default true,
  goals          integer not null default 0 check (goals >= 0),
  assists        integer not null default 0 check (assists >= 0),
  geel           integer not null default 0 check (geel between 0 and 2),
  rood           integer not null default 0 check (rood between 0 and 1),
  ingevoerd_door uuid references members (id),
  updated_at     timestamptz not null default now(),
  primary key (match_key, member_id)
);
create or replace function match_stats_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.ingevoerd_door := coalesce(my_member_id(), new.ingevoerd_door);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists match_stats_stamp on match_stats;
create trigger match_stats_stamp before insert or update on match_stats
  for each row execute function match_stats_stamp();
drop trigger if exists match_stats_log on match_stats;
create trigger match_stats_log after insert or update or delete on match_stats
  for each row execute function log_wijziging();

-- --------------------------------------------------------- adminfuncties

-- Wachtwoord van een lid instellen (niet van de hoofdadmin). Wordt gelogd.
create or replace function admin_set_password(p_member_id uuid, p_wachtwoord text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user uuid;
  v_hoofd boolean;
begin
  if not is_admin() then
    raise exception 'alleen admins';
  end if;
  select user_id, is_hoofdadmin into v_user, v_hoofd from members where id = p_member_id;
  if v_user is null then
    raise exception 'dit lid heeft geen account';
  end if;
  if v_hoofd then
    raise exception 'het wachtwoord van de hoofdadmin kan alleen door de hoofdadmin zelf gewijzigd worden';
  end if;
  if length(p_wachtwoord) < 8 then
    raise exception 'wachtwoord moet minstens 8 tekens hebben';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_wachtwoord, extensions.gen_salt('bf')), updated_at = now()
   where id = v_user;
  insert into audit_log (tabel, rij_id, actie, nieuw, door, door_user)
  values ('auth.users', v_user::text, 'WACHTWOORD_GEZET', jsonb_build_object('member_id', p_member_id), my_member_id(), auth.uid());
end $$;
revoke all on function admin_set_password(uuid, text) from public, anon;
grant execute on function admin_set_password(uuid, text) to authenticated;

-- Account loskoppelen: het inlogaccount verdwijnt, de gegevens van het lid blijven staan.
-- Registreert de persoon later opnieuw (zelfde e-mailadres of naam), dan wordt hij weer gekoppeld.
create or replace function admin_ontkoppel_account(p_member_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_hoofd boolean;
  v_naam text;
begin
  if not is_admin() then
    raise exception 'alleen admins';
  end if;
  select user_id, is_hoofdadmin, naam into v_user, v_hoofd, v_naam from members where id = p_member_id;
  if v_hoofd then
    raise exception 'het account van de hoofdadmin kan niet verwijderd worden';
  end if;
  if v_user is null then
    raise exception 'dit lid heeft geen account';
  end if;
  insert into audit_log (tabel, rij_id, actie, oud, door, door_user)
  values ('members', p_member_id::text, 'ACCOUNT_VERWIJDERD', jsonb_build_object('naam', v_naam, 'user_id', v_user), my_member_id(), auth.uid());
  -- het verwijderen zet members.user_id op null (on delete set null); die update mag niet
  -- tegen members_guard aanlopen, dus zetten we een vlag voor de duur van deze transactie
  perform set_config('steca.ontkoppelen', 'ja', true);
  delete from auth.users where id = v_user;  -- members.user_id wordt automatisch null
end $$;
revoke all on function admin_ontkoppel_account(uuid) from public, anon;
grant execute on function admin_ontkoppel_account(uuid) to authenticated;

-- Lid volledig verwijderen: gegevens én account (bv. een foute registratie). Niet voor de hoofdadmin. Wordt gelogd.
create or replace function admin_verwijder_lid(p_member_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_user uuid;
  v_hoofd boolean;
  v_naam text;
begin
  if not is_admin() then
    raise exception 'alleen admins';
  end if;
  select user_id, is_hoofdadmin, naam into v_user, v_hoofd, v_naam from members where id = p_member_id;
  if v_hoofd then
    raise exception 'de hoofdadmin kan niet verwijderd worden';
  end if;
  insert into audit_log (tabel, rij_id, actie, oud, door, door_user)
  values ('members', p_member_id::text, 'VERWIJDERD', jsonb_build_object('naam', v_naam, 'user_id', v_user), my_member_id(), auth.uid());
  delete from members where id = p_member_id;
  if v_user is not null then
    delete from auth.users where id = v_user;
  end if;
end $$;
revoke all on function admin_verwijder_lid(uuid) from public, anon;
grant execute on function admin_verwijder_lid(uuid) to authenticated;

-- ------------------------------------------------------- toegangsregels

alter table members enable row level security;
alter table attendance enable row level security;
alter table lineups enable row level security;
alter table lineup_players enable row level security;
alter table match_stats enable row level security;
alter table audit_log enable row level security;

-- leden
drop policy if exists "leden lezen" on members;
create policy "leden lezen" on members for select to authenticated
  using ((user_id = auth.uid() and status = 'actief') or is_admin() or (is_actief() and not is_supporter()));
drop policy if exists "leden toevoegen" on members;
create policy "leden toevoegen" on members for insert to authenticated with check (is_admin());
drop policy if exists "leden wijzigen" on members;
create policy "leden wijzigen" on members for update to authenticated
  using (user_id = auth.uid() or is_admin())
  with check (user_id = auth.uid() or is_admin());


-- aanwezigheden
drop policy if exists "aanwezigheid lezen" on attendance;
create policy "aanwezigheid lezen" on attendance for select to authenticated using (is_actief());
drop policy if exists "aanwezigheid zetten" on attendance;
create policy "aanwezigheid zetten" on attendance for insert to authenticated
  with check (is_staf() or (is_actief() and not is_supporter() and member_id = my_member_id()));
drop policy if exists "aanwezigheid wijzigen" on attendance;
create policy "aanwezigheid wijzigen" on attendance for update to authenticated
  using (is_staf() or (is_actief() and not is_supporter() and member_id = my_member_id()))
  with check (is_staf() or (is_actief() and not is_supporter() and member_id = my_member_id()));

-- opstellingen
drop policy if exists "opstelling lezen" on lineups;
create policy "opstelling lezen" on lineups for select to authenticated using (is_actief());
drop policy if exists "opstelling beheren" on lineups;
create policy "opstelling beheren" on lineups for all to authenticated using (is_staf()) with check (is_staf());
drop policy if exists "opstellingsspelers lezen" on lineup_players;
create policy "opstellingsspelers lezen" on lineup_players for select to authenticated using (is_actief());
drop policy if exists "opstellingsspelers beheren" on lineup_players;
create policy "opstellingsspelers beheren" on lineup_players for all to authenticated using (is_staf()) with check (is_staf());

-- statistieken
drop policy if exists "statistieken lezen" on match_stats;
create policy "statistieken lezen" on match_stats for select to authenticated using (is_actief());
drop policy if exists "statistieken beheren" on match_stats;
create policy "statistieken beheren" on match_stats for all to authenticated using (is_staf()) with check (is_staf());

-- logboek: admins lezen alles; staf alleen wedstrijdgebonden tabellen (ledengegevens staan er ook in)
drop policy if exists "logboek lezen" on audit_log;
create policy "logboek lezen" on audit_log for select to authenticated
  using (is_admin() or (is_staf() and tabel in ('match_stats', 'lineups', 'lineup_players', 'attendance')));

-- Synctabellen: alleen ingelogde leden lezen (de sync schrijft met de service-role key).
drop policy if exists "publiek lezen" on teams;
drop policy if exists "publiek lezen" on matches;
drop policy if exists "publiek lezen" on standings;
drop policy if exists "publiek lezen" on standings_state;
drop policy if exists "publiek lezen" on sync_status;
drop policy if exists "leden lezen" on teams;
create policy "leden lezen" on teams for select to authenticated using (true);
drop policy if exists "leden lezen" on matches;
create policy "leden lezen" on matches for select to authenticated using (true);
drop policy if exists "leden lezen" on standings;
create policy "leden lezen" on standings for select to authenticated using (true);
drop policy if exists "leden lezen" on standings_state;
create policy "leden lezen" on standings_state for select to authenticated using (true);
drop policy if exists "leden lezen" on sync_status;
create policy "leden lezen" on sync_status for select to authenticated using (true);

-- ------------------------------------------------------ sfeerbeelden
-- Privébestanden per wedstrijd; geen openbare bucket of overschrijven.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('match-sfeerbeelden', 'match-sfeerbeelden', false, 52428800,
  array['image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.is_match_mediamap(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select is_actief() and exists (
    select 1 from matches where (thuis_id = 152 or uit_id = 152)
      and encode(convert_to(match_key, 'UTF8'), 'hex') = split_part(p_name, '/', 1)
  ) and array_length(string_to_array(p_name, '/'), 1) = 2
$$;
revoke all on function public.is_match_mediamap(text) from public, anon;
grant execute on function public.is_match_mediamap(text) to authenticated;

drop policy if exists "sfeerbeelden lezen" on storage.objects;
create policy "sfeerbeelden lezen" on storage.objects for select to authenticated
  using (bucket_id = 'match-sfeerbeelden' and public.is_actief());
drop policy if exists "sfeerbeelden toevoegen" on storage.objects;
create policy "sfeerbeelden toevoegen" on storage.objects for insert to authenticated
  with check (bucket_id = 'match-sfeerbeelden' and public.is_match_mediamap(name)
    and split_part(split_part(name, '/', 2), '_', 1) = auth.uid()::text);
drop policy if exists "sfeerbeelden verwijderen" on storage.objects;
create policy "sfeerbeelden verwijderen" on storage.objects for delete to authenticated
  using (bucket_id = 'match-sfeerbeelden' and public.is_actief()
    and (owner_id = auth.uid()::text or public.is_admin()));

-- --------------------------------------------------------------- boetepot

-- Migratie 2026-09-09: boetepot.
-- Handmatig ingevoerde boetes per speler (kaarten komen uit match_stats en staan hier niet in).
-- Lezen: alle actieve leden. Invoeren, wijzigen en verwijderen: coach, spelercoach, verantwoordelijke of admin.
-- Elke wijziging komt in audit_log. Plakken in de Supabase SQL Editor en op Run klikken; veilig om te herhalen.

create table if not exists fines (
  id             uuid primary key default gen_random_uuid(),
  member_id      uuid not null references members (id) on delete cascade,
  match_key      text references matches (match_key) on delete set null,
  datum          date not null default current_date,
  soort          text not null,
  aantal         integer not null default 1 check (aantal > 0),
  bedrag_cent    integer not null default 0 check (bedrag_cent >= 0),
  bak_bier       integer not null default 0 check (bak_bier >= 0),
  opmerking      text,
  ingevoerd_door uuid references members (id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists fines_member_idx on fines (member_id, datum desc);

create or replace function fines_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    new.ingevoerd_door := coalesce(new.ingevoerd_door, my_member_id());
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists fines_stamp on fines;
create trigger fines_stamp before insert or update on fines
  for each row execute function fines_stamp();
drop trigger if exists fines_log on fines;
create trigger fines_log after insert or update or delete on fines
  for each row execute function log_wijziging();

alter table fines enable row level security;
drop policy if exists "boetes lezen" on fines;
create policy "boetes lezen" on fines for select to authenticated using (is_actief());
drop policy if exists "boetes beheren" on fines;
create policy "boetes beheren" on fines for all to authenticated using (is_staf()) with check (is_staf());

drop policy if exists "logboek lezen" on audit_log;
create policy "logboek lezen" on audit_log for select to authenticated
  using (is_admin() or (is_staf() and tabel in ('match_stats', 'lineups', 'lineup_players', 'attendance', 'fines')));

-- --------------------------------------------------------------- junior van de match

-- Migratie 2026-09-09: Junior van de match (stemming per match) en Junior d'or (seizoen).
-- Wie op een gespeelde match als aanwezig stond, kiest de beste drie spelers van die match:
-- 3, 2 en 1 punt. Je kunt niet op jezelf stemmen en alleen op spelers die aanwezig waren.
-- Eigen stem is alleen zichtbaar voor de stemmer (en admins); iedereen ziet de opgetelde punten.
-- Plakken in de Supabase SQL Editor en op Run klikken; veilig om te herhalen.

create table if not exists match_votes (
  match_key  text not null references matches (match_key) on delete cascade,
  voter_id   uuid not null references members (id) on delete cascade,
  eerste     uuid not null references members (id) on delete cascade,
  tweede     uuid not null references members (id) on delete cascade,
  derde      uuid not null references members (id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (match_key, voter_id),
  check (eerste <> tweede and eerste <> derde and tweede <> derde),
  check (voter_id <> eerste and voter_id <> tweede and voter_id <> derde)
);

-- Geldigheid van een stembrief: match gespeeld en hoogstens 7 dagen geleden, stemmer aanwezig,
-- alle drie de gekozen spelers aanwezig, niet op jezelf.
create or replace function stem_geldig(p_match_key text, p_eerste uuid, p_tweede uuid, p_derde uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_actief()
    and exists (select 1 from matches m where m.match_key = p_match_key and m.status = 'gespeeld'
                  and m.datum is not null and current_date <= m.datum + 7)
    and exists (select 1 from attendance a where a.match_key = p_match_key and a.member_id = my_member_id() and a.status = 'aanwezig')
    and (select count(*) from attendance a where a.match_key = p_match_key and a.status = 'aanwezig'
           and a.member_id in (p_eerste, p_tweede, p_derde)) = 3
    and my_member_id() not in (p_eerste, p_tweede, p_derde)
    and p_eerste <> p_tweede and p_eerste <> p_derde and p_tweede <> p_derde;
$$;
revoke all on function stem_geldig(text, uuid, uuid, uuid) from public, anon;
grant execute on function stem_geldig(text, uuid, uuid, uuid) to authenticated;

create or replace function match_votes_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists match_votes_stamp on match_votes;
create trigger match_votes_stamp before insert or update on match_votes
  for each row execute function match_votes_stamp();
drop trigger if exists match_votes_log on match_votes;
create trigger match_votes_log after insert or update or delete on match_votes
  for each row execute function log_wijziging();

alter table match_votes enable row level security;
drop policy if exists "eigen stem lezen" on match_votes;
create policy "eigen stem lezen" on match_votes for select to authenticated
  using (voter_id = my_member_id() or is_admin());
drop policy if exists "stem uitbrengen" on match_votes;
create policy "stem uitbrengen" on match_votes for insert to authenticated
  with check (voter_id = my_member_id() and stem_geldig(match_key, eerste, tweede, derde));
drop policy if exists "stem wijzigen" on match_votes;
create policy "stem wijzigen" on match_votes for update to authenticated
  using (voter_id = my_member_id())
  with check (voter_id = my_member_id() and stem_geldig(match_key, eerste, tweede, derde));
drop policy if exists "stem intrekken" on match_votes;
create policy "stem intrekken" on match_votes for delete to authenticated
  using (voter_id = my_member_id());

-- Opgetelde punten per match en speler, zonder te tonen wie op wie stemde.
-- 'stemmen' = aantal stembrieven waarop de speler voorkomt.
create or replace view match_vote_points as
  select s.match_key, s.member_id, sum(s.punten)::int as punten, count(*)::int as stemmen
  from (
    select match_key, eerste as member_id, 3 as punten from match_votes
    union all select match_key, tweede, 2 from match_votes
    union all select match_key, derde, 1 from match_votes
  ) s
  where is_actief()
  group by s.match_key, s.member_id;
revoke all on match_vote_points from anon;
grant select on match_vote_points to authenticated;

-- Aantal stemmers per match.
create or replace view match_vote_counts as
  select match_key, count(*)::int as stemmers
  from match_votes
  where is_actief()
  group by match_key;
revoke all on match_vote_counts from anon;
grant select on match_vote_counts to authenticated;


-- Alleen fictieve gegevens voor de testomgeving.
insert into teams (ploegid, seizoen, naam, reeks, fetched_at, bron) values
 (152, '2026-2027', 'Steca Juniors', 'DERDE AFDELING B', now(), 'test'),
 (9901, '2026-2027', 'FC Test United', 'DERDE AFDELING B', now(), 'test'),
 (9902, '2026-2027', 'FC Voorbeeld', 'DERDE AFDELING B', now(), 'test')
on conflict do nothing;
insert into matches (match_key, seizoen, reeks, datum, uur, thuis_id, uit_id, thuis, uit, status, fetched_at, bron) values
 ('test-volgende', '2026-2027', 'DERDE AFDELING B', current_date + 3, '15:00', 152, 9901, 'Steca Juniors', 'FC Test United', 'gepland', now(), 'test'),
 ('test-tweede', '2026-2027', 'DERDE AFDELING B', current_date + 10, '15:00', 9902, 152, 'FC Voorbeeld', 'Steca Juniors', 'gepland', now(), 'test')
on conflict do nothing;
insert into members (naam, voornaam, achternaam, email, functie, status, bron)
select 'Testspeler ' || n, 'Testspeler', n::text, 'testspeler' || n || '@example.invalid', 'speler', 'actief', 'admin'
from generate_series(1, 15) n
where not exists (select 1 from members where email = 'testspeler' || n || '@example.invalid');
insert into attendance (match_key, member_id, status)
select 'test-volgende', id, 'aanwezig' from members where email like 'testspeler%@example.invalid'
on conflict do nothing;


-- Openbare supporterstoegang: alleen onderstaande velden, nooit contactgegevens of clubadministratie.
create or replace function public.openbare_clubinfo() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'matches', coalesce((select jsonb_agg(to_jsonb(m) order by datum, uur) from (
      select match_key, seizoen, reeks, datum, uur, thuis_id, uit_id, thuis, uit,
             thuis_score, uit_score, status, terrein, null::text as opmerking
      from public.matches where thuis_id = 152 or uit_id = 152
    ) m), '[]'::jsonb),
    'klassement', coalesce((select jsonb_agg(to_jsonb(s) order by reeks, positie) from (
      select seizoen, reeks, ploegid, bron, positie, ploeg, gespeeld, gewonnen, gelijk, verloren,
             doelpunten_voor, doelpunten_tegen, saldo, punten, label, vergelijking_status
      from public.standings_current
    ) s), '[]'::jsonb),
    'ploegen', coalesce((select jsonb_agg(to_jsonb(t) order by naam) from (
      select ploegid, naam, reeks, terrein, kleuren from public.teams
    ) t), '[]'::jsonb)
  );
$$;
revoke all on function public.openbare_clubinfo() from public;
grant execute on function public.openbare_clubinfo() to anon, authenticated;

-- Bezoekers lezen uitsluitend via openbare_clubinfo, niet via de onderliggende tabellen/views.
revoke all on public.teams, public.matches, public.standings, public.standings_state,
 public.standings_current, public.sync_status, public.members, public.members_basis,
 public.attendance, public.lineups, public.lineup_players, public.match_stats,
 public.audit_log, public.fines, public.match_votes, public.match_vote_points, public.match_vote_counts from anon;

-- Bestaande supporteraccounts blijven bestaan. Nieuwe supporters hebben geen account nodig.
create or replace function public.geen_nieuwe_supporterregistratie() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.raw_user_meta_data->>'functie' = 'supporter' and coalesce(new.raw_user_meta_data->>'account_type','') <> 'supporter' then
    raise exception 'Supporters hebben geen account nodig. Kies Verder als supporter.';
  end if;
  return new;
end;
$$;
revoke all on function public.geen_nieuwe_supporterregistratie() from public, anon, authenticated;
drop trigger if exists geen_nieuwe_supporterregistratie on auth.users;
create trigger geen_nieuwe_supporterregistratie before insert on auth.users
 for each row execute function public.geen_nieuwe_supporterregistratie();


-- Openbare spelersnamen, wedstrijdcijfers en boetes. Contactgegevens en vrije opmerkingen blijven intern.
create or replace function public.openbare_spelerscijfers() returns jsonb
language sql stable security definer set search_path = public as $$
 select jsonb_build_object(
 'spelers', coalesce((select jsonb_agg(to_jsonb(p) order by naam) from (
 select id, naam from members where speelt or exists (select 1 from match_stats where member_id = members.id) or exists (select 1 from fines where member_id = members.id)
 ) p), '[]'::jsonb),
 'stats', coalesce((select jsonb_agg(to_jsonb(s)) from (
 select s.match_key, s.member_id, s.gespeeld, s.goals, s.assists, s.geel, s.rood from match_stats s
 join matches m on m.match_key = s.match_key where m.thuis_id = 152 or m.uit_id = 152
 ) s), '[]'::jsonb),
 'boetes', coalesce((select jsonb_agg(to_jsonb(f) order by datum desc) from (
 select id, member_id, match_key, datum, soort, aantal, bedrag_cent, bak_bier,
 null::text as opmerking, null::uuid as ingevoerd_door from fines
 ) f), '[]'::jsonb)
 );
$$;
revoke all on function public.openbare_spelerscijfers() from public;
grant execute on function public.openbare_spelerscijfers() to anon, authenticated;

-- Google Drive: alleen de backend kan de verbinding en eenmalige OAuth-pogingen lezen.
create table if not exists public.drive_connection (
  id integer primary key check (id = 1),
  email text not null,
  folder_id text not null,
  refresh_token_cipher text not null,
  connected_by uuid references auth.users(id) on delete set null,
  connected_at timestamptz not null default now()
);
create table if not exists public.drive_oauth_states (
  state_hash text primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  verifier text not null,
  expires_at timestamptz not null
);
alter table public.drive_connection enable row level security;
alter table public.drive_oauth_states enable row level security;
revoke all on public.drive_connection, public.drive_oauth_states from public, anon, authenticated;
grant all on public.drive_connection, public.drive_oauth_states to service_role;
-- Posities vastzetten voor het rad; voorkeuren worden met de opstelling opgeslagen.
alter table public.lineup_players add column if not exists vergrendeld boolean not null default false;
create or replace function public.bewaar_opstelling_met_slotjes(p_match_key text, p_formatie text, p_keuze jsonb, p_slotjes text[])
returns void language plpgsql security invoker set search_path = public as $$
begin
  if p_slotjes is null or cardinality(p_slotjes) > 15 or exists (
    select 1 from unnest(p_slotjes) p where p is null or nullif(p_keuze->>p, '') is null
  ) then
    raise exception 'Vergrendel alleen posities met een gekozen speler.';
  end if;
  perform bewaar_opstelling(p_match_key, p_formatie, p_keuze);
  update lineup_players set vergrendeld = true
    where lineup_id = (select id from lineups where match_key = p_match_key)
      and positie = any(p_slotjes);
end $$;
revoke all on function public.bewaar_opstelling_met_slotjes(text, text, jsonb, text[]) from public, anon;
grant execute on function public.bewaar_opstelling_met_slotjes(text, text, jsonb, text[]) to authenticated;

-- Supporters mogen de opgeslagen veld- en bankindeling bekijken, zonder bewerkrechten.
create or replace function public.openbare_opstellingen() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'match_key', l.match_key, 'formatie', l.formatie,
    'spelers', coalesce((select jsonb_agg(jsonb_build_object('positie', p.positie, 'naam', m.naam, 'member_id', m.id) order by p.positie)
      from public.lineup_players p join public.members m on m.id=p.member_id
      where p.lineup_id=l.id), '[]'::jsonb)
  ) order by l.match_key), '[]'::jsonb)
  from public.lineups l join public.matches w on w.match_key=l.match_key
  where w.thuis_id=152 or w.uit_id=152;
$$;
revoke all on function public.openbare_opstellingen() from public;
grant execute on function public.openbare_opstellingen() to anon, authenticated;

-- Automatisch opslaan controleert de laatst gelezen versie binnen dezelfde transactie.
create or replace function public.bewaar_opstelling_auto(p_match_key text, p_formatie text, p_keuze jsonb, p_slotjes text[], p_verwacht timestamptz)
returns jsonb language plpgsql security invoker set search_path = public as $$
declare v_huidig timestamptz; v_resultaat jsonb;
begin
  if not is_actief() or not is_staf() then raise exception 'Alleen bevoegde staf mag een opstelling maken.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_match_key, 0));
  select updated_at into v_huidig from lineups where match_key=p_match_key for update;
  if v_huidig is distinct from p_verwacht then
    raise exception 'Deze opstelling is ondertussen gewijzigd. Herlaad de nieuwste opstelling voordat je verder bewerkt.';
  end if;
  perform bewaar_opstelling_met_slotjes(p_match_key, p_formatie, p_keuze, p_slotjes);
  select to_jsonb(l) into v_resultaat from lineups l where match_key=p_match_key;
  return v_resultaat;
end $$;
revoke all on function public.bewaar_opstelling_auto(text, text, jsonb, text[], timestamptz) from public, anon;
grant execute on function public.bewaar_opstelling_auto(text, text, jsonb, text[], timestamptz) to authenticated;


-- Matchverslag en pushmeldingen. Deze proef blijft uitsluitend in de testdatabase.
create table if not exists public.match_reports (
 match_key text primary key references public.matches(match_key) on delete cascade,
 thuis_score integer not null check(thuis_score between 0 and 99),
 uit_score integer not null check(uit_score between 0 and 99),
 momenten jsonb not null default '[]' check(jsonb_typeof(momenten)='array'),
 score_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 ingevoerd_door uuid references public.members(id)
);
alter table public.match_reports enable row level security;
revoke all on public.match_reports from anon, authenticated;
grant select on public.match_reports to authenticated;
grant all on public.match_reports to service_role;
drop policy if exists "actieve leden lezen verslagen" on public.match_reports;
create policy "actieve leden lezen verslagen" on public.match_reports for select to authenticated using (is_actief());

create or replace function public.bewaar_matchverslag(p_match_key text, p_thuis integer, p_uit integer, p_momenten jsonb, p_versie timestamptz)
returns void language plpgsql security definer set search_path=public as $$
declare v_versie timestamptz; m jsonb;
begin
 if not is_actief() or not is_staf() then raise exception 'Alleen bevoegde staf mag het matchverslag invullen.'; end if;
 if not exists(select 1 from matches where match_key=p_match_key and (thuis_id=152 or uit_id=152)) then raise exception 'Geen eigen wedstrijd.'; end if;
 if p_momenten is null or jsonb_typeof(p_momenten)<>'array' or jsonb_array_length(p_momenten)>150 then raise exception 'Ongeldige tijdlijn.'; end if;
 for m in select value from jsonb_array_elements(p_momenten) loop
  if coalesce(m->>'soort','') not in ('goal','geel','rood') or coalesce(m->>'kant','') not in ('thuis','uit')
    or length(coalesce(m->>'speler',''))>100 or length(coalesce(m->>'assist',''))>100
    or (m->>'minuut' is not null and ((m->>'minuut') !~ '^[0-9]{1,3}$' or (m->>'minuut')::integer>130)) then raise exception 'Ongeldig wedstrijdmoment.'; end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('verslag:'||p_match_key,0));
 select updated_at into v_versie from match_reports where match_key=p_match_key for update;
 if v_versie is distinct from p_versie then raise exception 'Iemand heeft dit verslag aangepast. Herlaad het verslag voordat je verdergaat.'; end if;
 insert into match_reports(match_key,thuis_score,uit_score,momenten,ingevoerd_door)
 values(p_match_key,p_thuis,p_uit,p_momenten,my_member_id())
 on conflict(match_key) do update set thuis_score=excluded.thuis_score,uit_score=excluded.uit_score,momenten=excluded.momenten,ingevoerd_door=excluded.ingevoerd_door,updated_at=clock_timestamp();
end $$;
revoke all on function public.bewaar_matchverslag(text,integer,integer,jsonb,timestamptz) from public,anon;
grant execute on function public.bewaar_matchverslag(text,integer,integer,jsonb,timestamptz) to authenticated;

create or replace function public.match_aftrap(p_datum date,p_uur text) returns timestamptz
language sql stable set search_path=public as $$
 select case when p_datum is not null and p_uur ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$' then (p_datum + p_uur::time) at time zone 'Europe/Brussels' else null end;
$$;
create or replace function stem_geldig(p_match_key text,p_eerste uuid,p_tweede uuid,p_derde uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select is_actief()
 and exists(select 1 from matches m where m.match_key=p_match_key and (m.status='gespeeld' or exists(select 1 from match_reports r where r.match_key=m.match_key))
   and match_aftrap(m.datum,m.uur)+interval '80 minutes'<=now() and (now() at time zone 'Europe/Brussels')::date<=m.datum+7)
 and exists(select 1 from attendance where match_key=p_match_key and member_id=my_member_id() and status='aanwezig')
 and (select count(*) from attendance where match_key=p_match_key and status='aanwezig' and member_id in(p_eerste,p_tweede,p_derde))=3
 and my_member_id() not in(p_eerste,p_tweede,p_derde) and p_eerste<>p_tweede and p_eerste<>p_derde and p_tweede<>p_derde;
$$;
revoke all on function stem_geldig(text,uuid,uuid,uuid) from public,anon;
grant execute on function stem_geldig(text,uuid,uuid,uuid) to authenticated;

create table if not exists public.push_config (
 id integer primary key check(id=1), enabled boolean not null default false,
 allowed_member uuid references public.members(id),
 vapid_public text, vapid_private text,
 cron_secret text not null default encode(gen_random_bytes(32),'hex')
);
insert into public.push_config(id) values(1) on conflict do nothing;
create table if not exists public.push_subscriptions (
 endpoint text primary key, member_id uuid not null references public.members(id) on delete cascade,
 subscription jsonb not null, created_at timestamptz not null default now()
);
create table if not exists public.push_jobs (
 id uuid primary key default gen_random_uuid(), match_key text not null references public.matches(match_key) on delete cascade,
 member_id uuid not null references public.members(id) on delete cascade,
 soort text not null check(soort in('aanwezig72','aanwezig48','stemmen','stemherinnering','wasmand')),
 status text not null default 'pending' check(status in('pending','sending','sent','skipped')),
 sent_at timestamptz, lease_until timestamptz, attempts integer not null default 0,
 next_attempt timestamptz not null default now(), fout text, created_at timestamptz not null default now(),
 unique(match_key,member_id,soort)
);
alter table public.push_config enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.push_jobs enable row level security;
revoke all on public.push_config,public.push_subscriptions,public.push_jobs from public,anon,authenticated;
grant all on public.push_config,public.push_subscriptions,public.push_jobs to service_role;

-- Alleen service_role krijgt planninggegevens; geen contactgegevens of abonnementen in de client.
create or replace function public.push_planning() returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('match_key',m.match_key,'tegenstander',case when m.thuis_id=152 then m.uit else m.thuis end,
 'aftrap',match_aftrap(m.datum,m.uur),'score_at',r.score_at,'deadline',((m.datum+8)::timestamp at time zone 'Europe/Brussels'),
 'thuis_score',r.thuis_score,'uit_score',r.uit_score,'steca_thuis',m.thuis_id=152,
 'antwoord',a.member_id is not null,'aanwezig',coalesce(a.status='aanwezig',false),'gestemd',v.voter_id is not null,
 'eerste_verzonden',j.sent_at,'member_id',c.allowed_member,'wasmand',w.member_id is not null)), '[]'::jsonb)
 from push_config c join members lid on lid.id=c.allowed_member and lid.status='actief' and lid.user_id is not null
 cross join matches m left join match_reports r on r.match_key=m.match_key
 left join attendance a on a.match_key=m.match_key and a.member_id=lid.id
 left join match_votes v on v.match_key=m.match_key and v.voter_id=lid.id
 left join push_jobs j on j.match_key=m.match_key and j.member_id=lid.id and j.soort='stemmen' and j.status='sent'
 left join laundry_turns w on w.match_key=m.match_key and w.member_id=lid.id
 where c.enabled and (m.thuis_id=152 or m.uit_id=152) and m.datum between (now() at time zone 'Europe/Brussels')::date-7 and (now() at time zone 'Europe/Brussels')::date+4;
$$;
revoke all on function public.push_planning() from public,anon,authenticated;
grant execute on function public.push_planning() to service_role;

-- Eén verzender per job, inclusief herstart na een afgebroken Edge Function.
create or replace function public.claim_push_job(p_id uuid) returns boolean
language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 update push_jobs j set status='sending',lease_until=now()+interval '2 minutes',attempts=attempts+1
 where j.id=p_id and ((j.status='pending' and j.next_attempt<=now()) or (j.status='sending' and j.lease_until<now()))
 and exists(select 1 from push_config c join members m on m.id=c.allowed_member where c.enabled and c.allowed_member=j.member_id and m.status='actief' and m.user_id is not null)
 returning j.id into v_id;
 return v_id is not null;
end $$;
revoke all on function public.claim_push_job(uuid) from public,anon,authenticated;
grant execute on function public.claim_push_job(uuid) to service_role;

-- Geheime planneraanroep blijft in de database. De Edge Function weigert productie expliciet.
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;
select cron.schedule('steca-test-push','* * * * *',$cron$
 select net.http_post(
  url := 'https://fhgghcksvnyxfwkielzx.supabase.co/functions/v1/match-push',
  headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||cron_secret),
  body := '{"action":"run"}'::jsonb, timeout_milliseconds := 55000
 ) from public.push_config where id=1 and enabled and vapid_public is not null;
$cron$);

-- Een herkenbaar voorbeeld voor het matchverslag, zonder stemmeldingen voor echte leden.
insert into matches(match_key,seizoen,reeks,datum,uur,thuis_id,uit_id,thuis,uit,thuis_score,uit_score,status,bron,fetched_at)
values('test-matchverslag-voorbeeld','2026-2027','TESTMATCH',current_date-1,'15:00',152,9901,'Steca Juniors','FC Test United',2,1,'gespeeld','test',now()) on conflict do nothing;
insert into match_reports(match_key,thuis_score,uit_score,momenten)
values('test-matchverslag-voorbeeld',2,1,'[{"minuut":18,"soort":"goal","kant":"thuis","speler":"Testspeler 1","assist":"Testspeler 2"},{"minuut":36,"soort":"goal","kant":"uit","speler":"Speler FC Test United","assist":""},{"minuut":67,"soort":"goal","kant":"thuis","speler":"Testspeler 3","assist":"Testspeler 1"},{"minuut":74,"soort":"geel","kant":"uit","speler":"Speler FC Test United","assist":""}]') on conflict do nothing;

-- Handmatig een net gespeelde testmatch invullen en daarna opruimen.
create or replace function public.controleer_testmatch(p_match_key text) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not is_actief() or not is_admin() or not exists(select 1 from push_config where allowed_member=my_member_id()) then raise exception 'Alleen de aangewezen testbeheerder kan testmatches beheren.'; end if;
 if not exists(select 1 from matches where match_key=p_match_key and (bron in('test-invoer','push-test') or match_key='test-matchverslag-voorbeeld')) then raise exception 'Dit is geen verwijderbare testmatch.'; end if;
end $$;
create or replace function public.maak_testmatch() returns text
language plpgsql security definer set search_path=public as $$
declare k text:='test-invoer-'||gen_random_uuid(); aftrap timestamp:=(clock_timestamp()-interval '81 minutes') at time zone 'Europe/Brussels';
begin
 if not is_actief() or not is_admin() or not exists(select 1 from push_config where allowed_member=my_member_id()) then raise exception 'Alleen de aangewezen testbeheerder kan testmatches beheren.'; end if;
 insert into matches(match_key,seizoen,reeks,datum,uur,thuis_id,uit_id,thuis,uit,status,bron,fetched_at)
 values(k,'2026-2027','TESTMATCH',aftrap::date,to_char(aftrap,'HH24:MI'),152,9901,'Steca Juniors','FC Test United','gepland','test-invoer',now());
 insert into attendance(match_key,member_id,status) select k,id,'aanwezig' from members where id=my_member_id() or email like 'testspeler%@example.invalid';
 return k;
end $$;
create or replace function public.verwijder_testmatch(p_match_key text) returns void
language plpgsql security definer set search_path=public as $$
begin
 perform controleer_testmatch(p_match_key);
 if exists(select 1 from storage.objects where bucket_id='match-sfeerbeelden' and split_part(name,'/',1)=encode(convert_to(p_match_key,'UTF8'),'hex')) then raise exception 'Er staan nog sfeerbeelden bij deze testmatch. Probeer het verwijderen opnieuw.'; end if;
 delete from fines where match_key=p_match_key;
 delete from matches where match_key=p_match_key;
end $$;
revoke all on function public.controleer_testmatch(text),public.maak_testmatch(),public.verwijder_testmatch(text) from public,anon;
grant execute on function public.controleer_testmatch(text),public.maak_testmatch(),public.verwijder_testmatch(text) to authenticated;

-- Alleen de wachttijd van een bestaande testmatch simuleren; nooit een nieuwe uitslag maken.
create or replace function public.simuleer_testherinnering(p_match_key text) returns void
language plpgsql security definer set search_path=public as $$
declare lid uuid:=my_member_id();
begin
 perform controleer_testmatch(p_match_key);
 perform pg_advisory_xact_lock(hashtextextended('testherinnering:'||p_match_key,0));
 if not exists(select 1 from match_reports where match_key=p_match_key) then raise exception 'Vul eerst de uitslag van deze testmatch in.'; end if;
 if not exists(select 1 from matches where match_key=p_match_key and match_aftrap(datum,uur)<=now()-interval '80 minutes' and datum>=(now() at time zone 'Europe/Brussels')::date-7) then raise exception 'Deze testmatch valt buiten de stemperiode.'; end if;
 if not exists(select 1 from attendance where match_key=p_match_key and member_id=lid and status='aanwezig') then raise exception 'Je moet aanwezig staan bij deze testmatch.'; end if;
 if exists(select 1 from match_votes where match_key=p_match_key and voter_id=lid) then raise exception 'Je hebt al gestemd voor deze testmatch. Trek je teststem eerst in.'; end if;
 if not exists(select 1 from push_jobs where match_key=p_match_key and member_id=lid and soort='stemmen' and status='sent' and sent_at is not null) then raise exception 'Laat eerst de eerste stemmelding voor deze testmatch versturen.'; end if;
 if exists(select 1 from push_jobs where match_key=p_match_key and member_id=lid and status='sending' and lease_until>now()) then raise exception 'Deze melding wordt momenteel verstuurd. Wacht even.'; end if;
 update push_jobs set sent_at=least(sent_at,now()-interval '3 hours 1 minute'),fout='Test: drie uur wachttijd gesimuleerd voor dezelfde wedstrijd.' where match_key=p_match_key and member_id=lid and soort='stemmen';
 insert into push_jobs(match_key,member_id,soort) values(p_match_key,lid,'stemherinnering')
 on conflict(match_key,member_id,soort) do update set status='pending',sent_at=null,lease_until=null,attempts=0,next_attempt=now(),fout=null;
end $$;
revoke all on function public.simuleer_testherinnering(text) from public,anon;
grant execute on function public.simuleer_testherinnering(text) to authenticated;


-- De Kantine: persoonlijke ploegen zijn strikt gescheiden van officiële lineups.
create table if not exists public.dream_xi (
 user_id uuid primary key references auth.users(id) on delete cascade,
 formatie text not null check (formatie in ('4-3-3','4-4-2','3-4-3')),
 keuze jsonb not null default '{}', slotjes text[] not null default '{}',
 updated_at timestamptz not null default now()
);
alter table public.dream_xi enable row level security;
revoke all on public.dream_xi from anon, authenticated;
grant select on public.dream_xi to authenticated;
grant all on public.dream_xi to service_role;
drop policy if exists dream_prive on public.dream_xi;
create policy dream_prive on public.dream_xi for select to authenticated using ((is_actief() or exists(select 1 from supporter_profiles where user_id=auth.uid() and actief)) and user_id=auth.uid());

create or replace function public.kantine_spelers() returns table(id uuid,naam text)
language sql stable security definer set search_path=public as $$
 select id,naam from members where status='actief' and speelt order by naam;
$$;
revoke all on function public.kantine_spelers() from public;
grant execute on function public.kantine_spelers() to anon,authenticated;

create or replace function public.bewaar_dream_xi(p_formatie text,p_keuze jsonb,p_slotjes text[],p_versie timestamptz)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare pos text[]; v timestamptz; nieuw timestamptz; k record;
begin
 if not (coalesce(is_actief(),false) or exists(select 1 from supporter_profiles where user_id=auth.uid() and actief)) then raise exception 'Log in met een actief clubaccount.'; end if;
 pos:=case p_formatie when '4-3-3' then array['GK','LB','CB1','CB2','RB','CM1','CM2','CM3','LW','ST','RW']
 when '4-4-2' then array['GK','LB','CB1','CB2','RB','LM','CM1','CM2','RM','ST1','ST2']
 when '3-4-3' then array['GK','CB1','CB2','CB3','LM','CM1','CM2','RM','LW','ST','RW'] end;
 if pos is null or p_keuze is null or jsonb_typeof(p_keuze)<>'object' then raise exception 'Ongeldige persoonlijke opstelling.'; end if;
 pos:=pos||array['BANK1','BANK2','BANK3','BANK4'];
 for k in select * from jsonb_each_text(p_keuze) loop
  if not(k.key=any(pos)) or (k.value is not null and not exists(select 1 from members where id::text=k.value and status='actief' and speelt)) then raise exception 'Ongeldige speler of positie.'; end if;
 end loop;
 if (select count(*)<>count(distinct value) from jsonb_each_text(p_keuze) where value is not null) then raise exception 'Een speler mag maar eenmaal voorkomen.'; end if;
 if p_slotjes is null or not(p_slotjes<@pos) or exists(select 1 from unnest(p_slotjes) p where p_keuze->>p is null) then raise exception 'Ongeldig slotje.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('dream:'||auth.uid()::text,0));
 select updated_at into v from dream_xi where user_id=auth.uid();
 if v is distinct from p_versie then raise exception 'Je Dream XI is elders gewijzigd. Herlaad eerst.'; end if;
 nieuw:=clock_timestamp();
 insert into dream_xi values(auth.uid(),p_formatie,p_keuze,p_slotjes,nieuw)
 on conflict(user_id) do update set formatie=excluded.formatie,keuze=excluded.keuze,slotjes=excluded.slotjes,updated_at=excluded.updated_at;
 return nieuw;
end $$;
revoke all on function public.bewaar_dream_xi(text,jsonb,text[],timestamptz) from public,anon;
grant execute on function public.bewaar_dream_xi(text,jsonb,text[],timestamptz) to authenticated;

create table if not exists public.pronostieken (
 match_key text references public.matches(match_key) on delete cascade,
 user_id uuid references auth.users(id) on delete cascade,
 thuis integer not null check(thuis between 0 and 99), uit integer not null check(uit between 0 and 99),
 updated_at timestamptz not null default now(), primary key(match_key,user_id)
);
alter table public.pronostieken enable row level security;
revoke all on public.pronostieken from anon,authenticated;
grant select on public.pronostieken to authenticated;
grant all on public.pronostieken to service_role;
drop policy if exists eigen_pronostiek on public.pronostieken;
create policy eigen_pronostiek on public.pronostieken for select to authenticated using((is_actief() or exists(select 1 from supporter_profiles where user_id=auth.uid() and actief)) and user_id=auth.uid());

create or replace function public.bewaar_pronostiek(p_match text,p_thuis integer,p_uit integer)
returns void language plpgsql security definer set search_path=public as $$
declare m matches%rowtype;
begin
 if not (coalesce(is_actief(),false) or exists(select 1 from supporter_profiles where user_id=auth.uid() and actief)) then raise exception 'Log in met een actief clubaccount.'; end if;
 select * into m from matches where match_key=p_match for share;
 if m.match_key is null or not coalesce(m.thuis_id=152 or m.uit_id=152,false) then raise exception 'Alleen matchen van Steca Juniors.'; end if;
 if match_aftrap(m.datum,m.uur) is null or match_aftrap(m.datum,m.uur)<=clock_timestamp() or m.status<>'gepland'
 or m.thuis_score is not null or m.uit_score is not null or exists(select 1 from match_reports where match_key=p_match) then raise exception 'Pronostieken zijn gesloten voor deze match.'; end if;
 if p_thuis is null or p_uit is null or p_thuis not between 0 and 99 or p_uit not between 0 and 99 then raise exception 'Vul twee volledige scores van 0 tot 99 in.'; end if;
 insert into pronostieken values(p_match,auth.uid(),p_thuis,p_uit,clock_timestamp())
 on conflict(match_key,user_id) do update set thuis=excluded.thuis,uit=excluded.uit,updated_at=excluded.updated_at;
end $$;
revoke all on function public.bewaar_pronostiek(text,integer,integer) from public,anon;
grant execute on function public.bewaar_pronostiek(text,integer,integer) to authenticated;

create or replace function public.pronostiek_punten(p_thuis integer,p_uit integer,r_thuis integer,r_uit integer)
returns integer language sql immutable as $$
 select case when r_thuis is null or r_uit is null or p_thuis is null or p_uit is null then 0
 when p_thuis=r_thuis and p_uit=r_uit then 10
 when p_thuis-p_uit=r_thuis-r_uit then 5
 when sign(p_thuis-p_uit)=sign(r_thuis-r_uit) then 3 else 0 end;
$$;

-- Alleen totalen en namen zijn openbaar; persoonlijke voorspellingen blijven privé.
-- Herberekent bij correcties. Een tijdens de match ingevulde score telt pas vanaf aftrap +80 min.
create or replace function public.kantine_klassement(p_seizoen text)
returns table(user_id uuid,naam text,punten bigint,exact bigint,verschil bigint,winnaar bigint,gespeeld bigint)
language sql stable security definer set search_path=public as $$
 with scores as (
 select p.user_id,pronostiek_punten(p.thuis,p.uit,coalesce(r.thuis_score,m.thuis_score),coalesce(r.uit_score,m.uit_score)) pt
 from pronostieken p join matches m using(match_key) left join match_reports r using(match_key)
 where m.seizoen=p_seizoen and (m.thuis_id=152 or m.uit_id=152)
 and match_aftrap(m.datum,m.uur)+interval '80 minutes'<=now()
 and (r.match_key is not null or m.status='gespeeld')
 and coalesce(r.thuis_score,m.thuis_score) is not null and coalesce(r.uit_score,m.uit_score) is not null
 ), deelnemers as (
 select coalesce(m.user_id,m.id) as user_id,m.naam from members m where m.status='actief' and m.functie<>'supporter'
 union all select sp.user_id,sp.naam from supporter_profiles sp where sp.actief
 )
 select d.user_id,d.naam,coalesce(sum(s.pt),0)::bigint,count(*) filter(where pt=10),count(*) filter(where pt=5),count(*) filter(where pt=3),count(s.pt)
 from deelnemers d left join scores s on s.user_id=d.user_id
 group by d.user_id,d.naam order by 3 desc,d.naam;
$$;
revoke all on function public.kantine_klassement(text) from public;
grant execute on function public.kantine_klassement(text) to anon,authenticated;

-- --------------------------------------------------------------- wasmand
-- Per match één speler die de wasmand mee naar huis neemt. Lezen: alle actieve leden.
-- Aanduiden en wijzigen: coach, spelercoach, verantwoordelijke of admin. Elke wijziging komt in audit_log.

create table if not exists laundry_turns (
  match_key      text primary key references matches (match_key) on delete cascade,
  member_id      uuid not null references members (id) on delete cascade,
  opmerking      text,
  ingevoerd_door uuid references members (id),
  updated_at     timestamptz not null default now()
);
create index if not exists laundry_turns_member_idx on laundry_turns (member_id);

create or replace function laundry_turns_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.ingevoerd_door := coalesce(my_member_id(), new.ingevoerd_door);
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists laundry_turns_stamp on laundry_turns;
create trigger laundry_turns_stamp before insert or update on laundry_turns
  for each row execute function laundry_turns_stamp();
drop trigger if exists laundry_turns_log on laundry_turns;
create trigger laundry_turns_log after insert or update or delete on laundry_turns
  for each row execute function log_wijziging();

alter table laundry_turns enable row level security;
drop policy if exists "wasmand lezen" on laundry_turns;
create policy "wasmand lezen" on laundry_turns for select to authenticated using (is_actief());
drop policy if exists "wasmand beheren" on laundry_turns;
create policy "wasmand beheren" on laundry_turns for all to authenticated using (is_staf()) with check (is_staf());

drop policy if exists "logboek lezen" on audit_log;
create policy "logboek lezen" on audit_log for select to authenticated
  using (is_admin() or (is_staf() and tabel in ('match_stats', 'lineups', 'lineup_players', 'attendance', 'fines', 'laundry_turns')));

-- Accounttype wijzigen zonder wedstrijdhistoriek of persoonlijke pronostieken te wissen.
alter table public.supporter_profiles add column if not exists member_id uuid unique references public.members(id) on delete set null;
create or replace function public.admin_supporters() returns table(id uuid,naam text,actief boolean,heeft_account boolean)
language plpgsql stable security definer set search_path=public as $$
begin
 if not is_admin() then raise exception 'Alleen een beheerder mag supporters beheren.'; end if;
 return query select s.user_id,s.naam,s.actief,true from supporter_profiles s
 union all select m.id,m.naam,m.status='actief',m.user_id is not null from members m
 where m.functie='supporter' and not exists(select 1 from supporter_profiles s where s.member_id=m.id or s.user_id=m.user_id)
 order by 2;
end $$;
revoke all on function public.admin_supporters() from public,anon;
grant execute on function public.admin_supporters() to authenticated;

create or replace function public.admin_accountfunctie(p_id uuid,p_functie text) returns uuid
language plpgsql security definer set search_path=public as $$
declare s supporter_profiles; m members; u auth.users; doel uuid; vorige text; actor uuid; instelling text;
begin
 if not is_admin() then raise exception 'Alleen een beheerder mag functies wijzigen.'; end if;
 if p_functie is null or p_functie not in ('speler','spelercoach','coach','verantwoordelijke','supporter') then raise exception 'Ongeldige functie.'; end if;
 actor:=my_member_id();
 perform pg_advisory_xact_lock(hashtextextended('steca-accountfunctie',0));
 select * into s from supporter_profiles where user_id=p_id for update;
 if s.user_id is not null then
   if p_functie='supporter' then return s.user_id; end if;
   select * into u from auth.users where id=s.user_id;
   if u.id is null then raise exception 'Account niet gevonden.'; end if;
   if exists(select 1 from members where user_id=u.id) then raise exception 'Dit account is al aan een clublid gekoppeld.'; end if;
   if s.member_id is not null then
     select * into m from members where id=s.member_id for update;
     if m.user_id is not null or m.is_hoofdadmin then raise exception 'Historisch profiel is al gekoppeld.'; end if;
   end if;
   instelling:=current_setting('steca.ontkoppelen',true);
   perform set_config('steca.ontkoppelen','ja',true);
   if m.id is not null then
     update members set user_id=u.id,functie=p_functie,status='actief',is_admin=false,email=u.email where id=m.id;
     doel:=m.id;
   else
     insert into members(user_id,naam,voornaam,achternaam,email,functie,status,bron)
     values(u.id,s.naam,coalesce(nullif(u.raw_user_meta_data->>'voornaam',''),split_part(s.naam,' ',1)),
       coalesce(nullif(u.raw_user_meta_data->>'achternaam',''),nullif(trim(substr(s.naam,length(split_part(s.naam,' ',1))+1)),'')),u.email,p_functie,'actief','admin') returning id into doel;
   end if;
   perform set_config('steca.ontkoppelen',coalesce(instelling,''),true);
   delete from supporter_profiles where user_id=u.id;
   vorige:='supporter';
 else
   select * into m from members where id=p_id for update;
   if m.id is null then raise exception 'Account of lid niet gevonden.'; end if;
   if m.is_hoofdadmin and p_functie='supporter' then raise exception 'De hoofdadmin kan geen supporter worden.'; end if;
   if m.is_hoofdadmin and m.id<>actor then raise exception 'Alleen de hoofdadmin mag zijn eigen functie wijzigen.'; end if;
   vorige:=m.functie;doel:=m.id;
   if p_functie='supporter' then
     if m.user_id is not null then
       insert into supporter_profiles(user_id,naam,actief,member_id) values(m.user_id,m.naam,m.status<>'inactief',m.id);
       doel:=m.user_id;
     end if;
     update members set user_id=null,functie='supporter',status='inactief',is_admin=false where id=m.id;
     delete from push_subscriptions where member_id=m.id;
     update push_jobs set status='skipped',fout='Account omgezet naar supporter.',lease_until=null where member_id=m.id and status in ('pending','sending');
   else
     update members set functie=p_functie,status=case when functie='supporter' then 'actief' else status end where id=m.id;
   end if;
 end if;
 insert into audit_log(tabel,rij_id,actie,oud,nieuw,door,door_user) values('accountfunctie',doel::text,'UPDATE',jsonb_build_object('functie',vorige),jsonb_build_object('functie',p_functie),actor,auth.uid());
 return doel;
end $$;
revoke all on function public.admin_accountfunctie(uuid,text) from public,anon;
grant execute on function public.admin_accountfunctie(uuid,text) to authenticated;

-- Badges: uitsluitend handmatige testtoewijzingen in de aparte testomgeving.
create table if not exists public.test_badge_catalogus (
 id text primary key, soort text not null check(soort in ('seizoen','alltime','verzameling')),
 herhaalbaar boolean not null default false
);
insert into public.test_badge_catalogus(id,soort,herhaalbaar) values
('gouden_stier','seizoen',false),
('het_kanon','alltime',false),
('assistenkoning','seizoen',false),
('maestro','alltime',false),
('de_muur','seizoen',false),
('betonblok','alltime',false),
('beenhouwer','seizoen',false),
('rosse_furie','seizoen',false),
('fundering','seizoen',false),
('vaste_waarde','seizoen',false),
('clubmeubilair','alltime',false),
('star_boy','seizoen',false),
('goat','alltime',false),
('kuisvrouw','seizoen',false),
('junior_dor','seizoen',false),
('eentje_is_geentje','verzameling',false),
('dubbele_cijfers','verzameling',false),
('goalgetter','verzameling',false),
('sluipschutter','verzameling',false),
('67','verzameling',false),
('triple_digits','verzameling',false),
('wingman','verzameling',false),
('facteur','verzameling',false),
('de_architect','verzameling',false),
('kdb_der_juniors','verzameling',false),
('muur_van_dendermonde','verzameling',false),
('veilige_handen','verzameling',false),
('opgewarmd_door_georgie','verzameling',false),
('golden_glove','verzameling',false),
('official_junior','verzameling',false),
('toogplekker','verzameling',false),
('sterkhouder','verzameling',false),
('georgies_favoriet','verzameling',false),
('steca_legend','verzameling',false),
('hattrick','verzameling',true),
('vijf_op_een_rij','verzameling',false),
('rots_in_de_branding','verzameling',false),
('junior_van_de_match','verzameling',true),
('laat_je_ploeg','verzameling',false),
('getikte_zot','verzameling',false)
on conflict(id) do update set soort=excluded.soort,herhaalbaar=excluded.herhaalbaar;
alter table public.test_badge_catalogus enable row level security;
revoke all on public.test_badge_catalogus from public,anon,authenticated;

create table if not exists public.test_badge_toewijzingen (
 id uuid primary key default gen_random_uuid(),
 badge_id text not null references public.test_badge_catalogus(id),
 member_id uuid not null references public.members(id) on delete cascade,
 seizoen text check(seizoen ~ '^[0-9]{4}-[0-9]{4}$'),
 match_key text references public.matches(match_key) on delete cascade,
 aangemaakt_op timestamptz not null default now()
);
create unique index if not exists test_badge_een_keer on public.test_badge_toewijzingen
 (badge_id,member_id,coalesce(seizoen,''),coalesce(match_key,''));
alter table public.test_badge_toewijzingen enable row level security;
revoke all on public.test_badge_toewijzingen from public,anon,authenticated;
grant select on public.test_badge_toewijzingen to anon,authenticated;
drop policy if exists test_badges_lezen on public.test_badge_toewijzingen;
create policy test_badges_lezen on public.test_badge_toewijzingen for select using (true);

create or replace function public.mag_testbadges_beheren() returns boolean
language sql stable security definer set search_path=public as $$
 select is_actief() and is_admin() and exists(select 1 from push_config where allowed_member=my_member_id());
$$;
revoke all on function public.mag_testbadges_beheren() from public,anon;
grant execute on function public.mag_testbadges_beheren() to authenticated;

create or replace function public.wijs_testbadge_toe(p_badge_id text,p_member_id uuid,p_seizoen text default null,p_match_key text default null) returns uuid
language plpgsql security definer set search_path=public as $$
declare b test_badge_catalogus; resultaat uuid;
begin
 if not coalesce(mag_testbadges_beheren(),false) then raise exception 'Alleen de aangewezen testbeheerder kan badges toewijzen.'; end if;
 select * into b from test_badge_catalogus where id=p_badge_id;
 if not found then raise exception 'Onbekende badge.'; end if;
 if not exists(select 1 from members where id=p_member_id and status='actief' and functie<>'supporter') then raise exception 'Kies een actief clublid.'; end if;
 if b.soort='seizoen' then
   if p_seizoen is null or p_seizoen !~ '^[0-9]{4}-[0-9]{4}$' then raise exception 'Kies een geldig seizoen.'; end if;
   if right(p_seizoen,4)::integer <> left(p_seizoen,4)::integer+1 then raise exception 'Kies een geldig seizoen.'; end if;
 elsif p_seizoen is not null then raise exception 'Deze badge hoort niet bij een seizoen.';
 end if;
 if b.herhaalbaar then
   if p_match_key is null or not exists(select 1 from matches where match_key=p_match_key and (thuis_id=152 or uit_id=152)) then raise exception 'Kies de bijbehorende wedstrijd van Steca.'; end if;
 elsif p_match_key is not null then raise exception 'Deze badge wordt eenmalig toegewezen.';
 end if;
 insert into test_badge_toewijzingen(badge_id,member_id,seizoen,match_key)
 values(p_badge_id,p_member_id,p_seizoen,p_match_key) on conflict do nothing returning id into resultaat;
 if resultaat is null then raise exception 'Deze persoon heeft deze badge voor dit seizoen of deze wedstrijd al.'; end if;
 return resultaat;
end $$;
create or replace function public.verwijder_testbadge(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not coalesce(mag_testbadges_beheren(),false) then raise exception 'Alleen de aangewezen testbeheerder kan testbadges verwijderen.'; end if;
 delete from test_badge_toewijzingen where id=p_id;
end $$;
revoke all on function public.wijs_testbadge_toe(text,uuid,text,text),public.verwijder_testbadge(uuid) from public,anon;
grant execute on function public.wijs_testbadge_toe(text,uuid,text,text),public.verwijder_testbadge(uuid) to authenticated;

-- --------------------------------------------------------------- lichtkrant
-- Lezen: alle actieve leden. Toevoegen, aan- of uitzetten en verwijderen: alleen admins.
-- Elke wijziging komt in audit_log. Plakken in de Supabase SQL Editor en op Run klikken; veilig om te herhalen.

create table if not exists ticker_messages (
  id             uuid primary key default gen_random_uuid(),
  tekst          text not null check (char_length(tekst) between 1 and 140),
  actief         boolean not null default true,
  ingevoerd_door uuid references members (id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create or replace function ticker_messages_stamp() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if TG_OP = 'INSERT' then
    new.ingevoerd_door := coalesce(my_member_id(), new.ingevoerd_door);
    new.created_at := now();
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists ticker_messages_stamp on ticker_messages;
create trigger ticker_messages_stamp before insert or update on ticker_messages
  for each row execute function ticker_messages_stamp();
drop trigger if exists ticker_messages_log on ticker_messages;
create trigger ticker_messages_log after insert or update or delete on ticker_messages
  for each row execute function log_wijziging();

alter table ticker_messages enable row level security;
drop policy if exists "lichtkrant lezen" on ticker_messages;
create policy "lichtkrant lezen" on ticker_messages for select to authenticated using (is_actief());
drop policy if exists "lichtkrant beheren" on ticker_messages;
create policy "lichtkrant beheren" on ticker_messages for all to authenticated using (is_admin()) with check (is_admin());

-- Persoonlijke volgorde, uitsluitend presentatie; verleent nooit een badge.
create table if not exists public.test_badge_voorkeuren (
 member_id uuid primary key references public.members(id) on delete cascade,
 badges text[] not null default '{}'
);
alter table public.test_badge_voorkeuren enable row level security;
revoke all on public.test_badge_voorkeuren from public,anon,authenticated;
grant select on public.test_badge_voorkeuren to anon,authenticated;
drop policy if exists badgevoorkeur_lezen on public.test_badge_voorkeuren;
create policy badgevoorkeur_lezen on public.test_badge_voorkeuren for select using(true);
create or replace view public.test_badges_met_volgorde with (security_invoker=true) as
 select t.*,array_position(v.badges,t.badge_id) as volgorde
 from public.test_badge_toewijzingen t left join public.test_badge_voorkeuren v on v.member_id=t.member_id;
revoke all on public.test_badges_met_volgorde from public,anon,authenticated;
grant select on public.test_badges_met_volgorde to anon,authenticated;
create or replace function public.bewaar_badgevolgorde(p_badges text[]) returns void
language plpgsql security definer set search_path=public as $$
declare lid uuid:=my_member_id();
begin
 if lid is null or not is_actief() then raise exception 'Log in met je actieve clubaccount.'; end if;
 if p_badges is null or cardinality(p_badges)>40 or array_position(p_badges,null) is not null then raise exception 'Ongeldige badgevolgorde.'; end if;
 if (select count(distinct b) from unnest(p_badges) b)<>cardinality(p_badges) then raise exception 'Een badge mag maar een keer in de volgorde staan.'; end if;
 if exists(select 1 from unnest(p_badges) b where not exists(select 1 from test_badge_toewijzingen t where t.member_id=lid and t.badge_id=b)) then raise exception 'Je kunt alleen je eigen badges rangschikken.'; end if;
 insert into test_badge_voorkeuren(member_id,badges) values(lid,p_badges)
 on conflict(member_id) do update set badges=excluded.badges;
end $$;
revoke all on function public.bewaar_badgevolgorde(text[]) from public,anon;
grant execute on function public.bewaar_badgevolgorde(text[]) to authenticated;
-- Automatische badges: alleen afgesloten Steca-matchen. Historische seizoenen
-- blijven uit hun bewaarde wedstrijdcijfers beschikbaar, ook na 1 juli.
create or replace function public.bereken_badges()
returns table(id uuid,badge_id text,member_id uuid,seizoen text,match_key text,aangemaakt_op timestamptz)
language sql stable security definer set search_path=public as $$
with m as materialized (
 select x.*, row_number() over(order by datum,coalesce(uur,''),match_key) as nr
 from matches x
 where (thuis_id=152 or uit_id=152) and status='gespeeld'
 and thuis_score is not null and uit_score is not null and datum is not null
 and ((datum + coalesce(nullif(uur,'')::time,'15:00'::time)) at time zone 'Europe/Brussels') + interval '80 minutes' <= now()
), leden as materialized (
 select id from members where functie<>'supporter'
), cijfers as materialized (
 select s.*,m.seizoen,m.datum,m.nr,
 case when s.gespeeld and (case when m.thuis_id=152 then m.uit_score else m.thuis_score end)=0 then 1 else 0 end as cs
 from match_stats s join m using(match_key) join leden on leden.id=s.member_id
), stemmen as (
 select v.match_key,k.member_id,k.punten
 from match_votes v join m using(match_key)
 cross join lateral (values(v.eerste,3),(v.tweede,2),(v.derde,1)) k(member_id,punten)
 where v.voter_id not in(v.eerste,v.tweede,v.derde)
), punten as materialized (
 select s.match_key,s.member_id,sum(s.punten) as aantal
 from stemmen s join leden on leden.id=s.member_id group by s.match_key,s.member_id
), winnaars as materialized (
 select p.* from punten p where aantal>0 and aantal=(select max(q.aantal) from punten q where q.match_key=p.match_key)
), metingen as (
 select c.member_id,c.seizoen,c.datum,k.soort,k.aantal::bigint
 from cijfers c cross join lateral (values
 ('goals',c.goals),('assists',c.assists),('cs',c.cs),('kaarten',c.geel+c.rood),('rood',c.rood),('gespeeld',c.gespeeld::int)) k(soort,aantal)
 union all select a.member_id,m.seizoen,m.datum,'aanwezig',1 from attendance a join m using(match_key) join leden on leden.id=a.member_id where a.status='aanwezig'
 union all select w.member_id,m.seizoen,m.datum,'winnaar',1 from winnaars w join m using(match_key)
 union all select p.member_id,m.seizoen,m.datum,'punten',p.aantal from punten p join m using(match_key)
 union all select l.member_id,m.seizoen,m.datum,'was',1 from laundry_turns l join m using(match_key) join leden on leden.id=l.member_id
), totalen as materialized (
 select member_id,seizoen,soort,sum(aantal) as aantal,max(datum) as datum from metingen group by member_id,seizoen,soort
 union all select member_id,null,soort,sum(aantal),max(datum) from metingen group by member_id,soort
), titels(badge_id,soort,jaarlijks) as (values
 ('gouden_stier','goals',true),('het_kanon','goals',false),('assistenkoning','assists',true),('maestro','assists',false),
 ('de_muur','cs',true),('betonblok','cs',false),('beenhouwer','kaarten',true),('rosse_furie','rood',true),
 ('fundering','aanwezig',true),('vaste_waarde','gespeeld',true),('clubmeubilair','gespeeld',false),
 ('star_boy','winnaar',true),('goat','punten',false),('kuisvrouw','was',true),('junior_dor','punten',true)
), drempels(badge_id,soort,aantal) as (values
 ('eentje_is_geentje','goals',1),('dubbele_cijfers','goals',10),('goalgetter','goals',25),('sluipschutter','goals',50),('67','goals',67),('triple_digits','goals',100),
 ('wingman','assists',1),('facteur','assists',10),('de_architect','assists',25),('kdb_der_juniors','assists',50),
 ('muur_van_dendermonde','cs',1),('veilige_handen','cs',5),('opgewarmd_door_georgie','cs',10),('golden_glove','cs',25),
 ('official_junior','gespeeld',1),('toogplekker','gespeeld',10),('sterkhouder','gespeeld',25),('georgies_favoriet','gespeeld',50),('steca_legend','gespeeld',100),('laat_je_ploeg','rood',1)
), speelreeks as (
 select member_id,datum,nr-row_number() over(partition by member_id order by nr) as groep from cijfers where gespeeld
), aanwezigreeks as (
 select a.member_id,m.datum,m.nr-row_number() over(partition by a.member_id order by m.nr) as groep
 from attendance a join m using(match_key) join leden on leden.id=a.member_id where a.status='aanwezig'
), kaartenreeks as (
 select member_id,datum,(geel+rood)>0 as kaart,lag((geel+rood)>0) over(partition by member_id order by nr) as vorige
 from cijfers where gespeeld
), resultaat as (
 select b.badge_id,t.member_id,t.seizoen,null::text as match_key,t.datum
 from titels b join totalen t on t.soort=b.soort and (t.seizoen is not null)=b.jaarlijks
 where t.aantal>0 and t.aantal=(select max(q.aantal) from totalen q where q.soort=t.soort and q.seizoen is not distinct from t.seizoen)
 union all select d.badge_id,t.member_id,null,null,t.datum from drempels d join totalen t on t.soort=d.soort and t.seizoen is null and t.aantal>=d.aantal
 union all select 'hattrick',member_id,null,match_key,datum from cijfers where gespeeld and goals>=3
 union all select 'junior_van_de_match',w.member_id,null,w.match_key,m.datum from winnaars w join m using(match_key)
 union all select 'vijf_op_een_rij',member_id,null,null,max(datum) from speelreeks group by member_id,groep having count(*)>=5
 union all select 'rots_in_de_branding',member_id,null,null,max(datum) from aanwezigreeks group by member_id,groep having count(*)>=10
 union all select 'getikte_zot',member_id,null,null,datum from kaartenreeks where kaart and vorige
), uniek as (
 select badge_id,member_id,seizoen,match_key,min(datum) as datum from resultaat group by badge_id,member_id,seizoen,match_key
)
select md5(concat_ws('|',badge_id,member_id,seizoen,match_key))::uuid,badge_id,member_id,seizoen,match_key,
 (datum::timestamp at time zone 'Europe/Brussels') from uniek;
$$;
revoke all on function public.bereken_badges() from public;
grant execute on function public.bereken_badges() to anon,authenticated;

create table if not exists public.badge_voorkeuren (
 member_id uuid primary key references public.members(id) on delete cascade,
 badges text[] not null default '{}'
);
alter table public.badge_voorkeuren enable row level security;
revoke all on public.badge_voorkeuren from public,anon,authenticated;
grant select on public.badge_voorkeuren to anon,authenticated;
drop policy if exists badgevoorkeur_lezen on public.badge_voorkeuren;
create policy badgevoorkeur_lezen on public.badge_voorkeuren for select using(true);
create or replace view public.badges_met_volgorde with (security_invoker=true) as
 select b.*,array_position(v.badges,b.badge_id) as volgorde,true as automatisch from public.bereken_badges() b left join public.badge_voorkeuren v on v.member_id=b.member_id;
grant select on public.badges_met_volgorde to anon,authenticated;
create or replace function public.bewaar_badgevolgorde(p_badges text[]) returns void
language plpgsql security definer set search_path=public as $$
declare lid uuid:=my_member_id();
begin
 if lid is null or not is_actief() then raise exception 'Log in met je actieve clubaccount.'; end if;
 if p_badges is null or cardinality(p_badges)>40 or array_position(p_badges,null) is not null then raise exception 'Ongeldige badgevolgorde.'; end if;
 if (select count(distinct b) from unnest(p_badges) b)<>cardinality(p_badges) then raise exception 'Een badge mag maar een keer in de volgorde staan.'; end if;
 if exists(select 1 from unnest(p_badges) b where not exists(select 1 from badges_met_volgorde t where t.member_id=lid and t.badge_id=b)) then raise exception 'Je kunt alleen je eigen badges rangschikken.'; end if;
 insert into badge_voorkeuren(member_id,badges) values(lid,p_badges) on conflict(member_id) do update set badges=excluded.badges;
end $$;
revoke all on function public.bewaar_badgevolgorde(text[]) from public,anon;
grant execute on function public.bewaar_badgevolgorde(text[]) to authenticated;


-- Alleen test: handmatige voorbeelden blijven naast de berekende badges zichtbaar.
create or replace view public.badges_met_volgorde with (security_invoker=true) as
 with gecombineerd as (
  select b.*,false as automatisch from public.test_badge_toewijzingen b
  union all
  select b.*,true as automatisch from public.bereken_badges() b
  where not exists(select 1 from public.test_badge_toewijzingen t where t.member_id=b.member_id and t.badge_id=b.badge_id and t.seizoen is not distinct from b.seizoen and t.match_key is not distinct from b.match_key)
 ) select b.id,b.badge_id,b.member_id,b.seizoen,b.match_key,b.aangemaakt_op,array_position(v.badges,b.badge_id) as volgorde,b.automatisch
 from gecombineerd b left join public.badge_voorkeuren v on v.member_id=b.member_id;
insert into public.badge_voorkeuren select * from public.test_badge_voorkeuren on conflict do nothing;


-- Supporteraanwezigheid: apart van de spelers en zonder extra schrijfrechten.
create or replace function public.is_supporter_account() returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from supporter_profiles where user_id=auth.uid() and actief);
$$;
revoke all on function public.is_supporter_account() from public,anon;
grant execute on function public.is_supporter_account() to authenticated;

create table if not exists public.supporter_attendance (
 match_key text not null references public.matches(match_key) on delete cascade,
 user_id uuid not null references public.supporter_profiles(user_id) on delete cascade,
 status text not null check(status in ('aanwezig','afwezig','onzeker')),
 updated_at timestamptz not null default now(),
 primary key(match_key,user_id)
);
alter table public.supporter_attendance enable row level security;
revoke all on public.supporter_attendance from anon,authenticated;
grant all on public.supporter_attendance to service_role;

-- Alleen namen en antwoorden, geen e-mailadressen of andere profielgegevens.
create or replace function public.supporter_aanwezigheden() returns table(match_key text,user_id uuid,naam text,status text)
language sql stable security definer set search_path=public as $$
 select a.match_key,a.user_id,s.naam,a.status
 from supporter_attendance a join supporter_profiles s on s.user_id=a.user_id
 where s.actief and (is_actief() or is_supporter_account())
 order by s.naam;
$$;
revoke all on function public.supporter_aanwezigheden() from public,anon;
grant execute on function public.supporter_aanwezigheden() to authenticated;

-- Geen user-id als invoer: een supporter kan uitsluitend zijn eigen antwoord zetten.
create or replace function public.zet_supporter_aanwezigheid(p_match text,p_status text) returns void
language plpgsql security definer set search_path=public as $$
begin
 perform 1 from supporter_profiles where user_id=auth.uid() and actief for share;
 if not found then raise exception 'Log in met een actief supporteraccount.'; end if;
 if p_status is null or p_status not in ('aanwezig','afwezig','onzeker') then raise exception 'Ongeldige aanwezigheid.'; end if;
 perform 1 from matches where match_key=p_match and (thuis_id=152 or uit_id=152)
  and status='gepland' and datum >= (now() at time zone 'Europe/Brussels')::date for share;
 if not found then raise exception 'Je kunt alleen antwoorden voor een komende match van Steca Juniors.'; end if;
 insert into supporter_attendance(match_key,user_id,status) values(p_match,auth.uid(),p_status)
 on conflict(match_key,user_id) do update set status=excluded.status,updated_at=now();
end;
$$;
revoke all on function public.zet_supporter_aanwezigheid(text,text) from public,anon;
grant execute on function public.zet_supporter_aanwezigheid(text,text) to authenticated;

-- Dezelfde leesweergave in de app, zonder lid te worden of stem-/stafrechten te krijgen.
do $$
declare tabel text;
begin
 foreach tabel in array array['attendance','lineups','lineup_players','match_stats','fines','laundry_turns','match_reports','ticker_messages'] loop
  execute format('drop policy if exists supporter_app_lezen on public.%I',tabel);
  execute format('create policy supporter_app_lezen on public.%I for select to authenticated using (public.is_supporter_account())',tabel);
 end loop;
end;
$$;

create or replace view public.match_vote_points as
 select s.match_key,s.member_id,sum(s.punten)::int as punten,count(*)::int as stemmen
 from (
  select match_key,eerste as member_id,3 as punten from match_votes
  union all select match_key,tweede,2 from match_votes
  union all select match_key,derde,1 from match_votes
 ) s where is_actief() or is_supporter_account() group by s.match_key,s.member_id;
create or replace view public.match_vote_counts as
 select match_key,count(*)::int as stemmers from match_votes
 where is_actief() or is_supporter_account() group by match_key;



-- Supportersklassement en badgeproef: uitsluitend de testapp.
create table if not exists public.supporter_fans(id uuid primary key default gen_random_uuid(),user_id uuid unique references auth.users(id) on delete set null,naam text not null);
create table if not exists public.supporter_bezoeken(persoon uuid references supporter_fans(id) on delete cascade,match text not null,primary key(persoon,match));
create table if not exists public.supporter_proefmatches(id text primary key,seizoen text not null,datum date not null,uit boolean not null default false,gespeeld boolean not null default true,label text not null);
create table if not exists public.supporter_seizoen_afgerond(seizoen text primary key);
create table if not exists public.supporter_proefbadges(persoon uuid references supporter_fans(id) on delete cascade,badge text not null,seizoen text not null default '',primary key(persoon,badge,seizoen));
alter table supporter_fans enable row level security;
alter table supporter_bezoeken enable row level security;
alter table supporter_proefmatches enable row level security;
alter table supporter_seizoen_afgerond enable row level security;
alter table supporter_proefbadges enable row level security;
revoke all on supporter_fans,supporter_bezoeken,supporter_proefmatches,supporter_seizoen_afgerond,supporter_proefbadges from anon,authenticated;
grant all on supporter_fans,supporter_bezoeken,supporter_proefmatches,supporter_seizoen_afgerond,supporter_proefbadges to service_role;

create or replace function public.koppel_supporter_fan() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into supporter_fans(user_id,naam) values(new.user_id,new.naam) on conflict(user_id) do update set naam=excluded.naam;return new;end $$;
drop trigger if exists supporter_fan_profiel on supporter_profiles;
create trigger supporter_fan_profiel after insert or update of naam on supporter_profiles for each row execute function koppel_supporter_fan();
insert into supporter_fans(user_id,naam) select user_id,naam from supporter_profiles on conflict(user_id) do update set naam=excluded.naam;

create or replace function public.supporter_klassement_data() returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if not (is_actief() or exists(select 1 from supporter_profiles where user_id=auth.uid() and actief)) then raise exception 'Log in met een actief account.';end if;
 return jsonb_build_object(
 'personen',coalesce((select jsonb_agg(to_jsonb(p) order by naam) from supporter_fans p),'[]'::jsonb),
 'matches',coalesce((select jsonb_agg(to_jsonb(m)) from (
 select match_key as id,seizoen,datum,(uit_id=152) as uit,(status='gespeeld' and match_aftrap(datum,uur)+interval '80 minutes'<=now()) as gespeeld,thuis||' - '||uit as label
 from matches where (thuis_id=152 or uit_id=152) and datum is not null and coalesce(bron,'') not in ('push-test','test-invoer') and match_key<>'test-matchverslag-voorbeeld'
 union all select id,seizoen,datum,uit,gespeeld and datum<=(now() at time zone 'Europe/Brussels')::date,label from supporter_proefmatches
 ) m),'[]'::jsonb),
 'bezoeken',coalesce((select jsonb_agg(to_jsonb(b)) from (select persoon,match from supporter_bezoeken union select f.id,a.match_key from supporter_attendance a join supporter_fans f on f.user_id=a.user_id where a.status='aanwezig') b),'[]'::jsonb),
 'afgerond',coalesce((select jsonb_agg(seizoen) from supporter_seizoen_afgerond),'[]'::jsonb),
 'testbadges',coalesce((select jsonb_agg(jsonb_build_object('persoon',persoon,'badge',badge,'seizoen',nullif(seizoen,''))) from supporter_proefbadges),'[]'::jsonb));
end $$;
revoke all on function supporter_klassement_data() from public,anon;
grant execute on function supporter_klassement_data() to authenticated;

create or replace function public.supporter_testactie(p_actie text,p_data jsonb default '{}') returns void language plpgsql security definer set search_path=public as $$
declare pid uuid; uid uuid; mk text; nm text; n int; s text; i int; aanwezig boolean;
begin
 if not coalesce(mag_testbadges_beheren(),false) then raise exception 'Alleen de aangewezen testbeheerder kan dit aanpassen.';end if;
 s:=coalesce(nullif(p_data->>'seizoen',''),'2026-2027');
 if s!~'^[0-9]{4}-[0-9]{4}$' then raise exception 'Ongeldig seizoen.';end if;
 if p_actie='persoon' then
  nm:=trim(p_data->>'naam');if nm is null or length(nm)<2 or length(nm)>100 then raise exception 'Vul een naam in.';end if;
  insert into supporter_fans(naam) values(nm);
 elsif p_actie='eerste_match' then
  select match_key into mk from matches where (thuis_id=152 or uit_id=152) and seizoen=s and status='gespeeld' and coalesce(bron,'') not in ('push-test','test-invoer') and match_key<>'test-matchverslag-voorbeeld' order by datum,match_key limit 1;
  if mk is null then
   mk:='supporter-eerste-'||s;
   insert into supporter_proefmatches values(mk,s,'2026-09-12',true,true,'Eerste match: FC Patron - Steca Juniors') on conflict(id) do nothing;
  end if;
  foreach nm in array array['Ben Osselaer','Falco Tas','Luca Van Ransbeeck','Yoon Selleslagh'] loop
   select id into pid from supporter_fans where lower(naam)=lower(nm) order by user_id nulls last,id limit 1;
   if pid is null then insert into supporter_fans(naam) values(nm) returning id into pid;end if;
   insert into supporter_bezoeken values(pid,mk) on conflict do nothing;
  end loop;
 elsif p_actie='afsluiten' then
  if (p_data->>'afgerond')::boolean then insert into supporter_seizoen_afgerond values(s) on conflict do nothing;
  else delete from supporter_seizoen_afgerond where seizoen=s;end if;
 else
  pid:=(p_data->>'persoon')::uuid;
  if not exists(select 1 from supporter_fans where id=pid) then raise exception 'Kies een supporter.';end if;
  if p_actie='bezoek' then
   mk:=p_data->>'match';
   if not (exists(select 1 from matches where match_key=mk and (thuis_id=152 or uit_id=152)) or exists(select 1 from supporter_proefmatches where id=mk)) then raise exception 'Kies een Steca-match.';end if;
   select user_id into uid from supporter_fans where id=pid;
   if uid is not null and exists(select 1 from supporter_profiles where user_id=uid) and exists(select 1 from matches where match_key=mk) then
    insert into supporter_attendance(match_key,user_id,status) values(mk,uid,case when (p_data->>'aanwezig')::boolean then 'aanwezig' else 'afwezig' end) on conflict(match_key,user_id) do update set status=excluded.status,updated_at=now();
   end if;
   if (p_data->>'aanwezig')::boolean then insert into supporter_bezoeken values(pid,mk) on conflict do nothing;else delete from supporter_bezoeken where persoon=pid and match=mk;end if;
  elsif p_actie='badge' then
   if coalesce(p_data->>'badge','') not in ('ultra_jaar','eeuwige_ultra','vaste_klant','prioriteiten','perfect_seizoen','first_away','away_crew','onderweg','zwart_wit','away_legend','away_icon','welkom','smaak','toog','hardcore','team','tribune','busje') then raise exception 'Onbekende badge.';end if;
   if (p_data->>'toewijzen')::boolean then insert into supporter_proefbadges values(pid,p_data->>'badge',coalesce(p_data->>'badgeSeizoen','')) on conflict do nothing;
   else delete from supporter_proefbadges where persoon=pid and badge=p_data->>'badge' and seizoen=coalesce(p_data->>'badgeSeizoen','');end if;
  elsif p_actie='reeks' then
   n:=(p_data->>'aantal')::int;if n not in(1,5,10,25,50,100) then raise exception 'Kies 1, 5, 10, 25, 50 of 100.';end if;
   for i in 1..n loop
    mk:='supporter-proef-'||s||'-'||lpad(i::text,3,'0');
    insert into supporter_proefmatches values(mk,s,current_date-(n-i+1)*7,true,true,'Supporter-testmatch '||i) on conflict(id) do update set datum=excluded.datum;
    insert into supporter_bezoeken values(pid,mk) on conflict do nothing;
   end loop;
  elsif p_actie='wis_reeks' then
   delete from supporter_bezoeken where match in(select id from supporter_proefmatches where id like 'supporter-proef-%');
   delete from supporter_proefmatches where id like 'supporter-proef-%';
  else raise exception 'Onbekende actie.';end if;
 end if;
end $$;
revoke all on function supporter_testactie(text,jsonb) from public,anon;
grant execute on function supporter_testactie(text,jsonb) to authenticated;
-- Ploegscheiding: gedeelde accounts, afzonderlijke vrouwenrollen en gegevens.
-- Dit blok is aanvullend. Bestaande mannen-RPCs en notificatiejobs blijven intact.
create table if not exists public.club_members (
 id uuid primary key default gen_random_uuid(), club_id text not null check(club_id='vrouwen'),
 user_id uuid references auth.users(id) on delete set null, naam text not null check(length(naam) between 1 and 100),
 functie text not null default 'supporter' check(functie in ('speler','spelercoach','coach','verantwoordelijke','supporter')),
 status text not null default 'actief' check(status in ('actief','wacht_op_goedkeuring','inactief')),
 is_admin boolean not null default false, speelt boolean not null default false,
 unique(club_id,user_id), unique(club_id,id)
);
create table if not exists public.club_role_requests (
 club_id text not null check(club_id='vrouwen'), user_id uuid references auth.users(id) on delete cascade,
 functie text not null check(functie in ('speler','spelercoach','coach','verantwoordelijke')),
 primary key(club_id,user_id)
);
create or replace function public.club_role(p_club text) returns text language sql stable security definer set search_path=public as $$
 select case when p_club='vrouwen' and auth.uid() is not null then coalesce((select case when status='actief' then functie else 'geblokkeerd' end from club_members where club_id=p_club and user_id=auth.uid()),'supporter') else 'geblokkeerd' end
$$;
create or replace function public.club_admin(p_club text) returns boolean language sql stable security definer set search_path=public as $$
 select p_club='vrouwen' and public.is_admin()
$$;
create or replace function public.club_staf(p_club text) returns boolean language sql stable security definer set search_path=public as $$
 select club_admin(p_club) or club_role(p_club) in ('coach','spelercoach','verantwoordelijke')
$$;
create table if not exists public.club_matches (
 club_id text not null check(club_id='vrouwen'), match_key text not null, seizoen text not null,
 aftrap timestamptz not null, thuis text not null, uit text not null, locaties jsonb not null default '[]',
 reeks text not null default '', thuis_score integer check(thuis_score between 0 and 99), uit_score integer check(uit_score between 0 and 99),
 score_at timestamptz, is_test boolean not null default false, primary key(club_id,match_key),
 check((thuis_score is null)=(uit_score is null))
);
create table if not exists public.club_attendance (
 club_id text not null, match_key text not null, user_id uuid references auth.users(id) on delete cascade,
 status text not null check(status in ('aanwezig','afwezig','onzeker')), primary key(club_id,match_key,user_id),
 foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade
);
create table if not exists public.club_lineups (
 club_id text not null, match_key text not null, keuze jsonb not null default '{}', slotjes jsonb not null default '[]',
 versie integer not null default 1, primary key(club_id,match_key),
 foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade
);
create table if not exists public.club_reports (
 club_id text not null, match_key text not null, statistieken jsonb not null default '[]',
 verslag text not null default '', primary key(club_id,match_key),
 foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade
);
create table if not exists public.club_predictions (
 club_id text not null, match_key text not null, user_id uuid references auth.users(id) on delete cascade,
 thuis integer not null check(thuis between 0 and 99), uit integer not null check(uit between 0 and 99),
 primary key(club_id,match_key,user_id), foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade
);
create table if not exists public.club_dream (
 club_id text not null check(club_id='vrouwen'), user_id uuid references auth.users(id) on delete cascade,
 keuze jsonb not null default '{}', versie integer not null default 1, primary key(club_id,user_id)
);
create table if not exists public.club_votes (
 club_id text not null, match_key text not null, user_id uuid references auth.users(id) on delete cascade,
 eerste uuid not null, tweede uuid not null, derde uuid not null,
 primary key(club_id,match_key,user_id), foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade,
 foreign key(club_id,eerste) references club_members(club_id,id),
 foreign key(club_id,tweede) references club_members(club_id,id), foreign key(club_id,derde) references club_members(club_id,id),
 check(eerste<>tweede and eerste<>derde and tweede<>derde)
);
create table if not exists public.club_laundry (
 club_id text not null, match_key text not null, member_id uuid not null,
 primary key(club_id,match_key), foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade,
 foreign key(club_id,member_id) references club_members(club_id,id)
);
-- Geen directe mutaties. Alle schrijfacties lopen door gecontroleerde RPCs.
do $$ declare t text; begin
 foreach t in array array['club_members','club_role_requests','club_matches','club_attendance','club_lineups','club_reports','club_predictions','club_dream','club_votes','club_laundry'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end $$;
create or replace function public.club_naam(p_user uuid) returns text language sql stable security definer set search_path=public as $$
 select coalesce((select naam from members where user_id=p_user),(select naam from supporter_profiles where user_id=p_user),'Clublid')
$$;
-- Aanwezigheid van ingeschreven speelsters die nog geen login hebben.
create table if not exists public.club_member_attendance (
 club_id text not null,match_key text not null,member_id uuid not null,
 status text not null check(status in ('aanwezig','afwezig','onzeker')),
 primary key(club_id,match_key,member_id),
 foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade,
 foreign key(club_id,member_id) references club_members(club_id,id) on delete cascade
);
alter table club_member_attendance enable row level security;
revoke all on club_member_attendance from public,anon,authenticated;
grant all on club_member_attendance to service_role;
create or replace function public.club_aanwezig_lid(p_club text,p_match text,p_lid uuid,p_status text) returns void
language plpgsql security definer set search_path=public as $$
declare u uuid;
begin
 if not club_staf(p_club) then raise exception 'Alleen de staf kan aanwezigheden aanpassen.';end if;
 if not exists(select 1 from club_matches where club_id=p_club and match_key=p_match ) then raise exception 'Wedstrijd niet gevonden.';end if;
 select user_id into u from club_members where club_id=p_club and id=p_lid and speelt and status='actief';
 if not found then raise exception 'Geen actieve speelster.';end if;
 if u is not null then
 insert into club_attendance values(p_club,p_match,u,p_status) on conflict(club_id,match_key,user_id) do update set status=excluded.status;
 delete from club_member_attendance where club_id=p_club and match_key=p_match and member_id=p_lid;
 else
 insert into club_member_attendance values(p_club,p_match,p_lid,p_status) on conflict(club_id,match_key,member_id) do update set status=excluded.status;
 end if;
end $$;
create or replace function public.club_data(p_club text) returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if club_role(p_club)='geblokkeerd' then raise exception 'Log in met een actief account.';end if;
 return jsonb_build_object(
 'rol',club_role(p_club),'admin',club_admin(p_club),'staf',club_staf(p_club),'user_id',auth.uid(),
 'leden',coalesce((select jsonb_agg(to_jsonb(m)) from club_members m where club_id=p_club and (status='actief' or club_admin(p_club))),'[]'),
 'aanvragen',case when club_admin(p_club) then coalesce((select jsonb_agg(jsonb_build_object('user_id',r.user_id,'naam',club_naam(r.user_id),'functie',r.functie)) from club_role_requests r where r.club_id=p_club),'[]') else '[]'::jsonb end,
 'matches',coalesce((select jsonb_agg(to_jsonb(m) order by aftrap) from club_matches m where club_id=p_club),'[]'),
 'aanwezigheden',coalesce((select jsonb_agg(v) from (
 select a.match_key,a.user_id,m.id as member_id,coalesce(m.naam,club_naam(a.user_id)) as naam,a.status,coalesce(m.status='actief' and m.speelt,false) as speler from club_attendance a left join club_members m on m.club_id=a.club_id and m.user_id=a.user_id where a.club_id=p_club
 union all select a.match_key,coalesce(m.user_id,m.id),m.id,m.naam,a.status,m.status='actief' and m.speelt from club_member_attendance a join club_members m on m.id=a.member_id and m.club_id=a.club_id where a.club_id=p_club and not exists(select 1 from club_attendance c where c.club_id=a.club_id and c.match_key=a.match_key and c.user_id=m.user_id)
 ) v),'[]'),
 'opstellingen',coalesce((select jsonb_agg(to_jsonb(l)) from club_lineups l where club_id=p_club),'[]'),
 'verslagen',coalesce((select jsonb_agg(to_jsonb(r)) from club_reports r where club_id=p_club),'[]'),
 'pronos',coalesce((select jsonb_agg(to_jsonb(p)) from club_predictions p join club_matches m using(club_id,match_key) where p.club_id=p_club and (p.user_id=auth.uid() or m.aftrap<=now())),'[]'),
 'dream',(select to_jsonb(d) from club_dream d where club_id=p_club and user_id=auth.uid()),
 'stemmen',coalesce((select jsonb_agg(to_jsonb(v)) from club_votes v where club_id=p_club and user_id=auth.uid()),'[]'),
 'stempunten',coalesce((select jsonb_agg(to_jsonb(r)) from (select v.match_key,k.member_id,sum(k.punten)::int punten,count(*)::int stemmen from club_votes v join club_matches m on m.club_id=v.club_id and m.match_key=v.match_key cross join lateral (values(v.eerste,3),(v.tweede,2),(v.derde,1)) k(member_id,punten) where v.club_id=p_club and m.thuis_score is not null and m.aftrap+interval '80 minutes'<=now() group by v.match_key,k.member_id) r),'[]'),
 'wasmand',coalesce((select jsonb_agg(to_jsonb(l)) from club_laundry l where club_id=p_club),'[]'),
 'pronoleden',coalesce((select jsonb_agg(jsonb_build_object('user_id',u.id,'naam',club_naam(u.id))) from auth.users u where exists(select 1 from members m where m.user_id=u.id and m.status='actief') or exists(select 1 from supporter_profiles s where s.user_id=u.id and s.actief)),'[]')
 );
end $$;
create or replace function public.club_vraag_rol(p_club text,p_functie text) returns void language plpgsql security definer set search_path=public as $$
begin
 if club_role(p_club)='geblokkeerd' then raise exception 'Log eerst in.';end if;
 insert into club_role_requests values(p_club,auth.uid(),p_functie) on conflict(club_id,user_id) do update set functie=excluded.functie;
end $$;
create or replace function public.club_zet_lid(p_club text,p_user uuid,p_functie text,p_speelt boolean,p_admin boolean default false,p_status text default 'actief') returns void language plpgsql security definer set search_path=public as $$
begin
 if not club_admin(p_club) then raise exception 'Alleen een beheerder van deze ploeg.';end if;
 perform pg_advisory_xact_lock(hashtextextended('clubbeheer-'||p_club,0));
 if p_user=auth.uid() and p_status<>'actief' then raise exception 'Je kunt jezelf niet als beheerder uitschakelen.';end if;
 if p_functie='supporter' and p_speelt then raise exception 'Een supporter kan niet opgesteld worden of beheerder zijn.';end if;
 insert into club_members(club_id,user_id,naam,functie,speelt,is_admin,status) values(p_club,p_user,club_naam(p_user),p_functie,p_speelt,exists(select 1 from members where user_id=p_user and status='actief' and is_admin),p_status)
 on conflict(club_id,user_id) do update set functie=excluded.functie,speelt=excluded.speelt,is_admin=excluded.is_admin,status=excluded.status;
 delete from club_role_requests where club_id=p_club and user_id=p_user;
end $$;
create or replace function public.club_aanwezig(p_club text,p_match text,p_status text,p_user uuid default null) returns void language plpgsql security definer set search_path=public as $$
declare u uuid:=coalesce(p_user,auth.uid());begin
 if club_role(p_club)='geblokkeerd' or (u<>auth.uid() and not club_staf(p_club)) then raise exception 'Geen bevoegdheid voor deze aanwezigheid.';end if;
 if not exists(select 1 from club_matches where club_id=p_club and match_key=p_match and aftrap>now()) then raise exception 'Alleen voor een komende match.';end if;
 insert into club_attendance values(p_club,p_match,u,p_status) on conflict(club_id,match_key,user_id) do update set status=excluded.status;
end $$;
create or replace function public.club_controle_keuze(p_club text,p_keuze jsonb,p_match text default null) returns void language plpgsql security definer set search_path=public as $$
declare k text; v text; gezien text[]:='{}';begin
 if jsonb_typeof(p_keuze)<>'object' or length(p_keuze::text)>8000 then raise exception 'Ongeldige opstelling.';end if;
 for k,v in select * from jsonb_each_text(p_keuze) loop
 if k='__formatie' then if v is null or v not in ('2-2','3-1','1-2-1') then raise exception 'Onbekende formatie.';end if;continue;end if;
 if k not in ('GK','LB','RB','LW','RW','BANK1','BANK2','BANK3','BANK4','BANK5') then raise exception 'Onbekende positie.';end if;
 if v is null or v='' then continue;end if;
 if v=any(gezien) then raise exception 'Iemand staat dubbel in de opstelling.';end if;gezien:=array_append(gezien,v);
 if not exists(select 1 from club_members m where m.club_id=p_club and m.id::text=v and m.status='actief' and m.speelt and (p_match is null or exists(select 1 from club_attendance a where a.club_id=p_club and a.match_key=p_match and a.user_id=m.user_id and a.status='aanwezig') or exists(select 1 from club_member_attendance a where a.club_id=m.club_id and a.match_key=p_match and a.member_id=m.id and a.status='aanwezig' and not exists(select 1 from club_attendance c where c.club_id=a.club_id and c.match_key=a.match_key and c.user_id=m.user_id)))) then raise exception 'Alleen aanwezige speelsters van deze ploeg kunnen geselecteerd worden.';end if;
 end loop;
end $$;
create or replace function public.club_bewaar_opstelling(p_club text,p_match text,p_keuze jsonb,p_slotjes jsonb,p_versie integer) returns integer language plpgsql security definer set search_path=public as $$
declare v integer;begin
 if not club_staf(p_club) then raise exception 'Geen opstellingsrechten voor deze ploeg.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_club||p_match,0));
 select versie into v from club_lineups where club_id=p_club and match_key=p_match;
 if coalesce(v,0)<>p_versie then raise exception 'De opstelling is ondertussen gewijzigd. Herlaad eerst.';end if;
 if not exists(select 1 from club_matches where club_id=p_club and match_key=p_match and aftrap>now()) then raise exception 'Deze opstelling is afgesloten.';end if;
 perform club_controle_keuze(p_club,p_keuze,p_match);
 if jsonb_typeof(p_slotjes)<>'array' or jsonb_array_length(p_slotjes)>12 then raise exception 'Ongeldige slotjes.';end if;
 insert into club_lineups values(p_club,p_match,p_keuze,p_slotjes,coalesce(v,0)+1) on conflict(club_id,match_key) do update set keuze=excluded.keuze,slotjes=excluded.slotjes,versie=excluded.versie returning versie into v;
 return v;
end $$;
create or replace function public.club_bewaar_dream(p_club text,p_keuze jsonb,p_versie integer) returns integer language plpgsql security definer set search_path=public as $$
declare v integer;begin
 if club_role(p_club)='geblokkeerd' then raise exception 'Log eerst in.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_club||auth.uid()::text,0));
 select versie into v from club_dream where club_id=p_club and user_id=auth.uid();
 if coalesce(v,0)<>p_versie then raise exception 'Je droomploeg is elders aangepast. Herlaad eerst.';end if;
 perform club_controle_keuze(p_club,p_keuze);
 insert into club_dream values(p_club,auth.uid(),p_keuze,coalesce(v,0)+1) on conflict(club_id,user_id) do update set keuze=excluded.keuze,versie=excluded.versie returning versie into v;return v;
end $$;
create or replace function public.club_bewaar_prono(p_club text,p_match text,p_thuis integer,p_uit integer) returns void language plpgsql security definer set search_path=public as $$
begin
 if club_role(p_club)='geblokkeerd' then raise exception 'Log eerst in.';end if;
 if not exists(select 1 from club_matches where club_id=p_club and match_key=p_match and aftrap>now() and thuis_score is null) then raise exception 'Pronostieken zijn afgesloten.';end if;
 insert into club_predictions values(p_club,p_match,auth.uid(),p_thuis,p_uit) on conflict(club_id,match_key,user_id) do update set thuis=excluded.thuis,uit=excluded.uit;
end $$;
create or replace function public.club_bewaar_verslag(p_club text,p_match text,p_thuis integer,p_uit integer,p_stats jsonb,p_verslag text) returns void language plpgsql security definer set search_path=public as $$
declare r jsonb;k text;begin
 if not club_staf(p_club) then raise exception 'Geen verslagrechten voor deze ploeg.';end if;
 if jsonb_typeof(p_stats)<>'array' or jsonb_array_length(p_stats)>30 or length(p_verslag)>10000 then raise exception 'Ongeldig verslag.';end if;
 for r in select * from jsonb_array_elements(p_stats) loop
 if not exists(select 1 from club_members where club_id=p_club and id::text=r->>'id' and speelt and status='actief') then raise exception 'Onbekende speelster.';end if;
 foreach k in array array['goals','assists','geel','rood'] loop
 if coalesce((r->>k)::integer,0) not between 0 and (case when k='geel' then 2 when k='rood' then 1 else 30 end) then raise exception 'Ongeldige statistiek.';end if;
 end loop;end loop;
 update club_matches set thuis_score=p_thuis,uit_score=p_uit,score_at=coalesce(score_at,now()) where club_id=p_club and match_key=p_match and aftrap<=now();
 if not found then raise exception 'Deze wedstrijd is nog niet begonnen.';end if;
 insert into club_reports values(p_club,p_match,p_stats,p_verslag) on conflict(club_id,match_key) do update set statistieken=excluded.statistieken,verslag=excluded.verslag;
end $$;
create or replace function public.club_stem(p_club text,p_match text,p_eerste uuid,p_tweede uuid,p_derde uuid) returns void language plpgsql security definer set search_path=public as $$
declare v uuid;begin
 if not exists(select 1 from club_members m join club_attendance a on a.club_id=m.club_id and a.user_id=m.user_id where m.club_id=p_club and m.user_id=auth.uid() and m.status='actief' and m.speelt and a.match_key=p_match and a.status='aanwezig') then raise exception 'Alleen aanwezige speelsters kunnen stemmen.';end if;
 if not exists(select 1 from club_matches where club_id=p_club and match_key=p_match and thuis_score is not null and now()>=aftrap+interval '80 minutes' and now()<aftrap+interval '24 hours') then raise exception 'Stemmen is nog niet geopend of al afgesloten.';end if;
 foreach v in array array[p_eerste,p_tweede,p_derde] loop
 if not exists(select 1 from club_members m join club_lineups l on l.club_id=m.club_id where m.club_id=p_club and m.id=v and m.user_id is distinct from auth.uid() and m.speelt and l.match_key=p_match and exists(select 1 from jsonb_each_text(l.keuze) kv where kv.value=v::text)) then raise exception 'Kies drie andere geselecteerde speelsters.';end if;end loop;
 insert into club_votes values(p_club,p_match,auth.uid(),p_eerste,p_tweede,p_derde) on conflict(club_id,match_key,user_id) do update set eerste=excluded.eerste,tweede=excluded.tweede,derde=excluded.derde;
end $$;
create or replace function public.club_zet_wasmand(p_club text,p_match text,p_lid uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not club_staf(p_club) then raise exception 'Geen bevoegdheid voor deze ploeg.';end if;
 if not exists(select 1 from club_members where club_id=p_club and id=p_lid and status='actief' and functie<>'supporter') then raise exception 'Kies een clublid van deze ploeg.';end if;
 insert into club_laundry values(p_club,p_match,p_lid) on conflict(club_id,match_key) do update set member_id=excluded.member_id;
end $$;
-- Alleen server-/SQL-toegang voor import. Een browser kan geen wedstrijden aanmaken.
create or replace function public.club_import_matches(p_data jsonb) returns void language plpgsql security definer set search_path=public as $$
declare m jsonb;begin
 for m in select * from jsonb_array_elements(p_data->'wedstrijden') loop
 insert into club_matches(club_id,match_key,seizoen,aftrap,thuis,uit,locaties,reeks,thuis_score,uit_score,score_at)
 values('vrouwen','twizzit-'||(m->>'id'),p_data->>'seizoen',(m->>'aftrap')::timestamptz,m->>'thuis',m->>'uit',m->'locaties',m->>'reeks',(m->'score'->>0)::integer,(m->'score'->>1)::integer,case when m->'score'->>0 is not null then now() end)
 on conflict(club_id,match_key) do update set aftrap=excluded.aftrap,locaties=excluded.locaties,reeks=excluded.reeks;
 end loop;
end $$;
-- Nieuwe vrouwenaccounts zijn bij de mannen supporter. Zelfgekozen vrouwenrollen
-- zijn uitsluitend aanvragen, nooit automatische beheer- of spelersrechten.
create or replace function public.club_nieuw_account() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if not exists(select 1 from club_members where club_id='vrouwen' and user_id=new.id and status='actief') and new.raw_user_meta_data->>'club'='vrouwen' and new.raw_user_meta_data->>'club_functie' in ('speler','spelercoach','coach','verantwoordelijke') then
 insert into club_role_requests values('vrouwen',new.id,new.raw_user_meta_data->>'club_functie') on conflict do nothing;
 end if;return new;
end $$;
drop trigger if exists on_club_user_created on auth.users;
create trigger on_club_user_created after insert on auth.users for each row execute function club_nieuw_account();
-- Sluit ook standaard PUBLIC-execute op security-definer helpers af.
do $$ declare f record;begin
 for f in select p.oid::regprocedure as naam from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'club\_%' escape '\' loop
 execute format('revoke all on function %s from public,anon,authenticated',f.naam);
 execute format('grant execute on function %s to service_role',f.naam);
 end loop;
end $$;
grant execute on function club_aanwezig_lid(text,text,uuid,text),club_data(text),club_vraag_rol(text,text),club_zet_lid(text,uuid,text,boolean,boolean,text),club_aanwezig(text,text,text,uuid),club_bewaar_opstelling(text,text,jsonb,jsonb,integer),club_bewaar_dream(text,jsonb,integer),club_bewaar_prono(text,text,integer,integer),club_bewaar_verslag(text,text,integer,integer,jsonb,text),club_stem(text,text,uuid,uuid,uuid),club_zet_wasmand(text,text,uuid) to authenticated;
-- Einde ploegscheiding.
-- Ploegregistratie: private e-mailkoppeling met vooraf ingeschreven speelsters.
create table if not exists public.club_registration (
 club_id text not null check(club_id='vrouwen'),
 email text not null check(email=lower(trim(email)) and position('@' in email)>1),
 member_id uuid not null,
 primary key(club_id,email), unique(club_id,member_id),
 foreign key(club_id,member_id) references club_members(club_id,id) on delete cascade
);
alter table public.club_registration enable row level security;
revoke all on public.club_registration from public,anon,authenticated;
grant all on public.club_registration to service_role;

create or replace function public.club_koppel_registratie() returns trigger
language plpgsql security definer set search_path=public as $$
declare doel uuid;
begin
 if new.email_confirmed_at is null then return new; end if;
 select member_id into doel from club_registration where club_id='vrouwen' and email=lower(trim(new.email));
 if doel is null then return new; end if;
 -- Een bestaande koppeling of handmatige blokkering nooit overschrijven.
 if exists(select 1 from club_members where club_id='vrouwen' and user_id=new.id and id<>doel) then return new; end if;
 update club_members set user_id=new.id where id=doel and club_id='vrouwen'
   and status='actief' and (user_id is null or user_id=new.id);
 if found then
  delete from club_role_requests where club_id='vrouwen' and user_id=new.id;
  insert into club_attendance(club_id,match_key,user_id,status)
  select club_id,match_key,new.id,status from club_member_attendance where club_id='vrouwen' and member_id=doel
  on conflict(club_id,match_key,user_id) do nothing;
  delete from club_member_attendance where club_id='vrouwen' and member_id=doel;
 end if;
 return new;
end $$;
drop trigger if exists on_club_registration on auth.users;
create trigger on_club_registration after insert or update of email,email_confirmed_at on auth.users
for each row execute function club_koppel_registratie();

create or replace function public.club_import_members(p_leden jsonb) returns integer
language plpgsql security definer set search_path=public as $$
declare r jsonb; mail text; doel uuid; gebruiker uuid; aantal integer:=0;
begin
 if jsonb_typeof(p_leden)<>'array' then raise exception 'Verwacht een ledenlijst.'; end if;
 for r in select value from jsonb_array_elements(p_leden) loop
 mail:=lower(trim(r->>'email'));
 if mail is null or position('@' in mail)<2 or coalesce(r->>'naam','')='' or coalesce(r->>'functie','') not in ('speler','coach','verantwoordelijke') then
 raise exception 'Ongeldige inschrijving.'; end if;
 select member_id into doel from club_registration where club_id='vrouwen' and email=mail;
 -- Een herhaalde import verandert geen handmatig ingestelde rechten.
 if doel is not null then continue; end if;
 select id into gebruiker from auth.users where lower(trim(email))=mail and email_confirmed_at is not null;
 if gebruiker is not null then select id into doel from club_members where club_id='vrouwen' and user_id=gebruiker; end if;
 if doel is null then
 insert into club_members(club_id,user_id,naam,functie,speelt) values('vrouwen',gebruiker,r->>'naam',r->>'functie',r->>'functie'='speler') returning id into doel;
 end if;
 insert into club_registration(club_id,email,member_id) values('vrouwen',mail,doel);
 if gebruiker is not null then delete from club_role_requests where club_id='vrouwen' and user_id=gebruiker; end if;
 aantal:=aantal+1;
 end loop;
 return aantal;
end $$;
revoke all on function public.club_import_members(jsonb),public.club_koppel_registratie() from public,anon,authenticated;
grant execute on function public.club_import_members(jsonb),public.club_koppel_registratie() to service_role;
-- Einde ploegregistratie.
-- Vrouwenprofielbeheer, ook voor ingeschreven leden zonder account.
create or replace function public.club_wijzig_lid(p_club text,p_lid uuid,p_functie text,p_speelt boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
 if not club_admin(p_club) then raise exception 'Alleen een ploegbeheerder kan functies aanpassen.'; end if;
 if p_functie is null or p_functie not in ('speler','spelercoach','coach','verantwoordelijke','supporter') or p_speelt is null then raise exception 'Ongeldige functie.'; end if;
 if exists(select 1 from club_members where club_id=p_club and id=p_lid and is_admin) and p_functie='supporter' then raise exception 'Verwijder eerst de beheerdersrol.'; end if;
 update club_members set functie=p_functie,speelt=(p_functie<>'supporter' and p_speelt) where club_id=p_club and id=p_lid;
 if not found then raise exception 'Lid niet gevonden.'; end if;
end $$;
revoke all on function public.club_wijzig_lid(text,uuid,text,boolean) from public,anon;
grant execute on function public.club_wijzig_lid(text,uuid,text,boolean) to authenticated,service_role;
-- Einde vrouwenprofielbeheer.


-- Ploegmeldingen: aparte voorkeuren en unieke jobs, nooit de mannenwachtrij.
create table if not exists public.club_push_preferences (
 club_id text not null check(club_id='vrouwen'),user_id uuid references auth.users(id) on delete cascade,
 enabled boolean not null default false,primary key(club_id,user_id)
);
create table if not exists public.club_push_jobs (
 id uuid primary key default gen_random_uuid(),club_id text not null,match_key text not null,user_id uuid references auth.users(id) on delete cascade,
 soort text not null check(soort in ('aanwezig72','aanwezig48','stemmen','stemherinnering','wasmand')),
 sent_at timestamptz,primary_attempt_at timestamptz,unique(club_id,match_key,user_id,soort),
 foreign key(club_id,match_key) references club_matches(club_id,match_key) on delete cascade
);
create table if not exists public.club_push_subscriptions (
 user_id uuid references auth.users(id) on delete cascade,endpoint text primary key,subscription jsonb not null
);
create table if not exists public.club_push_config (
 id integer primary key check(id=1),enabled boolean not null default false,allowed_user uuid references auth.users(id)
);
insert into club_push_config(id) values(1) on conflict do nothing;
do $$ declare t text;begin
 foreach t in array array['club_push_preferences','club_push_jobs','club_push_subscriptions','club_push_config'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;end $$;
create or replace function public.club_push_planning(p_nu timestamptz default now()) returns table(club_id text,match_key text,user_id uuid,soort text,tegenstander text,thuis_score integer,uit_score integer,steca_thuis boolean)
language sql stable security definer set search_path=public as $$
 with basis as (
 select m.club_id,m.match_key,l.user_id,m.aftrap,m.score_at,m.thuis_score,m.uit_score,m.thuis='STECA VROUWEN' as eigen_thuis,
 case when m.thuis='STECA VROUWEN' then m.uit else m.thuis end as tegenstander,l.speelt,
 exists(select 1 from club_attendance a where a.club_id=m.club_id and a.match_key=m.match_key and a.user_id=l.user_id) as antwoord,
 exists(select 1 from club_attendance a where a.club_id=m.club_id and a.match_key=m.match_key and a.user_id=l.user_id and a.status='aanwezig') as aanwezig,
 exists(select 1 from club_votes v where v.club_id=m.club_id and v.match_key=m.match_key and v.user_id=l.user_id) as gestemd,
 exists(select 1 from club_laundry w where w.club_id=m.club_id and w.match_key=m.match_key and w.member_id=l.id) as wasmand,
 (select j.sent_at from club_push_jobs j where j.club_id=m.club_id and j.match_key=m.match_key and j.user_id=l.user_id and j.soort='stemmen') as eerste
 from club_matches m join club_members l on l.club_id=m.club_id and l.status='actief' and l.functie<>'supporter'
 join club_push_preferences p on p.club_id=l.club_id and p.user_id=l.user_id and p.enabled
 where m.aftrap>p_nu-interval '24 hours' and m.aftrap<=p_nu+interval '72 hours'
 ), kandidaten as (
 select b.*,s.soort from basis b cross join lateral (
 select 'aanwezig72'::text soort where b.speelt and not b.antwoord and p_nu>=b.aftrap-interval '72 hours' and p_nu<b.aftrap-interval '48 hours'
 union all select 'aanwezig48' where b.speelt and not b.antwoord and p_nu>=b.aftrap-interval '48 hours' and p_nu<b.aftrap
 union all select 'wasmand' where b.wasmand and p_nu>=b.aftrap+interval '100 minutes'
 union all select 'stemmen' where b.speelt and b.aanwezig and not b.gestemd and b.thuis_score is not null and b.score_at is not null and p_nu>=greatest(b.aftrap+interval '80 minutes',b.score_at) and b.eerste is null
 union all select 'stemherinnering' where b.speelt and b.aanwezig and not b.gestemd and p_nu>=b.eerste+interval '3 hours'
 ) s
 ) select k.club_id,k.match_key,k.user_id,k.soort,k.tegenstander,k.thuis_score,k.uit_score,k.eigen_thuis from kandidaten k
 where not exists(select 1 from club_push_jobs j where j.club_id=k.club_id and j.match_key=k.match_key and j.user_id=k.user_id and j.soort=k.soort and j.sent_at is not null)
$$;
revoke all on function club_push_planning(timestamptz) from public,anon,authenticated;
grant execute on function club_push_planning(timestamptz) to service_role;
-- Einde ploegmeldingen.


-- Alleen vrouwen-testcentrum. Niet overnemen naar productie.
create or replace function public.club_testactie(p_club text,p_actie text) returns void language plpgsql security definer set search_path=public as $$
declare k text; ids uuid[]:='{}';x integer;v uuid;begin
 if p_club<>'vrouwen' or not coalesce(mag_testbadges_beheren(),false) then raise exception 'Alleen de aangewezen testbeheerder.';end if;
 if p_actie='verwijderen' then delete from club_matches where club_id=p_club and is_test;return;end if;
 if p_actie not in ('komend','gespeeld') then raise exception 'Onbekende testactie.';end if;
 update club_members set speelt=true where club_id=p_club and user_id=auth.uid() returning id into v;
 if v is null then raise exception 'Geen vrouwen-testbeheerder gekoppeld.';end if;ids:=array_append(ids,v);
 for x in 1..4 loop
 select id into v from club_members where club_id=p_club and naam='Test Speelster '||x and user_id is null limit 1;
 if v is null then insert into club_members(club_id,naam,functie,speelt) values(p_club,'Test Speelster '||x,'speler',true) returning id into v;end if;
 ids:=array_append(ids,v);end loop;
 k:='vrouwen-test-'||gen_random_uuid()::text;
 insert into club_matches(club_id,match_key,seizoen,aftrap,thuis,uit,thuis_score,uit_score,score_at,is_test)
 values(p_club,k,'2026-2027',now()+case when p_actie='gespeeld' then interval '-90 minutes' else interval '70 hours' end,'STECA VROUWEN','TEST Tegenstander',case when p_actie='gespeeld' then 3 end,case when p_actie='gespeeld' then 1 end,case when p_actie='gespeeld' then now() end,true);
 if p_actie='gespeeld' then insert into club_attendance values(p_club,k,auth.uid(),'aanwezig');end if;
 insert into club_lineups values(p_club,k,jsonb_build_object('GK',ids[1],'LB',ids[2],'RB',ids[3],'LW',ids[4],'RW',ids[5]),'[]',1);
 if p_actie='gespeeld' then insert into club_reports values(p_club,k,jsonb_build_array(jsonb_build_object('id',ids[2],'goals',3,'assists',0,'geel',0,'rood',0),jsonb_build_object('id',ids[3],'goals',0,'assists',2,'geel',2,'rood',1)),'Fictief testverslag, alleen zichtbaar in de testapp.');end if;
end $$;
revoke all on function club_testactie(text,text) from public,anon;
grant execute on function club_testactie(text,text) to authenticated;

create or replace function public.club_claim_push(p_id uuid) returns boolean language plpgsql security definer set search_path=public as $$
begin
 update club_push_jobs set primary_attempt_at=now() where id=p_id and sent_at is null and (primary_attempt_at is null or primary_attempt_at<now()-interval '5 minutes');return found;
end $$;
revoke all on function club_claim_push(uuid) from public,anon,authenticated;
grant execute on function club_claim_push(uuid) to service_role;

-- Twizzit: afgeschermde worker, openbare broncache en adminaanvragen.
create table if not exists public.vrouwen_sync (
 id boolean primary key default true check(id), token_hash text not null,
 data jsonb, laatste_succes timestamptz, aangevraagd timestamptz,
 gestart timestamptz, afgerond timestamptz, run_id uuid, fout text
);
alter table vrouwen_sync enable row level security;
revoke all on vrouwen_sync from anon,authenticated;
create or replace function public.vrouwen_bron() returns jsonb language sql stable security definer set search_path=public as $$ select data from vrouwen_sync where id $$;
grant execute on function vrouwen_bron() to anon,authenticated;
create or replace function public.club_twizzit(p_club text,p_start boolean default false) returns jsonb language plpgsql security definer set search_path=public as $$
declare r vrouwen_sync;begin
 if p_club<>'vrouwen' or not club_admin(p_club) then raise exception 'Alleen een vrouwenadmin kan Twizzit bijwerken.';end if;
 select * into r from vrouwen_sync where id for update;
 if p_start and (r.aangevraagd is null or r.afgerond>=r.aangevraagd) and (r.gestart is null or r.afgerond>=r.gestart or r.gestart<now()-interval '10 minutes') then
 update vrouwen_sync set aangevraagd=now(),fout=null where id returning * into r;
 end if;
 return jsonb_build_object('laatste_succes',r.laatste_succes,'wacht',r.aangevraagd is not null and (r.afgerond is null or r.aangevraagd>r.afgerond),'bezig',r.gestart>coalesce(r.afgerond,'epoch') and r.gestart>now()-interval '10 minutes','fout',r.fout);
end $$;
revoke all on function club_twizzit(text,boolean) from public;
grant execute on function club_twizzit(text,boolean) to authenticated;
create or replace function public.vrouwen_sync_worker(p_token text,p_actie text,p_id uuid default null,p_data jsonb default null) returns jsonb language plpgsql security definer set search_path=public,extensions as $$
declare r vrouwen_sync; lokaal timestamp:=now() at time zone 'Europe/Brussels'; due boolean; m jsonb;begin
 select * into r from vrouwen_sync where id for update;
 if r.token_hash is null or encode(digest(p_token,'sha256'),'hex') is distinct from r.token_hash then raise exception 'Geen toegang.';end if;
 if p_actie='claim' then
 if r.gestart>coalesce(r.afgerond,'epoch') and r.gestart>now()-interval '10 minutes' then return null;end if;
 due:=r.laatste_succes is null or coalesce(r.aangevraagd>coalesce(r.afgerond,'epoch'),false);
 -- Laatste dinsdag/woensdag/donderdag om 22u, inclusief gemiste scheduler-runs.
 due:=due or exists(select 1 from generate_series(lokaal::date-6,lokaal::date,interval '1 day') d where extract(isodow from d) in(2,3,4) and d+interval '22 hours'<=lokaal and (d+interval '22 hours') at time zone 'Europe/Brussels'>coalesce(r.laatste_succes,'epoch'));
 due:=due or exists(select 1 from club_matches where club_id='vrouwen' and not is_test and aftrap+interval '2 hours'<=now() and aftrap+interval '2 hours'>coalesce(r.laatste_succes,'epoch'));
 if not due or (r.fout is not null and r.afgerond>now()-interval '10 minutes') then return null;end if;
 update vrouwen_sync set gestart=now(),run_id=gen_random_uuid(),fout=null where id returning * into r;
 return jsonb_build_object('id',r.run_id);
 end if;
 if p_id is distinct from r.run_id or r.afgerond>=r.gestart then raise exception 'Verlopen update.';end if;
 if p_actie='fout' then update vrouwen_sync set afgerond=now(),fout='Twizzit ophalen mislukt. De vorige gegevens blijven behouden.' where id;return '{}'::jsonb;end if;
 if p_actie<>'klaar' or jsonb_typeof(p_data->'wedstrijden') is distinct from 'array' or jsonb_array_length(p_data->'wedstrijden')=0 or jsonb_typeof(p_data->'klassementen') is distinct from 'array' or jsonb_array_length(p_data->'klassementen')=0 then raise exception 'Ongeldige Twizzit-gegevens.';end if;
 perform club_import_matches(p_data);
 -- Een handmatig ingevuld matchverslag blijft leidend; openbare uitslagen vullen de overige matchen aan.
 for m in select * from jsonb_array_elements(p_data->'wedstrijden') loop
 if m->'score'->>0 is not null then
 update club_matches set thuis_score=(m->'score'->>0)::int,uit_score=(m->'score'->>1)::int,score_at=coalesce(score_at,now()) where club_id='vrouwen' and match_key='twizzit-'||(m->>'id') and not exists(select 1 from club_reports v where v.club_id='vrouwen' and v.match_key='twizzit-'||(m->>'id'));
 end if;
 end loop;
 update vrouwen_sync set data=p_data,laatste_succes=gestart,afgerond=now(),fout=null where id;
 return '{}'::jsonb;
end $$;
revoke all on function vrouwen_sync_worker(text,text,uuid,jsonb) from public;
grant execute on function vrouwen_sync_worker(text,text,uuid,jsonb) to anon;

create table if not exists public.club_berichten(id uuid primary key default gen_random_uuid(),club_id text not null,tekst text not null check(length(btrim(tekst)) between 1 and 140),actief boolean not null default true,auteur uuid not null default auth.uid(),created_at timestamptz not null default now(),updated_at timestamptz not null default now());
alter table club_berichten enable row level security;
revoke all on club_berichten from anon,authenticated;
create or replace function public.club_lichtkrant(p_club text) returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'tekst',b.tekst,'actief',b.actief,'auteur',coalesce(m.naam,'Staf'),'updated_at',b.updated_at) order by b.created_at),'[]') from club_berichten b left join club_members m on m.club_id=b.club_id and m.user_id=b.auteur where b.club_id=p_club and (b.actief or club_staf(p_club))
$$;
create or replace function public.club_bewaar_bericht(p_club text,p_id uuid default null,p_tekst text default '',p_actief boolean default true,p_verwijder boolean default false) returns void language plpgsql security definer set search_path=public as $$
begin
 if not coalesce(club_staf(p_club),false) then raise exception 'Alleen coaches, verantwoordelijken en admins kunnen boodschappen beheren.';end if;
 if p_id is null then insert into club_berichten(club_id,tekst) values(p_club,btrim(p_tekst));
 elsif p_verwijder then delete from club_berichten where club_id=p_club and id=p_id;if not found then raise exception 'Boodschap niet gevonden.';end if;
 else update club_berichten set tekst=btrim(p_tekst),actief=p_actief,updated_at=now() where club_id=p_club and id=p_id;if not found then raise exception 'Boodschap niet gevonden.';end if;end if;
end $$;
revoke all on function club_bewaar_bericht(text,uuid,text,boolean,boolean) from public;
grant execute on function club_bewaar_bericht(text,uuid,text,boolean,boolean) to authenticated;
grant execute on function club_lichtkrant(text) to anon,authenticated;

-- Rechtstreekse Twizzit-start: alleen de database controleert de planning.
alter table public.vrouwen_sync add column if not exists dispatch_at timestamptz;
create or replace function public.vrouwen_dispatch(p_force boolean default false) returns boolean
language plpgsql security definer set search_path=public,extensions as $$
declare r vrouwen_sync; lokaal timestamp:=now() at time zone 'Europe/Brussels'; due boolean; sleutel text;
begin
 select * into r from vrouwen_sync where id for update;
 if not found then return false;end if;
 if r.gestart>coalesce(r.afgerond,'epoch') and r.gestart>now()-interval '10 minutes' then return false;end if;
 if r.dispatch_at>coalesce(r.afgerond,'epoch') and r.dispatch_at>now()-interval '10 minutes' then return false;end if;
 due:=p_force or r.laatste_succes is null or coalesce(r.aangevraagd>coalesce(r.afgerond,'epoch'),false);
 due:=due or exists(select 1 from generate_series(lokaal::date-6,lokaal::date,interval '1 day') d where extract(isodow from d) in(2,3,4) and d+interval '22 hours'<=lokaal and (d+interval '22 hours') at time zone 'Europe/Brussels'>coalesce(r.laatste_succes,'epoch'));
 due:=due or exists(select 1 from club_matches where club_id='vrouwen' and not is_test and aftrap+interval '2 hours'<=now() and aftrap+interval '2 hours'>coalesce(r.laatste_succes,'epoch'));
 if not due or (r.fout is not null and r.afgerond>now()-interval '10 minutes' and not p_force) then return false;end if;
 select decrypted_secret into sleutel from vault.decrypted_secrets where name='twizzit_github_token' limit 1;
 if sleutel is null then raise exception 'De rechtstreekse updatekoppeling is nog niet ingesteld.';end if;
 perform net.http_post(url:='https://api.github.com/repos/arthurpepermans/steca-competitie-test/actions/workflows/sync-vrouwen.yml/dispatches',
 headers:=jsonb_build_object('Authorization','Bearer '||sleutel,'Accept','application/vnd.github+json','Content-Type','application/json','User-Agent','Steca-Twizzit'),
 body:='{"ref":"main"}'::jsonb,timeout_milliseconds:=15000);
 update vrouwen_sync set dispatch_at=now(),aangevraagd=case when p_force then now() else aangevraagd end,fout=null where id;
 return true;
end $$;
revoke all on function public.vrouwen_dispatch(boolean) from public,anon,authenticated;
create or replace function public.club_twizzit(p_club text,p_start boolean default false) returns jsonb language plpgsql security definer set search_path=public as $$
declare r vrouwen_sync;begin
 if p_club<>'vrouwen' or not club_admin(p_club) then raise exception 'Alleen een vrouwenadmin kan Twizzit bijwerken.';end if;
 if p_start then perform vrouwen_dispatch(true);end if;
 select * into r from vrouwen_sync where id;
 return jsonb_build_object('laatste_succes',r.laatste_succes,'wacht',r.dispatch_at>coalesce(r.afgerond,'epoch') and r.dispatch_at>now()-interval '10 minutes','bezig',r.gestart>coalesce(r.afgerond,'epoch') and r.gestart>now()-interval '10 minutes','fout',r.fout);
end $$;
-- Idempotent: vervangt dezelfde job. De GitHub-workflow heeft geen kwartiercron meer.
select cron.schedule('steca-twizzit-planning','* * * * *','select public.vrouwen_dispatch(false)');
-- Einde rechtstreekse Twizzit-start.
