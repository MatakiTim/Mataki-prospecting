-- Mataki Prospecting Platform
-- Initial database schema for Supabase.
-- Apply once in Supabase Dashboard > SQL Editor.
-- This migration contains no customer data or secrets.

create extension if not exists pgcrypto;

-- -------------------------------------------------------------------
-- Core workspace and membership
-- -------------------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_by uuid not null references auth.users(id) on delete restrict default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_memberships (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id)
);

-- Security-definer helpers avoid recursive membership RLS checks.
create or replace function public.is_org_member(target_org_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = target_org_id
      and m.user_id = (select auth.uid())
  );
$$;

create or replace function public.has_org_role(target_org_id uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_memberships m
    where m.organization_id = target_org_id
      and m.user_id = (select auth.uid())
      and m.role = any(allowed_roles)
  );
$$;

-- First-user setup: call this after signing into the Mataki application.
create or replace function public.create_workspace(workspace_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_org_id uuid;
  current_user_id uuid;
begin
  current_user_id := auth.uid();

  if current_user_id is null then
    raise exception 'You must be signed in to create a Mataki workspace.';
  end if;

  if workspace_name is null or length(trim(workspace_name)) = 0 then
    raise exception 'Workspace name cannot be blank.';
  end if;

  insert into public.organizations (name, created_by)
  values (trim(workspace_name), current_user_id)
  returning id into new_org_id;

  insert into public.organization_memberships (organization_id, user_id, role)
  values (new_org_id, current_user_id, 'owner');

  return new_org_id;
end;
$$;

revoke all on function public.is_org_member(uuid) from public, anon;
revoke all on function public.has_org_role(uuid, text[]) from public, anon;
revoke all on function public.create_workspace(text) from public, anon;
grant execute on function public.is_org_member(uuid) to authenticated;
grant execute on function public.has_org_role(uuid, text[]) to authenticated;
grant execute on function public.create_workspace(text) to authenticated;

-- -------------------------------------------------------------------
-- Businesses and physical buildings
-- -------------------------------------------------------------------

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  trading_name text,
  industry text,
  website text,
  phone text,
  email text,
  status text not null default 'prospect'
    check (status in ('prospect', 'active_client', 'inactive', 'not_a_fit')),
  lead_source text,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id)
);

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid,
  building_name text,
  street_address text,
  suburb text,
  city text not null default 'Christchurch',
  postcode text,
  latitude double precision check (latitude is null or latitude between -90 and 90),
  longitude double precision check (longitude is null or longitude between -180 and 180),
  footprint_geojson jsonb,
  prospecting_status text not null default 'potential'
    check (prospecting_status in ('visited', 'potential', 'follow_up', 'active_client', 'not_fit')),
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  constraint buildings_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete set null (business_id)
);

-- -------------------------------------------------------------------
-- People, visits and follow-up actions
-- -------------------------------------------------------------------

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid,
  building_id uuid,
  first_name text not null,
  last_name text,
  job_title text,
  phone text,
  email text,
  is_primary boolean not null default false,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, organization_id),
  constraint contacts_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete set null (business_id),
  constraint contacts_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete set null (building_id)
);

create table public.visits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid,
  building_id uuid,
  contact_id uuid,
  visited_at timestamptz not null default now(),
  outcome text not null default 'conversation'
    check (outcome in ('no_answer', 'conversation', 'interested', 'not_interested', 'quote_requested', 'other')),
  summary text,
  next_action text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visits_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete set null (business_id),
  constraint visits_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete set null (building_id),
  constraint visits_contact_same_org
    foreign key (contact_id, organization_id)
    references public.contacts (id, organization_id)
    on delete set null (contact_id)
);

create table public.follow_ups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid,
  building_id uuid,
  contact_id uuid,
  title text not null check (length(trim(title)) > 0),
  description text,
  due_at timestamptz,
  status text not null default 'open'
    check (status in ('open', 'in_progress', 'completed', 'cancelled')),
  priority text not null default 'normal'
    check (priority in ('low', 'normal', 'high')),
  assigned_to uuid references auth.users(id) on delete set null,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint follow_ups_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete set null (business_id),
  constraint follow_ups_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete set null (building_id),
  constraint follow_ups_contact_same_org
    foreign key (contact_id, organization_id)
    references public.contacts (id, organization_id)
    on delete set null (contact_id)
);

-- -------------------------------------------------------------------
-- Quotes, inspections and attached document metadata
-- -------------------------------------------------------------------

create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid not null,
  building_id uuid,
  quote_reference text,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'accepted', 'declined', 'expired', 'withdrawn')),
  amount_ex_gst numeric(12,2) not null default 0 check (amount_ex_gst >= 0),
  gst_rate numeric(5,4) not null default 0.15 check (gst_rate >= 0 and gst_rate <= 1),
  total_inc_gst numeric(12,2) generated always as (round(amount_ex_gst * (1 + gst_rate), 2)) stored,
  valid_until date,
  sent_at timestamptz,
  notes text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint quotes_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete cascade,
  constraint quotes_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete set null (building_id),
  unique (id, organization_id)
);

create table public.inspections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid not null,
  building_id uuid not null,
  inspection_date date not null default current_date,
  inspector_user_id uuid references auth.users(id) on delete set null,
  inspection_type text not null default 'routine'
    check (inspection_type in ('routine', 'initial', 'follow_up', 'post_repair', 'other')),
  status text not null default 'scheduled'
    check (status in ('scheduled', 'in_progress', 'completed', 'cancelled')),
  outcome text
    check (outcome is null or outcome in ('pass', 'remedial_work', 'fail')),
  mataki_rating text
    check (mataki_rating is null or mataki_rating in ('bronze', 'gold', 'diamond')),
  summary text,
  report_reference text,
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint inspections_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete cascade,
  constraint inspections_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete cascade,
  unique (id, organization_id)
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  business_id uuid,
  building_id uuid,
  quote_id uuid,
  inspection_id uuid,
  storage_bucket text not null default 'mataki-documents',
  storage_path text not null,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  uploaded_by uuid references auth.users(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  constraint documents_has_parent check (
    business_id is not null or building_id is not null or quote_id is not null or inspection_id is not null
  ),
  constraint documents_business_same_org
    foreign key (business_id, organization_id)
    references public.businesses (id, organization_id)
    on delete cascade,
  constraint documents_building_same_org
    foreign key (building_id, organization_id)
    references public.buildings (id, organization_id)
    on delete cascade,
  constraint documents_quote_same_org
    foreign key (quote_id, organization_id)
    references public.quotes (id, organization_id)
    on delete cascade,
  constraint documents_inspection_same_org
    foreign key (inspection_id, organization_id)
    references public.inspections (id, organization_id)
    on delete cascade
);

-- -------------------------------------------------------------------
-- Indexes
-- -------------------------------------------------------------------

create index businesses_org_status_idx on public.businesses (organization_id, status);
create index buildings_org_status_idx on public.buildings (organization_id, prospecting_status);
create index buildings_location_idx on public.buildings (latitude, longitude);
create index buildings_business_idx on public.buildings (business_id);
create index contacts_business_idx on public.contacts (business_id);
create index visits_org_visited_at_idx on public.visits (organization_id, visited_at desc);
create index visits_business_idx on public.visits (business_id);
create index follow_ups_org_due_idx on public.follow_ups (organization_id, due_at);
create index follow_ups_assigned_idx on public.follow_ups (assigned_to, status);
create index quotes_org_status_idx on public.quotes (organization_id, status);
create index inspections_org_date_idx on public.inspections (organization_id, inspection_date desc);
create index documents_org_created_idx on public.documents (organization_id, created_at desc);

-- -------------------------------------------------------------------
-- updated_at triggers
-- -------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger organizations_set_updated_at
before update on public.organizations
for each row execute function public.set_updated_at();

create trigger businesses_set_updated_at
before update on public.businesses
for each row execute function public.set_updated_at();

create trigger buildings_set_updated_at
before update on public.buildings
for each row execute function public.set_updated_at();

create trigger contacts_set_updated_at
before update on public.contacts
for each row execute function public.set_updated_at();

create trigger visits_set_updated_at
before update on public.visits
for each row execute function public.set_updated_at();

create trigger follow_ups_set_updated_at
before update on public.follow_ups
for each row execute function public.set_updated_at();

create trigger quotes_set_updated_at
before update on public.quotes
for each row execute function public.set_updated_at();

create trigger inspections_set_updated_at
before update on public.inspections
for each row execute function public.set_updated_at();

-- -------------------------------------------------------------------
-- Row Level Security and minimum client grants
-- -------------------------------------------------------------------

alter table public.organizations enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.businesses enable row level security;
alter table public.buildings enable row level security;
alter table public.contacts enable row level security;
alter table public.visits enable row level security;
alter table public.follow_ups enable row level security;
alter table public.quotes enable row level security;
alter table public.inspections enable row level security;
alter table public.documents enable row level security;

-- Remove client access from signed-out users. The application requires login.
revoke all on public.organizations, public.organization_memberships,
  public.businesses, public.buildings, public.contacts, public.visits,
  public.follow_ups, public.quotes, public.inspections, public.documents
from anon;

grant select, update on public.organizations to authenticated;
grant select on public.organization_memberships to authenticated;
grant select, insert, update, delete on public.businesses, public.buildings,
  public.contacts, public.visits, public.follow_ups, public.quotes,
  public.inspections, public.documents to authenticated;

create policy "members can view their organizations"
on public.organizations for select to authenticated
using (public.is_org_member(id));

create policy "owners and admins can update their organizations"
on public.organizations for update to authenticated
using (public.has_org_role(id, array['owner', 'admin']))
with check (public.has_org_role(id, array['owner', 'admin']));

create policy "members can view organization memberships"
on public.organization_memberships for select to authenticated
using (public.is_org_member(organization_id));

-- Workspace membership is created by the create_workspace() function.
-- Do not grant direct client insert/update/delete access to membership rows.

create policy "members can manage businesses"
on public.businesses for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage buildings"
on public.buildings for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage contacts"
on public.contacts for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage visits"
on public.visits for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage follow ups"
on public.follow_ups for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage quotes"
on public.quotes for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage inspections"
on public.inspections for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));

create policy "members can manage documents"
on public.documents for all to authenticated
using (public.is_org_member(organization_id))
with check (public.is_org_member(organization_id));
