-- ═══════════════════════════════════════════════════════════════════
--  TRADMATHS — mode « salle » : base de données Supabase (schéma version 1)
--  Conçu par Tom Rougeaud — code rédigé avec l’aide de Claude (Anthropic, Opus 5.5).
--  Licence CC BY-NC 4.0.
--
--  À coller UNE FOIS dans Supabase › SQL Editor › New query, puis « Run ».
--  Le script peut être relancé sans risque (il ne casse rien de Flash Maths :
--  toutes les tables et fonctions de TradMaths commencent par « tm_ »).
--
--  Ce que la base conserve, et pour combien de temps :
--   • tm_rooms   : les salles ouvertes (code à 4 caractères).
--   • tm_players : le prénom ou pseudo de chaque élève connecté et sa langue (30 au plus).
--   • tm_items   : les phrases traduites diffusées pendant le cours (50 dernières au plus).
--  Tout est supprimé quand le prof ferme la salle, et au plus tard 4 h après
--  la dernière activité. Aucun nom de famille, e-mail ou adresse IP n’est enregistré.
--
--  Sécurité : les tables sont fermées (RLS sans aucune règle d’accès).
--  Les pages agissent uniquement par les fonctions ci-dessous.
--  Seul l’appareil du prof (qui détient le jeton secret de la salle) peut
--  écrire une traduction ; les téléphones des élèves ne peuvent que lire
--  la traduction dans LEUR langue.
-- ═══════════════════════════════════════════════════════════════════

-- ─── Tables ───────────────────────────────────────────────────────
create table if not exists public.tm_rooms (
  code        text primary key check (code ~ '^[A-HJ-NP-Z2-9]{4}$'),
  host_token  uuid not null,
  status      text not null default 'open' check (status in ('open','ended')),
  seq         bigint not null default 0,          -- compteur des diffusions
  created_at  timestamptz not null default now(),
  last_seen   timestamptz not null default now()
);

create table if not exists public.tm_players (
  id         uuid primary key default gen_random_uuid(),
  room_code  text not null references public.tm_rooms(code) on delete cascade,
  pseudo     text not null check (char_length(pseudo) between 2 and 16),
  lang       text not null check (lang ~ '^[a-z]{2,5}$'),
  joined_at  timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create unique index if not exists tm_players_pseudo_uq on public.tm_players (room_code, lower(pseudo));
create index if not exists tm_players_room_idx on public.tm_players (room_code);

create table if not exists public.tm_items (
  room_code  text not null references public.tm_rooms(code) on delete cascade,
  item_id    text not null check (item_id ~ '^[a-z0-9-]{1,40}$'),
  seq        bigint not null,
  fr         text not null check (char_length(fr) <= 2000),
  tr         jsonb not null default '{}'::jsonb check (octet_length(tr::text) < 80000),
  at         timestamptz not null default now(),
  primary key (room_code, item_id)
);
create index if not exists tm_items_seq_idx on public.tm_items (room_code, seq);

alter table public.tm_rooms   enable row level security;
alter table public.tm_players enable row level security;
alter table public.tm_items   enable row level security;
revoke all on public.tm_rooms, public.tm_players, public.tm_items from anon, authenticated;

-- ─── Outils internes ──────────────────────────────────────────────
-- Ménage : salles inactives depuis 4 h (joueurs et phrases partent avec elles)
create or replace function public.tm_purge() returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from tm_rooms where last_seen < now() - interval '4 hours';
end $$;

-- Nettoie un pseudo : retire les caractères spéciaux, réduit les espaces
create or replace function public.tm_clean_pseudo(p text) returns text
language sql immutable as $$
  select btrim(regexp_replace(regexp_replace(coalesce(p,''), '[<>"''`{}\\[:cntrl:]]', '', 'g'), '\s+', ' ', 'g'))
$$;

-- ─── Diagnostic (bouton « Tester la connexion ») ──────────────────
create or replace function public.tm_ping() returns json
language plpgsql security definer set search_path = public as $$
begin
  return json_build_object('ok', true, 'version', 1,
    'rooms', (select count(*) from tm_rooms where last_seen > now() - interval '10 minutes'));
end $$;

-- ─── Côté prof ────────────────────────────────────────────────────
-- Ouvre une salle : renvoie le code (à afficher) et le jeton (secret, gardé par le prof)
create or replace function public.tm_create_room() returns json
language plpgsql security definer set search_path = public as $$
declare v_code text; v_tok uuid := gen_random_uuid(); i int := 0;
        abc constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
begin
  perform tm_purge();
  if (select count(*) from tm_rooms) >= 3000 then
    return json_build_object('ok', false, 'err', 'too_many_rooms');
  end if;
  loop
    i := i + 1;
    v_code := '';
    for k in 1..4 loop
      v_code := v_code || substr(abc, 1 + floor(random() * length(abc))::int, 1);
    end loop;
    begin
      insert into tm_rooms(code, host_token) values (v_code, v_tok);
      exit;
    exception when unique_violation then
      if i > 200 then return json_build_object('ok', false, 'err', 'no_code'); end if;
    end;
  end loop;
  return json_build_object('ok', true, 'code', v_code, 'token', v_tok);
end $$;

-- Battement de cœur du prof : garde la salle en vie et renvoie les élèves présents (pseudo + langue)
create or replace function public.tm_host_ping(p_code text, p_token uuid) returns json
language plpgsql security definer set search_path = public as $$
declare r tm_rooms;
begin
  update tm_rooms set last_seen = now()
   where code = upper(p_code) and host_token = p_token and status = 'open'
  returning * into r;
  if not found then return json_build_object('ok', false, 'err', 'not_found'); end if;
  return json_build_object('ok', true, 'seq', r.seq,
    'players', coalesce((select json_agg(json_build_object('id', id, 'p', pseudo, 'l', lang) order by joined_at)
                         from tm_players where room_code = r.code and last_seen > now() - interval '2 minutes'), '[]'::json));
end $$;

-- Diffuse (ou met à jour) une phrase traduite. p_tr = {"ta":"…","ps":"…"}
create or replace function public.tm_push(p_code text, p_token uuid, p_item text, p_fr text, p_tr jsonb) returns json
language plpgsql security definer set search_path = public as $$
declare r tm_rooms; v_tr jsonb := '{}'::jsonb; k text; v jsonb;
begin
  if p_item !~ '^[a-z0-9-]{1,40}$' or char_length(coalesce(p_fr,'')) > 2000 or char_length(coalesce(p_fr,'')) = 0 then
    return json_build_object('ok', false, 'err', 'invalid');
  end if;
  -- ne garde que des paires « code langue → texte » raisonnables
  if jsonb_typeof(p_tr) = 'object' then
    for k, v in select * from jsonb_each(p_tr) loop
      if k ~ '^[a-z]{2,5}$' and jsonb_typeof(v) = 'string' and char_length(v #>> '{}') <= 4000 then
        v_tr := v_tr || jsonb_build_object(k, v);
      end if;
    end loop;
  end if;
  update tm_rooms set seq = seq + 1, last_seen = now()
   where code = upper(p_code) and host_token = p_token and status = 'open'
  returning * into r;
  if not found then return json_build_object('ok', false, 'err', 'not_found'); end if;
  insert into tm_items(room_code, item_id, seq, fr, tr) values (r.code, p_item, r.seq, p_fr, v_tr)
  on conflict (room_code, item_id) do update set seq = excluded.seq, fr = excluded.fr, tr = excluded.tr, at = now();
  -- 50 phrases au plus par salle
  delete from tm_items where room_code = r.code and seq <= r.seq - 50;
  return json_build_object('ok', true, 'seq', r.seq);
end $$;

-- Retire un élève de la salle
create or replace function public.tm_kick(p_code text, p_token uuid, p_player uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from tm_rooms where code = upper(p_code) and host_token = p_token) then
    return json_build_object('ok', false, 'err', 'not_found');
  end if;
  delete from tm_players where id = p_player and room_code = upper(p_code);
  return json_build_object('ok', true);
end $$;

-- Ferme la salle : tout est effacé (élèves et phrases)
create or replace function public.tm_close_room(p_code text, p_token uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  delete from tm_rooms where code = upper(p_code) and host_token = p_token;
  return json_build_object('ok', found);
end $$;

-- ─── Côté élève ───────────────────────────────────────────────────
-- Rejoindre (ou revenir après une coupure, ou changer de langue)
create or replace function public.tm_join(p_code text, p_pseudo text, p_lang text, p_player uuid default null) returns json
language plpgsql security definer set search_path = public as $$
declare r tm_rooms; v_ps text := tm_clean_pseudo(p_pseudo); v_n int; v_id uuid;
begin
  if char_length(v_ps) < 2 or char_length(v_ps) > 16 then
    return json_build_object('ok', false, 'err', 'pseudo_invalid');
  end if;
  if coalesce(p_lang,'') !~ '^[a-z]{2,5}$' then
    return json_build_object('ok', false, 'err', 'lang_invalid');
  end if;
  select * into r from tm_rooms where code = upper(p_code) for update;
  if not found or r.last_seen < now() - interval '4 hours' or r.status = 'ended' then
    return json_build_object('ok', false, 'err', 'not_found');
  end if;
  -- même élève : sa place est conservée (pseudo et langue mis à jour)
  if p_player is not null and exists (select 1 from tm_players where id = p_player and room_code = r.code) then
    if exists (select 1 from tm_players where room_code = r.code and lower(pseudo) = lower(v_ps) and id <> p_player
               and last_seen > now() - interval '2 minutes') then
      return json_build_object('ok', false, 'err', 'pseudo_taken');
    end if;
    delete from tm_players where room_code = r.code and lower(pseudo) = lower(v_ps) and id <> p_player;
    update tm_players set pseudo = v_ps, lang = p_lang, last_seen = now() where id = p_player;
    return json_build_object('ok', true, 'id', p_player, 'pseudo', v_ps, 'code', r.code);
  end if;
  -- places libérées par les élèves partis sans prévenir
  delete from tm_players where room_code = r.code and last_seen < now() - interval '2 minutes';
  select count(*) into v_n from tm_players where room_code = r.code;
  if v_n >= 30 then return json_build_object('ok', false, 'err', 'full'); end if;
  if exists (select 1 from tm_players where room_code = r.code and lower(pseudo) = lower(v_ps)) then
    return json_build_object('ok', false, 'err', 'pseudo_taken');
  end if;
  v_id := coalesce(p_player, gen_random_uuid());
  insert into tm_players(id, room_code, pseudo, lang) values (v_id, r.code, v_ps, p_lang);
  return json_build_object('ok', true, 'id', v_id, 'pseudo', v_ps, 'code', r.code);
end $$;

-- Lire les nouvelles phrases, uniquement dans la langue de l’élève (sert aussi de battement de cœur)
create or replace function public.tm_pull(p_player uuid, p_since bigint default 0) returns json
language plpgsql security definer set search_path = public as $$
declare pl tm_players; r tm_rooms;
begin
  update tm_players set last_seen = now() where id = p_player returning * into pl;
  if not found then return json_build_object('ok', false, 'err', 'gone'); end if;
  select * into r from tm_rooms where code = pl.room_code;
  if not found or r.status = 'ended' or r.last_seen < now() - interval '4 hours' then
    return json_build_object('ok', false, 'err', 'ended');
  end if;
  return json_build_object('ok', true, 'seq', r.seq, 'lang', pl.lang,
    'items', coalesce((select json_agg(x order by x.s) from (
        select item_id as id, seq as s, fr, tr ->> pl.lang as t
          from tm_items where room_code = r.code and seq > coalesce(p_since, 0)
         order by seq desc limit 30) x), '[]'::json));
end $$;

create or replace function public.tm_leave(p_player uuid) returns json
language plpgsql security definer set search_path = public as $$
begin
  delete from tm_players where id = p_player;
  return json_build_object('ok', true);
end $$;

-- ─── Droits : seules les fonctions publiques sont appelables ──────
revoke execute on function
  public.tm_purge(), public.tm_clean_pseudo(text), public.tm_ping(), public.tm_create_room(),
  public.tm_host_ping(text, uuid), public.tm_push(text, uuid, text, text, jsonb),
  public.tm_kick(text, uuid, uuid), public.tm_close_room(text, uuid),
  public.tm_join(text, text, text, uuid), public.tm_pull(uuid, bigint), public.tm_leave(uuid)
from public, anon, authenticated;
grant execute on function
  public.tm_ping(), public.tm_create_room(),
  public.tm_host_ping(text, uuid), public.tm_push(text, uuid, text, text, jsonb),
  public.tm_kick(text, uuid, uuid), public.tm_close_room(text, uuid),
  public.tm_join(text, text, text, uuid), public.tm_pull(uuid, bigint), public.tm_leave(uuid)
to anon, authenticated;

-- Vérification : doit afficher {"ok" : true, "version" : 1, ...}
select public.tm_ping();
