-- Mataki prospecting map status extension.
-- Apply after the initial schema and map fields migrations.

alter table public.buildings
  alter column prospecting_status set default 'unvisited';

alter table public.buildings
  drop constraint if exists buildings_prospecting_status_check;

alter table public.buildings
  add constraint buildings_prospecting_status_check
  check (prospecting_status in ('unvisited', 'visited', 'potential', 'follow_up', 'active_client', 'not_fit'));

comment on column public.buildings.prospecting_status is
  'Prospecting state displayed on the map. Unvisited is distinct from a qualified potential client.';
