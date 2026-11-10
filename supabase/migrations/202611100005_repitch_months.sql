-- Mataki: selectable 1–12 month re-pitch schedule
-- Apply after migration 202611100004_repitch_later.sql in Supabase SQL Editor.

alter table public.buildings
  add column if not exists repitch_months smallint not null default 12;

alter table public.buildings
  drop constraint if exists buildings_repitch_months_check;

alter table public.buildings
  add constraint buildings_repitch_months_check
  check (repitch_months between 1 and 12);

-- Preserve the decline date as the anchor and calculate the re-pitch date
-- using the selected number of months. Existing records default to 12.
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

    new.repitch_months := coalesce(new.repitch_months, 12);
    new.repitch_date :=
      (new.declined_date + make_interval(months => new.repitch_months))::date;
  end if;

  return new;
end;
$$;

drop trigger if exists buildings_set_repitch_schedule on public.buildings;

create trigger buildings_set_repitch_schedule
before insert or update of prospecting_status, declined_date, repitch_months
on public.buildings
for each row
execute function public.set_building_repitch_schedule();

comment on column public.buildings.repitch_months is
  'Number of months (1–12) after declined_date before Mataki should re-pitch this prospect.';
comment on column public.buildings.repitch_date is
  'Automatically calculated as declined_date plus the selected repitch_months.';
