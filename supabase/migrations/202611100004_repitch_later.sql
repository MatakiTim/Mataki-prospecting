-- Mataki: Re-pitch Later workflow
-- Apply after migrations 001, 002 and 003 in Supabase SQL Editor.

alter table public.buildings
  add column if not exists first_contact_date date,
  add column if not exists declined_date date,
  add column if not exists decline_reason text,
  add column if not exists repitch_date date;

alter table public.buildings
  drop constraint if exists buildings_prospecting_status_check;

alter table public.buildings
  add constraint buildings_prospecting_status_check
  check (prospecting_status in (
    'unvisited',
    'visited',
    'potential',
    'follow_up',
    'repitch_later',
    'active_client',
    'not_fit'
  ));

create index if not exists buildings_org_repitch_date_idx
  on public.buildings (organization_id, repitch_date)
  where prospecting_status = 'repitch_later' and repitch_date is not null;

-- Enforce the 12-month re-pitch interval in the database as well as the UI.
-- The date is calculated from the date the prospect declined, not first contact.
create or replace function public.set_building_repitch_schedule()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.prospecting_status = 'repitch_later' then
    if new.declined_date is null then
      new.declined_date := current_date;
    end if;

    new.repitch_date := (new.declined_date + interval '12 months')::date;
  end if;

  return new;
end;
$$;

drop trigger if exists buildings_set_repitch_schedule on public.buildings;

create trigger buildings_set_repitch_schedule
before insert or update of prospecting_status, declined_date
on public.buildings
for each row
execute function public.set_building_repitch_schedule();

comment on column public.buildings.first_contact_date is
  'Date Mataki first contacted this prospect.';
comment on column public.buildings.declined_date is
  'Date the prospect declined Mataki services or asked to defer.';
comment on column public.buildings.decline_reason is
  'Reason the prospect declined or deferred Mataki services.';
comment on column public.buildings.repitch_date is
  'Automatically calculated as 12 months after declined_date for Re-pitch Later records.';
