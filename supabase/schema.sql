-- PengPal: run this once in Supabase (SQL Editor > New query > paste > Run).
-- Safe to run again: it only creates what is missing and replaces the functions.

create table if not exists public.sessions (
  session_id     text primary key,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  stage          text not null,
  traveler_type  text,
  prefer_female  boolean not null default false,
  city           text,
  country        text,
  language       text,
  interests      jsonb not null default '[]'::jsonb,
  host_id        text,
  booking_date   text,
  duration       text,
  party          int,
  commit_choice  text,
  commit_month   text,
  commit_city    text,
  commit_reason  text,
  review_stars   int,
  review_nps     int,
  review_tags    jsonb not null default '[]'::jsonb,
  review_comment text,
  -- Hand-matching request (the "match request" screen)
  contact_method text,
  contact        text,
  trip_start     text,
  trip_end       text,
  dates_flexible boolean not null default false,
  lead_at        timestamptz,
  lead_status    text not null default 'new'
);

-- If you ran an earlier version of this file, these add the new columns. Safe to repeat.
alter table public.sessions add column if not exists contact_method text;
alter table public.sessions add column if not exists contact        text;
alter table public.sessions add column if not exists trip_start     text;
alter table public.sessions add column if not exists trip_end       text;
alter table public.sessions add column if not exists dates_flexible boolean not null default false;
alter table public.sessions add column if not exists lead_at        timestamptz;
alter table public.sessions add column if not exists lead_status    text not null default 'new';

-- Lock the table: with row level security on and no policies, the public (anon) key
-- can neither read nor write it directly. Data goes in only through save_session() below.
alter table public.sessions enable row level security;
revoke all on public.sessions from anon, authenticated;

-- Helpers that clean what the browser sends. Not callable from the browser.
create or replace function public._clean_text(v text, max_len int)
returns text language sql immutable as
$$ select left(nullif(btrim(v), ''), max_len) $$;

create or replace function public._clean_int(j jsonb, lo int, hi int)
returns int language sql immutable as
$$
  select case
    when jsonb_typeof(j) = 'number'
     and (j #>> '{}')::numeric = floor((j #>> '{}')::numeric)
     and (j #>> '{}')::numeric between lo and hi
    then (j #>> '{}')::int
  end
$$;

create or replace function public._clean_list(j jsonb)
returns jsonb language sql immutable as
$$
  select coalesce(jsonb_agg(left(v, 50)), '[]'::jsonb)
  from (
    select v from jsonb_array_elements_text(
      case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end
    ) as v limit 20
  ) t
$$;

-- The one entry point the front end uses. One row per visitor, overwritten on each save.
create or replace function public.save_session(p jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  sid  text  := p ->> 'sessionId';
  stg  text  := p ->> 'stage';
  prof jsonb := case when jsonb_typeof(p -> 'profile') = 'object' then p -> 'profile' else '{}'::jsonb end;
  book jsonb := case when jsonb_typeof(p -> 'booking') = 'object' then p -> 'booking' else '{}'::jsonb end;
  cmt  jsonb := case when jsonb_typeof(p -> 'commit')  = 'object' then p -> 'commit'  else '{}'::jsonb end;
  rev  jsonb := case when jsonb_typeof(p -> 'review')  = 'object' then p -> 'review'  else '{}'::jsonb end;
  ld   jsonb := case when jsonb_typeof(p -> 'lead')    = 'object' then p -> 'lead'    else '{}'::jsonb end;
  l_contact text := _clean_text(ld ->> 'contact', 100);
begin
  if sid is null or sid !~ '^[A-Za-z0-9_-]{8,64}$' then
    raise exception 'invalid sessionId';
  end if;
  if stg is null or stg not in ('request','hosts','profile','intro','book','commit','prep','trip','review','done') then
    raise exception 'invalid stage';
  end if;

  insert into public.sessions (
    session_id, stage, traveler_type, prefer_female, city, country, language, interests,
    host_id, booking_date, duration, party, commit_choice, commit_month, commit_city,
    commit_reason, review_stars, review_nps, review_tags, review_comment,
    contact_method, contact, trip_start, trip_end, dates_flexible, lead_at
  ) values (
    sid, stg,
    _clean_text(prof ->> 'travelerType', 30),
    coalesce((prof ->> 'preferFemale') = 'true', false),
    _clean_text(prof ->> 'city', 30),
    _clean_text(prof ->> 'country', 30),
    _clean_text(prof ->> 'language', 40),
    _clean_list(prof -> 'interests'),
    _clean_text(p ->> 'hostId', 30),
    _clean_text(book ->> 'date', 10),
    _clean_text(book ->> 'duration', 20),
    _clean_int(book -> 'party', 1, 4),
    _clean_text(cmt ->> 'choice', 20),
    _clean_text(cmt ->> 'month', 7),
    _clean_text(cmt ->> 'city', 30),
    _clean_text(cmt ->> 'reason', 1000),
    _clean_int(rev -> 'stars', 1, 5),
    _clean_int(rev -> 'nps', 0, 10),
    _clean_list(rev -> 'tags'),
    _clean_text(rev ->> 'comment', 1000),
    case when l_contact is not null and ld ->> 'method' in ('email','wechat','whatsapp') then ld ->> 'method' end,
    l_contact,
    case when ld ->> 'start' ~ '^\d{4}-\d{2}-\d{2}$' then ld ->> 'start' end,
    case when ld ->> 'end'   ~ '^\d{4}-\d{2}-\d{2}$' then ld ->> 'end'   end,
    coalesce((ld ->> 'flexible') = 'true', false),
    case when l_contact is not null then now() end
  )
  on conflict (session_id) do update set
    updated_at     = now(),
    stage          = excluded.stage,
    traveler_type  = excluded.traveler_type,
    prefer_female  = excluded.prefer_female,
    city           = excluded.city,
    country        = excluded.country,
    language       = excluded.language,
    interests      = excluded.interests,
    host_id        = excluded.host_id,
    booking_date   = excluded.booking_date,
    duration       = excluded.duration,
    party          = excluded.party,
    commit_choice  = excluded.commit_choice,
    commit_month   = excluded.commit_month,
    commit_city    = excluded.commit_city,
    commit_reason  = excluded.commit_reason,
    review_stars   = excluded.review_stars,
    review_nps     = excluded.review_nps,
    review_tags    = excluded.review_tags,
    review_comment = excluded.review_comment,
    -- Lead fields only change when this save carries a contact, so later saves
    -- (without one) never wipe a request that was already sent.
    contact_method = case when excluded.contact is not null then excluded.contact_method else sessions.contact_method end,
    contact        = case when excluded.contact is not null then excluded.contact        else sessions.contact        end,
    trip_start     = case when excluded.contact is not null then excluded.trip_start     else sessions.trip_start     end,
    trip_end       = case when excluded.contact is not null then excluded.trip_end       else sessions.trip_end       end,
    dates_flexible = case when excluded.contact is not null then excluded.dates_flexible else sessions.dates_flexible end,
    lead_at        = coalesce(sessions.lead_at, excluded.lead_at);
end;
$$;

-- Only save_session is public. Everything else stays private.
revoke all on function public._clean_text(text, int)       from public, anon, authenticated;
revoke all on function public._clean_int(jsonb, int, int)  from public, anon, authenticated;
revoke all on function public._clean_list(jsonb)           from public, anon, authenticated;
revoke all on function public.save_session(jsonb)          from public;
grant execute on function public.save_session(jsonb) to anon, authenticated;

-- Your matching worklist: everyone who sent a request, newest first, with the date by which
-- you promised to reply. Open it in Table Editor > Views > leads. To track progress, change
-- lead_status on the row in the sessions table (new / contacted / matched / closed).
create or replace view public.leads with (security_invoker = true) as
select
  lead_at,
  lead_at + interval '3 days' as reply_by,
  lead_status,
  contact_method,
  contact,
  trip_start,
  trip_end,
  dates_flexible,
  traveler_type,
  prefer_female,
  city,
  country,
  language,
  interests,
  session_id
from public.sessions
where contact is not null
order by lead_at desc;

revoke all on public.leads from public, anon, authenticated;
