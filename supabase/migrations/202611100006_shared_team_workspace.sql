-- Mataki shared team workspace access.
-- Apply after migration 202611100005_repitch_months.sql.
--
-- A staff account must exist in Supabase Auth before an owner/admin can add it.
-- A user's newest membership is the active workspace in the application.
-- Existing separate workspaces and their data are deliberately preserved.

-- Inspect a prospective team member without exposing data to ordinary members.
create or replace function public.preview_workspace_member(member_email text)
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
  is_already_member boolean := false;
  other_workspace_count integer := 0;
  existing_record_count bigint := 0;
  old_org_id uuid;
  row_count bigint;
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
    raise exception 'Only a Mataki owner or administrator can manage team members.';
  end if;

  if member_email is null or length(trim(member_email)) = 0 then
    raise exception 'Enter the staff member email address.';
  end if;

  select u.id, u.email
    into target_user_id, target_email
  from auth.users u
  where lower(u.email) = lower(trim(member_email))
  limit 1;

  if target_user_id is null then
    return jsonb_build_object('user_found', false);
  end if;

  select exists (
    select 1 from public.organization_memberships m
    where m.organization_id = active_org_id and m.user_id = target_user_id
  ) into is_already_member;

  for old_org_id in
    select m.organization_id
    from public.organization_memberships m
    where m.user_id = target_user_id
      and m.organization_id <> active_org_id
  loop
    other_workspace_count := other_workspace_count + 1;

    select count(*) into row_count from public.businesses b where b.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.buildings b where b.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.contacts c where c.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.visits v where v.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.follow_ups f where f.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.quotes q where q.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.inspections i where i.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
    select count(*) into row_count from public.documents d where d.organization_id = old_org_id;
    existing_record_count := existing_record_count + row_count;
  end loop;

  return jsonb_build_object(
    'user_found', true,
    'email', target_email,
    'already_member', is_already_member,
    'other_workspace_count', other_workspace_count,
    'existing_record_count', existing_record_count
  );
end;
$$;

create or replace function public.add_workspace_member_by_email(member_email text)
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

  if member_email is null or length(trim(member_email)) = 0 then
    raise exception 'Enter the staff member email address.';
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
  values (active_org_id, target_user_id, 'member')
  on conflict (organization_id, user_id) do nothing;

  return jsonb_build_object(
    'email', target_email,
    'already_member', already_member,
    'organization_id', active_org_id
  );
end;
$$;

create or replace function public.list_workspace_members()
returns table(email text, role text, joined_at timestamptz)
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  active_org_id uuid;
  actor_role text;
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
    raise exception 'Only a Mataki owner or administrator can view the team list.';
  end if;

  return query
  select u.email::text, m.role, m.created_at
  from public.organization_memberships m
  join auth.users u on u.id = m.user_id
  where m.organization_id = active_org_id
  order by case m.role when 'owner' then 0 when 'admin' then 1 else 2 end,
           lower(u.email);
end;
$$;

revoke all on function public.preview_workspace_member(text) from public, anon;
revoke all on function public.add_workspace_member_by_email(text) from public, anon;
revoke all on function public.list_workspace_members() from public, anon;
grant execute on function public.preview_workspace_member(text) to authenticated;
grant execute on function public.add_workspace_member_by_email(text) to authenticated;
grant execute on function public.list_workspace_members() to authenticated;

-- The application no longer creates a separate workspace for every new staff signup.
revoke execute on function public.create_workspace(text) from authenticated;
