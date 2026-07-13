# Настройка: приглашение участника по ID

Добавляет в «Участники» графика способ пригласить конкретного человека не ссылкой,
а по его числовому ID (тот же `public_id`, что уже показывается во вкладке «Аккаунт»).
Приглашённый видит и принимает (или отклоняет) приглашение сам — при следующем входе
в систему.

## Что делать
1. В Supabase слева **SQL Editor** → **New query**.
2. Вставьте текст ниже целиком, нажмите **Run** (Ctrl+Enter).
3. Готово — фронтенд (`construction_gantt.html`) уже обновлён и рассчитан на этот SQL.

Скрипт идемпотентный (`add column if not exists`, `create or replace`) — его можно
запускать повторно.

```sql
-- ============================================================
-- ПРИГЛАШЕНИЕ УЧАСТНИКА ПО ID (адресное приглашение — альтернатива ссылке)
-- ============================================================

-- 1. Новые поля в project_invites: получатель (если приглашение адресное,
--    а не по ссылке-токену) и время создания (нужно для сортировки списка «входящие»)
alter table public.project_invites add column if not exists target_user_id uuid references auth.users(id);
alter table public.project_invites add column if not exists created_at timestamptz not null default now();

-- 2. Поиск профиля по public_id — доступен любому вошедшему (аналогично find_company_by_inn)
create or replace function public.find_profile_by_public_id(p_public_id bigint)
returns table(user_id uuid, full_name text, email text)
language sql security definer stable as $$
  select p.user_id, p.full_name, p.email
  from public.profiles p
  where p.public_id = p_public_id;
$$;

-- 3. Создание адресного приглашения (только РП этого графика).
--    Одно активное приглашение на пользователя+график — повторный вызов заменяет прежнее.
create or replace function public.invite_member_by_id(
  p_project_id bigint, p_target_user_id uuid, p_role text)
returns uuid language plpgsql security definer as $$
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
end $$;

-- 4. Список входящих (адресованных мне) приглашений — проверяется при каждом входе
create or replace function public.get_my_pending_invites()
returns table(token uuid, project_name text, role text, created_at timestamptz)
language sql security definer stable as $$
  select i.token, pr.name, i.role, i.created_at
  from public.project_invites i
  join public.projects pr on pr.id = i.project_id
  where i.target_user_id = auth.uid() and i.used_at is null and i.expires_at > now()
  order by i.created_at desc;
$$;

-- 5. Отклонить входящее приглашение (сам получатель, без прав РП)
create or replace function public.decline_project_invite(p_token uuid)
returns void language plpgsql security definer as $$
begin
  delete from public.project_invites
  where token = p_token and target_user_id = auth.uid() and used_at is null;
end $$;

-- 6. accept_invite: та же функция, что уже принимает ссылки-приглашения, теперь
--    дополнительно проверяет, что адресное приглашение принимает именно адресат
create or replace function public.accept_invite(p_token uuid)
returns bigint language plpgsql security definer as $$
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
end $$;
```

## Если что-то пошло не так
Скопируйте текст ошибки целиком и пришлите — разберёмся. Скрипт можно запускать
повторно.
