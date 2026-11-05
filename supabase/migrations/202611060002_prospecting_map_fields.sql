-- Mataki prospecting map fields.
-- Apply after 202611060001_initial_schema.sql.

alter table public.buildings
  add column if not exists osm_way_id bigint,
  add column if not exists osm_name text,
  add column if not exists osm_tags jsonb,
  add column if not exists priority text
    check (priority is null or priority in ('High', 'Medium', 'Low')),
  add column if not exists quote_status text not null default 'not_started'
    check (quote_status in ('not_started', 'to_prepare', 'sent', 'accepted', 'declined')),
  add column if not exists racking_estimate text,
  add column if not exists visit_date date,
  add column if not exists follow_up_date date;

create unique index if not exists buildings_org_osm_way_unique
  on public.buildings (organization_id, osm_way_id)
  where osm_way_id is not null;

comment on column public.buildings.osm_way_id is
  'OpenStreetMap way identifier used to reconnect a prospect record to its building footprint.';
comment on column public.buildings.osm_tags is
  'OpenStreetMap tags captured for this building at the time it was recorded.';
comment on column public.buildings.priority is
  'Prospecting priority: High, Medium or Low.';
comment on column public.buildings.quote_status is
  'Quote workflow status associated with this prospecting record.';
