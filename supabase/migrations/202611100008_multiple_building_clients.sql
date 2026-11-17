-- Mataki: separate physical building footprints from companies occupying them.
-- Apply after migrations 001–007.
-- Every existing building/prospect record is migrated into one company record.
-- The original buildings rows remain as physical locations and are not deleted.

create table if not exists public.building_clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null,
  business_id uuid,
  business_name text not null check (length(trim(business_name)) > 0),
  prospecting_status text not null default 'unvisited'
    check (prospecting_status in ('unvisited','visited','potential','follow_up','repitch_later','active_client','not_fit')),
  priority text check (priority is null or priority in ('High','Medium','Low')),
  quote_status text not null default 'not_started'
    check (quote_status in ('not_started','to_prepare','sent','accepted','declined')),
  racking_estimate text,
  visit_date date,
  follow_up_date date,
  first_contact_date date,
  declined_date date,
  repitch_months smallint not null default 12 check (repitch_months between 1 and 12),
  decline_reason text,
  repitch_date date,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  constraint building_clients_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete cascade,
  constraint building_clients_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete set null (business_id)
);

create index if not exists building_clients_org_building_idx
  on public.building_clients (organization_id, building_id);
create index if not exists building_clients_org_status_idx
  on public.building_clients (organization_id, prospecting_status);
create index if not exists building_clients_business_idx
  on public.building_clients (business_id);
create index if not exists building_clients_updated_idx
  on public.building_clients (organization_id, updated_at desc);

create trigger building_clients_set_updated_at
before update on public.building_clients
for each row execute function public.set_updated_at();

drop trigger if exists building_clients_set_repitch_schedule on public.building_clients;
create trigger building_clients_set_repitch_schedule
before insert or update of prospecting_status, declined_date, repitch_months
on public.building_clients
for each row execute function public.set_building_repitch_schedule();

-- Backfill one company row for each existing prospect/building record.
insert into public.building_clients (
  organization_id, building_id, business_id, business_name,
  prospecting_status, priority, quote_status, racking_estimate,
  visit_date, follow_up_date, first_contact_date, declined_date,
  repitch_months, decline_reason, repitch_date, notes, created_by,
  created_at, updated_at
)
select
  b.organization_id,
  b.id,
  b.business_id,
  coalesce(nullif(trim(biz.name),''), nullif(trim(b.building_name),''), nullif(trim(b.osm_name),''), 'Unidentified prospect'),
  b.prospecting_status,
  b.priority,
  b.quote_status,
  b.racking_estimate,
  b.visit_date,
  b.follow_up_date,
  b.first_contact_date,
  b.declined_date,
  coalesce(b.repitch_months,12),
  b.decline_reason,
  b.repitch_date,
  b.notes,
  b.created_by,
  b.created_at,
  b.updated_at
from public.buildings b
left join public.businesses biz
  on biz.id=b.business_id and biz.organization_id=b.organization_id
where not exists (
  select 1 from public.building_clients bc
  where bc.organization_id=b.organization_id and bc.building_id=b.id
);

alter table public.building_clients enable row level security;
revoke all on public.building_clients from anon, authenticated;
grant select, insert, update, delete on public.building_clients to authenticated;

create policy "team can view building clients"
on public.building_clients for select to authenticated
using (public.is_org_member(organization_id));

create policy "sales admins owners insert building clients"
on public.building_clients for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners update building clients"
on public.building_clients for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']))
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "admins owners delete building clients"
on public.building_clients for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

comment on table public.building_clients is
  'One row per company occupying a physical building. One building may have multiple independent company prospect records.';

-- Enable live updates for the new company-at-building records.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'building_clients'
     ) then
    execute 'alter publication supabase_realtime add table public.building_clients';
  end if;
end;
$$;
