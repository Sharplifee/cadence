-- Cadence — standalone schema. Own project, own tables, no shared references.

create table if not exists cadence_sessions (
  id                uuid primary key,
  started_at        timestamptz not null,
  duration_seconds  double precision not null,
  talk_share        real,
  interruptions     integer default 0,
  correction_rate   real,
  created_at        timestamptz not null default now()
);

-- 500 ms frames. ~7,200 rows per hour of conversation.
create table if not exists cadence_frames (
  id             bigserial primary key,
  session_id     uuid not null references cadence_sessions(id) on delete cascade,
  t              double precision not null,
  speaker        text not null check (speaker in ('me','them','silence','overlap')),
  dbfs           real,
  f0             real,
  syllable_rate  real,
  centroid       real
);
create index if not exists cadence_frames_session_t on cadence_frames (session_id, t);

create table if not exists cadence_cues (
  id                bigserial primary key,
  session_id        uuid not null references cadence_sessions(id) on delete cascade,
  t                 double precision not null,
  code              smallint not null,
  label             text,
  rate_ratio        real,
  loudness_delta    real,
  pitch_delta       real,
  turn_length_ratio real,
  talk_share        real,
  interrupt_rate    real,
  corrected         boolean
);
create index if not exists cadence_cues_session on cadence_cues (session_id, t);

alter table cadence_sessions enable row level security;
alter table cadence_frames   enable row level security;
alter table cadence_cues     enable row level security;

-- Single-user app: service role writes, nothing else reads.
create policy cadence_sessions_service on cadence_sessions
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create policy cadence_frames_service on cadence_frames
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');
create policy cadence_cues_service on cadence_cues
  for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

-- Week-over-week: is the coaching actually landing?
create or replace view cadence_weekly as
select
  date_trunc('week', started_at)              as week,
  count(*)                                    as sessions,
  round(avg(talk_share)::numeric, 3)          as avg_talk_share,
  round(avg(correction_rate)::numeric, 3)     as avg_correction_rate,
  sum(interruptions)                          as interruptions,
  round((sum(interruptions) / nullif(sum(duration_seconds) / 3600, 0))::numeric, 2)
                                              as interruptions_per_hour
from cadence_sessions
group by 1
order by 1 desc;
