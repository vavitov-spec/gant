alter table public.project_invites add column if not exists target_user_id uuid references auth.users(id);
alter table public.project_invites add column if not exists created_at timestamptz not null default now();

create or replace function public.find_profile_by_public_id(p_public_id bigint)
returns table(user_id uuid, full_name text, email text)
language sql security definer stable as $body1$
  select p.user_id, p.full_name, p.email
  from public.profiles p
  where p.public_id = p_public_id;
$body1$;

create or replace function public.invite_member_by_id(
  p_project_id bigint, p_target_user_id uuid, p_role text)
returns uuid language plpgsql security definer as $body2$
declare v_token uuid;
begin
  if not public.is_project_admin(p_project_id) then
    raise exception 'Приглашать участников может только руководитель проекта';
  end if;
  if p_role not in ('admin','member','contractor','client') then
    raise exception 'Неверная роль';
  end if;
  if p_target_user_id is null then
    raise exception 'Пользователь не найден';
  end if;
  if exists(select 1 from public.project_members where project_id = p_project_id and user_id = p_target_user_id) then
    raise exception 'Этот пользователь уже участник графика';
  end if;
  delete from public.project_invites
    where project_id = p_project_id and target_user_id = p_target_user_id and used_at is null;
  insert into public.project_invites(project_id, role, created_by, target_user_id)
  values (p_project_id, p_role, auth.uid(), p_target_user_id)
  returning token into v_token;
  return v_token;
end $body2$;

create or replace function public.get_my_pending_invites()
returns table(token uuid, project_name text, role text, created_at timestamptz)
language sql security definer stable as $body3$
  select i.token, pr.name, i.role, i.created_at
  from public.project_invites i
  join public.projects pr on pr.id = i.project_id
  where i.target_user_id = auth.uid() and i.used_at is null and i.expires_at > now()
  order by i.created_at desc;
$body3$;

create or replace function public.decline_project_invite(p_token uuid)
returns void language plpgsql security definer as $body4$
begin
  delete from public.project_invites
  where token = p_token and target_user_id = auth.uid() and used_at is null;
end $body4$;

create or replace function public.accept_invite(p_token uuid)
returns bigint language plpgsql security definer as $body5$
declare
  inv record;
  v_app_state_id bigint;
begin
  select * into inv from public.project_invites where token = p_token and used_at is null and expires_at > now();
  if not found then
    raise exception 'Приглашение недействительно или уже использовано';
  end if;
  if inv.target_user_id is not null and inv.target_user_id <> auth.uid() then
    raise exception 'Это приглашение предназначено другому пользователю';
  end if;
  insert into public.project_members(project_id, user_id, role, contractor_name)
  values (inv.project_id, auth.uid(), inv.role, inv.contractor_name)
  on conflict (project_id, user_id) do update set role = excluded.role, contractor_name = excluded.contractor_name;
  update public.project_invites set used_at = now() where token = p_token;
  select app_state_id into v_app_state_id from public.projects where id = inv.project_id;
  return v_app_state_id;
end $body5$;
