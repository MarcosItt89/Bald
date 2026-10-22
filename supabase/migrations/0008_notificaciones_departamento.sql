-- =============================================================================
-- OPERALIA · 0008 · NOTIFICACIONES PERSONALES Y POR DEPARTAMENTO
-- -----------------------------------------------------------------------------
-- Una notificación puede ser:
--   * personal          → employee_id = X
--   * de departamento   → employee_id NULL, department_id = D
--                         (branch_id NULL = todas las sucursales, o una en particular)
-- La lectura se guarda POR EMPLEADO en notification_reads, así un aviso de
-- departamento leído por una persona sigue "no leído" para sus compañeros.
-- El frontend lee la vista v_my_notifications y marca con las funciones
-- mark_notification_read / mark_all_notifications_read.
-- =============================================================================

alter table public.notifications alter column employee_id drop not null;
alter table public.notifications add column if not exists department_id uuid references public.departments(id) on delete cascade;
alter table public.notifications add column if not exists branch_id uuid references public.branches(id) on delete cascade;

do $$ begin
  alter table public.notifications add constraint notifications_target_chk
    check (employee_id is not null or department_id is not null);
exception when duplicate_object then null; end $$;

create index if not exists notifications_department_idx on public.notifications (department_id, created_at desc);

create table if not exists public.notification_reads (
  notification_id uuid not null references public.notifications(id) on delete cascade,
  employee_id     uuid not null references public.employees(id) on delete cascade,
  read_at         timestamptz not null default now(),
  primary key (notification_id, employee_id)
);
alter table public.notification_reads enable row level security;

-- ¿Esta notificación es para mí? (personal, o de mi departamento en mi sucursal)
create or replace function public.is_my_notification(p_employee_id uuid, p_department_id uuid, p_branch_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_employee_id is not null then p_employee_id = public.auth_employee_id()
    else (p_branch_id is null or p_branch_id = public.auth_branch_id())
     and (p_department_id = public.auth_department_id()
          or exists (select 1 from public.employee_departments ed
                     where ed.employee_id = public.auth_employee_id() and ed.department_id = p_department_id))
  end
$$;

-- Políticas: cada usuario ve las suyas y las de su(s) departamento(s).
drop policy if exists notifications_select on public.notifications;
drop policy if exists notifications_update on public.notifications;
drop policy if exists notifications_delete on public.notifications;
drop policy if exists notifications_insert on public.notifications;

create policy notifications_select on public.notifications for select to authenticated
  using (company_id = (select public.auth_company_id())
         and public.is_my_notification(employee_id, department_id, branch_id));
-- Solo se marcan/borran directamente las personales; las de departamento usan notification_reads.
create policy notifications_update on public.notifications for update to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));
create policy notifications_delete on public.notifications for delete to authenticated
  using (employee_id = (select public.auth_employee_id()));
-- Gerentes/supervisores pueden enviar avisos a un departamento de su sucursal.
create policy notifications_insert on public.notifications for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and department_id is not null and employee_id is null
              and (select public.has_permission('manage_tasks')));

drop policy if exists notification_reads_all on public.notification_reads;
create policy notification_reads_all on public.notification_reads for all to authenticated
  using (employee_id = (select public.auth_employee_id()))
  with check (employee_id = (select public.auth_employee_id()));

grant select, insert, update, delete on public.notification_reads to authenticated;

-- Vista con el estado "leída" calculado para el usuario actual.
create or replace view public.v_my_notifications with (security_invoker = on) as
select n.id, n.company_id, n.employee_id, n.department_id, n.branch_id, n.type, n.title, n.body, n.link,
       n.created_at, d.name as department_name,
       (n.employee_id is null) as is_department,
       case when n.employee_id is not null then n.is_read
            else exists (select 1 from public.notification_reads r
                         where r.notification_id = n.id and r.employee_id = public.auth_employee_id())
       end as is_read
from public.notifications n
left join public.departments d on d.id = n.department_id;

revoke all on public.v_my_notifications from anon;
grant select on public.v_my_notifications to authenticated;

create or replace function public.mark_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n public.notifications%rowtype;
begin
  select * into n from public.notifications where id = p_id;
  if not found or not public.is_my_notification(n.employee_id, n.department_id, n.branch_id) then return; end if;
  if n.employee_id is not null then
    update public.notifications set is_read = true where id = p_id;
  else
    insert into public.notification_reads (notification_id, employee_id)
    values (p_id, public.auth_employee_id()) on conflict do nothing;
  end if;
end $$;

create or replace function public.mark_all_notifications_read()
returns integer language plpgsql security definer set search_path = public as $$
declare v_count int;
begin
  update public.notifications set is_read = true
   where employee_id = public.auth_employee_id() and not is_read;
  get diagnostics v_count = row_count;

  insert into public.notification_reads (notification_id, employee_id)
  select n.id, public.auth_employee_id() from public.notifications n
  where n.employee_id is null and n.company_id = public.auth_company_id()
    and public.is_my_notification(n.employee_id, n.department_id, n.branch_id)
  on conflict do nothing;
  return v_count;
end $$;

revoke all on function public.is_my_notification(uuid, uuid, uuid) from public, anon;
revoke all on function public.mark_notification_read(uuid) from public, anon;
revoke all on function public.mark_all_notifications_read() from public, anon;
grant execute on function public.is_my_notification(uuid, uuid, uuid) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
