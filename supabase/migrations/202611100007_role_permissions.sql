-- Mataki role-based permissions.
-- Apply after migration 202611100006_shared_team_workspace.sql.
--
-- Roles:
-- owner: full control; protected ownership role.
-- admin: operational administration and staff management, but cannot manage admins/owners.
-- sales: manage prospects, customers, contacts, visits, follow-ups and quotes.
-- inspector: read customer/site directory and manage visits, follow-ups, inspections and documents.
-- viewer: read-only access to the customer/site directory and operational summaries.
--
-- Previous generic members are mapped to sales to retain prospecting access.
-- No customer records are deleted or moved.

alter table public.organization_memberships
  drop constraint if exists organization_memberships_role_check;

update public.organization_memberships
set role = 'sales'
where role = 'member';

alter table public.organization_memberships
  add constraint organization_memberships_role_check
  check (role in ('owner', 'admin', 'sales', 'inspector', 'viewer'));

-- Keep the current role helper aligned with the new role model.
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

-- -------------------------------------------------------------------
-- Data access policies
-- -------------------------------------------------------------------

drop policy if exists "members can manage businesses" on public.businesses;
drop policy if exists "members can manage buildings" on public.buildings;
drop policy if exists "members can manage contacts" on public.contacts;
drop policy if exists "members can manage visits" on public.visits;
drop policy if exists "members can manage follow ups" on public.follow_ups;
drop policy if exists "members can manage quotes" on public.quotes;
drop policy if exists "members can manage inspections" on public.inspections;
drop policy if exists "members can manage documents" on public.documents;

-- All team roles can read the shared customer/site directory.
create policy "team can view businesses"
on public.businesses for select to authenticated
using (public.is_org_member(organization_id));

create policy "team can view buildings"
on public.buildings for select to authenticated
using (public.is_org_member(organization_id));

create policy "team can view contacts"
on public.contacts for select to authenticated
using (public.is_org_member(organization_id));

-- Sales can manage prospecting and customer records. Only administrators
-- can delete records, protecting shared company history.
create policy "sales admins owners manage businesses"
on public.businesses for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners update businesses"
on public.businesses for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']))
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "admins owners delete businesses"
on public.businesses for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

create policy "sales admins owners insert buildings"
on public.buildings for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners update buildings"
on public.buildings for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']))
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "admins owners delete buildings"
on public.buildings for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

create policy "sales admins owners insert contacts"
on public.contacts for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners update contacts"
on public.contacts for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']))
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "admins owners delete contacts"
on public.contacts for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

-- Visits and follow-up actions are shared operational records. Inspectors
-- and sales staff can create and update these, but only admins delete them.
create policy "team can view visits"
on public.visits for select to authenticated
using (public.is_org_member(organization_id));

create policy "sales inspectors admins insert visits"
on public.visits for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales','inspector']));

create policy "sales inspectors admins update visits"
on public.visits for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales','inspector']))
with check (public.has_org_role(organization_id, array['owner','admin','sales','inspector']));

create policy "admins owners delete visits"
on public.visits for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

create policy "team can view follow ups"
on public.follow_ups for select to authenticated
using (public.is_org_member(organization_id));

create policy "sales inspectors admins insert follow ups"
on public.follow_ups for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales','inspector']));

create policy "sales inspectors admins update follow ups"
on public.follow_ups for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales','inspector']))
with check (public.has_org_role(organization_id, array['owner','admin','sales','inspector']));

create policy "admins owners delete follow ups"
on public.follow_ups for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

-- Quote information is a sales function and is not exposed to inspectors.
create policy "sales admins owners view quotes"
on public.quotes for select to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners insert quotes"
on public.quotes for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "sales admins owners update quotes"
on public.quotes for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','sales']))
with check (public.has_org_role(organization_id, array['owner','admin','sales']));

create policy "admins owners delete quotes"
on public.quotes for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

-- Inspection records and their documents are visible to inspectors and admins.
create policy "inspection team view inspections"
on public.inspections for select to authenticated
using (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "inspection team insert inspections"
on public.inspections for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "inspection team update inspections"
on public.inspections for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','inspector']))
with check (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "admins owners delete inspections"
on public.inspections for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

create policy "inspection team view documents"
on public.documents for select to authenticated
using (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "inspection team insert documents"
on public.documents for insert to authenticated
with check (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "inspection team update documents"
on public.documents for update to authenticated
using (public.has_org_role(organization_id, array['owner','admin','inspector']))
with check (public.has_org_role(organization_id, array['owner','admin','inspector']));

create policy "admins owners delete documents"
on public.documents for delete to authenticated
using (public.has_org_role(organization_id, array['owner','admin']));

-- Owner/admin workspace updates only.
drop policy if exists "owners and admins can update their organizations" on public.organizations;
create policy "owners admins update organizations"
on public.organizations for update to authenticated
using (public.has_org_role(id, array['owner','admin']))
with check (public.has_org_role(id, array['owner','admin']));

-- -------------------------------------------------------------------
-- Secure team administration
-- -------------------------------------------------------------------

drop function if exists public.add_workspace_member_by_email(text);

create or replace function public.add_workspace_member_by_email(member_email text, member_role text default 'sales')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  active_org_id uuid;
  actor_role text;
  target_user_id uuid;
  target_email text;
  already_member boolean := false;
begin
  if actor_id is null then
    raise exception 'You must be signed in.';
  end if;

  select m.organization_id, m.role
    into active_org_id, actor_role
  from public.organization_memberships m
  where m.user_id = actor_id
  order by m.created_at desc, m.organization_id desc
  limit 1;

  if active_org_id is null or actor_role not in ('owner', 'admin') then
    raise exception 'Only a Mataki owner or administrator can add team members.';
  end if;

  if member_role not in ('admin','sales','inspector','viewer') then
    raise exception 'That role cannot be assigned.';
  end if;

  if actor_role = 'admin' and member_role = 'admin' then
    raise exception 'Only the owner can appoint another administrator.';
  end if;

  select u.id, u.email
    into target_user_id, target_email
  from auth.users u
  where lower(u.email) = lower(trim(member_email))
  limit 1;

  if target_user_id is null then
    raise exception 'No registered account was found for %. They must sign up and confirm their email first.', trim(member_email);
  end if;

  if target_user_id = actor_id then
    raise exception 'You are already signed in to the Mataki workspace.';
  end if;

  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = active_org_id and m.user_id = target_user_id
  ) into already_member;

  insert into public.organization_memberships (organization_id, user_id, role)
  values (active_org_id, target_user_id, member_role)
  on conflict (organization_id, user_id)
  do update set role = excluded.role;

  return jsonb_build_object(
    'email', target_email,
    'role', member_role,
    'already_member', already_member,
    'organization_id', active_org_id
  );
end;
$$;

create or replace function public.set_workspace_member_role(member_email text, new_role text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  active_org_id uuid;
  actor_role text;
  target_user_id uuid;
  old_role text;
begin
  if actor_id is null then raise exception 'You must be signed in.'; end if;

  select m.organization_id, m.role into active_org_id, actor_role
  from public.organization_memberships m
  where m.user_id = actor_id
  order by m.created_at desc, m.organization_id desc
  limit 1;

  if actor_role not in ('owner','admin') or active_org_id is null then
    raise exception 'Only a Mataki owner or administrator can change team roles.';
  end if;

  if new_role not in ('admin','sales','inspector','viewer') then
    raise exception 'That role cannot be assigned.';
  end if;

  select u.id into target_user_id
  from auth.users u
  where lower(u.email) = lower(trim(member_email))
  limit 1;
  if target_user_id is null then raise exception 'Team member not found.'; end if;
  if target_user_id = actor_id then raise exception 'You cannot change your own role.'; end if;

  select m.role into old_role
  from public.organization_memberships m
  where m.organization_id = active_org_id and m.user_id = target_user_id;

  if old_role is null then raise exception 'That person is not a member of this workspace.'; end if;
  if old_role = 'owner' then raise exception 'The owner role is protected.'; end if;
  if actor_role = 'admin' and (old_role = 'admin' or new_role = 'admin') then
    raise exception 'Only the owner can manage administrator roles.';
  end if;

  update public.organization_memberships
  set role = new_role
  where organization_id = active_org_id and user_id = target_user_id;

  return jsonb_build_object('email',trim(member_email),'role',new_role);
end;
$$;

create or replace function public.remove_workspace_member(member_email text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  active_org_id uuid;
  actor_role text;
  target_user_id uuid;
  target_role text;
begin
  if actor_id is null then raise exception 'You must be signed in.'; end if;

  select m.organization_id, m.role into active_org_id, actor_role
  from public.organization_memberships m
  where m.user_id = actor_id
  order by m.created_at desc, m.organization_id desc
  limit 1;

  if actor_role not in ('owner','admin') or active_org_id is null then
    raise exception 'Only a Mataki owner or administrator can remove team members.';
  end if;

  select u.id into target_user_id
  from auth.users u where lower(u.email) = lower(trim(member_email)) limit 1;
  if target_user_id is null then raise exception 'Team member not found.'; end if;
  if target_user_id = actor_id then raise exception 'You cannot remove your own account.'; end if;

  select m.role into target_role
  from public.organization_memberships m
  where m.organization_id = active_org_id and m.user_id = target_user_id;
  if target_role is null then raise exception 'That person is not a member of this workspace.'; end if;
  if target_role = 'owner' then raise exception 'The owner account cannot be removed.'; end if;
  if actor_role = 'admin' and target_role = 'admin' then
    raise exception 'Only the owner can remove an administrator.';
  end if;

  delete from public.organization_memberships
  where organization_id = active_org_id and user_id = target_user_id;

  return jsonb_build_object('email',trim(member_email),'removed',true);
end;
$$;

revoke all on function public.add_workspace_member_by_email(text,text) from public, anon;
revoke all on function public.set_workspace_member_role(text,text) from public, anon;
revoke all on function public.remove_workspace_member(text) from public, anon;
grant execute on function public.add_workspace_member_by_email(text,text) to authenticated;
grant execute on function public.set_workspace_member_role(text,text) to authenticated;
grant execute on function public.remove_workspace_member(text) to authenticated;
