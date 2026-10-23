-- =============================================================================
-- OPERALIA · 0021 · COMUNICADOS CON ACUSE DE LECTURA
-- -----------------------------------------------------------------------------
--   * announcements: título, cuerpo, adjunto opcional (bucket privado
--     «announcements»), alcance (empresa, zona, sucursal o departamento) y
--     fecha de vigencia. Departamento sin sucursal = ese departamento en
--     todas las sucursales.
--   * announcement_reads: cada empleado confirma «Leído»
--     (mark_announcement_read).
--   * Al publicar se notifica a cada empleado activo del alcance.
--   * announcement_progress: el publicador (o quien tiene
--     manage_announcements) ve quién falta, por sucursal y persona.
--   * Permisos: publish_announcements y manage_announcements.
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.announcements (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references public.companies(id) on delete cascade,
  title            text not null check (length(trim(title)) > 0),
  body             text not null,
  scope            text not null default 'company' check (scope in ('company','zone','branch','department')),
  zone_id          uuid references public.zones(id) on delete cascade,
  branch_id        uuid references public.branches(id) on delete cascade,
  department_id    uuid references public.departments(id) on delete cascade,
  valid_until      date,
  attachment_path  text,
  attachment_name  text,
  attachment_type  text,
  status           text not null default 'active' check (status in ('active','archived')),
  published_by     uuid references public.employees(id) on delete set null,
  published_at     timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
do $$ begin
  alter table public.announcements add constraint announcements_scope_chk check (
       (scope = 'company'    and zone_id is null and branch_id is null and department_id is null)
    or (scope = 'zone'       and zone_id is not null and branch_id is null and department_id is null)
    or (scope = 'branch'     and branch_id is not null and zone_id is null and department_id is null)
    or (scope = 'department' and department_id is not null and zone_id is null));
exception when duplicate_object then null; end $$;
create index if not exists announcements_company_idx on public.announcements (company_id, published_at desc);

create table if not exists public.announcement_reads (
  announcement_id  uuid not null references public.announcements(id) on delete cascade,
  employee_id      uuid not null references public.employees(id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (announcement_id, employee_id)
);

drop trigger if exists trg_updated_at on public.announcements;
create trigger trg_updated_at before update on public.announcements
  for each row execute function public.tg_set_updated_at();
drop trigger if exists trg_actor on public.announcements;
create trigger trg_actor before insert on public.announcements
  for each row execute function public.tg_set_actor('published_by');

insert into public.permissions (code, module, name, description) values
  ('publish_announcements', 'Comunicados', 'Publicar comunicados', 'Publicar comunicados dentro de su alcance y ver quién falta de leer'),
  ('manage_announcements',  'Comunicados', 'Gestionar comunicados', 'Ver el avance de lectura de todos los comunicados y archivarlos')
on conflict (code) do nothing;

-- ─── ALCANCE ────────────────────────────────────────────────────────────────
-- ¿El comunicado le llega a este empleado?
create or replace function public.announcement_matches(
  p_employee_id uuid, p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.employees e
    left join public.branches b on b.id = e.branch_id
    where e.id = p_employee_id
      and case p_scope
            when 'company' then true
            when 'zone' then b.zone_id = p_zone_id
                          or exists (select 1 from public.employee_zones ez where ez.employee_id = e.id and ez.zone_id = p_zone_id)
            when 'branch' then e.branch_id = p_branch_id
            when 'department' then (p_branch_id is null or e.branch_id = p_branch_id)
                               and (e.department_id = p_department_id
                                    or exists (select 1 from public.employee_departments ed
                                               where ed.employee_id = e.id and ed.department_id = p_department_id))
            else false
          end)
$$;
revoke all on function public.announcement_matches(uuid, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.announcement_matches(uuid, text, uuid, uuid, uuid) to authenticated;

-- ¿Puede el usuario publicar con este alcance?
create or replace function public.can_publish_announcement(p_scope text, p_zone_id uuid, p_branch_id uuid, p_department_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_permission('publish_announcements') and case p_scope
    when 'company' then public.auth_role_scope() = 'company'
    when 'zone' then public.auth_role_scope() = 'company' or p_zone_id in (select public.auth_zone_ids())
    when 'branch' then public.can_access_branch(p_branch_id)
    when 'department' then case when p_branch_id is null then public.auth_role_scope() = 'company'
                                else public.can_access_department(p_branch_id, p_department_id) end
    else false
  end
$$;
revoke all on function public.can_publish_announcement(text, uuid, uuid, uuid) from public, anon;
grant execute on function public.can_publish_announcement(text, uuid, uuid, uuid) to authenticated;

-- ¿Puede ver quién falta? El publicador, o manage_announcements con alcance de empresa.
create or replace function public.can_track_announcement(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.announcements a where a.id = p_id and a.company_id = public.auth_company_id()
                 and (a.published_by = public.auth_employee_id()
                      or (public.has_permission('manage_announcements') and public.auth_role_scope() = 'company')))
$$;
revoke all on function public.can_track_announcement(uuid) from public, anon;
grant execute on function public.can_track_announcement(uuid) to authenticated;

-- ─── RLS ────────────────────────────────────────────────────────────────────
alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated
  using (company_id = (select public.auth_company_id()) and (
    published_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_announcements')) and (select public.auth_role_scope()) = 'company')
    or (status = 'active' and public.announcement_matches((select public.auth_employee_id()), scope, zone_id, branch_id, department_id))));
drop policy if exists announcements_insert on public.announcements;
create policy announcements_insert on public.announcements for insert to authenticated
  with check (company_id = (select public.auth_company_id())
              and public.can_publish_announcement(scope, zone_id, branch_id, department_id));
drop policy if exists announcements_update on public.announcements;
create policy announcements_update on public.announcements for update to authenticated
  using (company_id = (select public.auth_company_id()) and (
    published_by = (select public.auth_employee_id())
    or ((select public.has_permission('manage_announcements')) and (select public.auth_role_scope()) = 'company')))
  with check (company_id = (select public.auth_company_id()));
drop policy if exists announcements_delete on public.announcements;
create policy announcements_delete on public.announcements for delete to authenticated
  using (company_id = (select public.auth_company_id()) and published_by = (select public.auth_employee_id()));

-- Lecturas: cada quien ve las suyas; el publicador ve las de su comunicado.
-- Se escriben con mark_announcement_read.
drop policy if exists announcement_reads_select on public.announcement_reads;
create policy announcement_reads_select on public.announcement_reads for select to authenticated
  using (employee_id = (select public.auth_employee_id()) or public.can_track_announcement(announcement_id));

grant select, insert, update, delete on public.announcements to authenticated;
grant select on public.announcement_reads to authenticated;

-- El alcance y el publicador no cambian al editar (solo texto, vigencia, adjunto y estado).
create or replace function public.tg_announcement_guard()
returns trigger language plpgsql as $$
begin
  if (new.scope, new.zone_id, new.branch_id, new.department_id, new.published_by, new.company_id)
     is distinct from (old.scope, old.zone_id, old.branch_id, old.department_id, old.published_by, old.company_id) then
    raise exception 'El alcance de un comunicado no se puede cambiar: publícalo de nuevo';
  end if;
  return new;
end $$;
drop trigger if exists trg_announcement_guard on public.announcements;
create trigger trg_announcement_guard before update on public.announcements
  for each row execute function public.tg_announcement_guard();

-- ─── PUBLICAR: aviso a cada empleado del alcance ────────────────────────────
create or replace function public.tg_announcement_notify()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (company_id, employee_id, type, title, body, link)
  select new.company_id, e.id, 'announcement', left('Comunicado: ' || new.title, 200),
         left(regexp_replace(new.body, '\s+', ' ', 'g'), 160), '/announcements?id=' || new.id
  from public.employees e
  where e.company_id = new.company_id and e.status = 'active'
    and e.id is distinct from new.published_by
    and public.announcement_matches(e.id, new.scope, new.zone_id, new.branch_id, new.department_id);
  -- Quien publica y también está en el alcance queda como leído.
  if new.published_by is not null
     and public.announcement_matches(new.published_by, new.scope, new.zone_id, new.branch_id, new.department_id) then
    insert into public.announcement_reads (announcement_id, employee_id) values (new.id, new.published_by)
    on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists trg_announcement_notify on public.announcements;
create trigger trg_announcement_notify after insert on public.announcements
  for each row execute function public.tg_announcement_notify();

-- ─── LEÍDO ──────────────────────────────────────────────────────────────────
create or replace function public.mark_announcement_read(p_id uuid)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare
  a      public.announcements%rowtype;
  v_at   timestamptz;
begin
  select * into a from public.announcements where id = p_id;
  if not found or a.company_id <> public.auth_company_id()
     or not public.announcement_matches(public.auth_employee_id(), a.scope, a.zone_id, a.branch_id, a.department_id) then
    raise exception 'Este comunicado no es para ti';
  end if;
  insert into public.announcement_reads (announcement_id, employee_id) values (p_id, public.auth_employee_id())
  on conflict (announcement_id, employee_id) do nothing;
  select read_at into v_at from public.announcement_reads where announcement_id = p_id and employee_id = public.auth_employee_id();
  -- Su aviso también queda leído.
  update public.notifications set is_read = true
   where employee_id = public.auth_employee_id() and type = 'announcement'
     and link = '/announcements?id=' || p_id and not is_read;
  return v_at;
end $$;
revoke all on function public.mark_announcement_read(uuid) from public, anon;
grant execute on function public.mark_announcement_read(uuid) to authenticated;

-- ─── AVANCE DE LECTURA ──────────────────────────────────────────────────────
create or replace function public.announcement_progress(p_id uuid)
returns table (employee_id uuid, full_name text, job_title text, branch_id uuid, branch_name text,
               department_name text, read_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare a public.announcements%rowtype;
begin
  if not public.can_track_announcement(p_id) then raise exception 'No puedes ver el avance de este comunicado'; end if;
  select * into a from public.announcements where id = p_id;
  return query
  select e.id, e.full_name, e.position, e.branch_id, b.name, d.name, r.read_at
  from public.employees e
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  left join public.announcement_reads r on r.announcement_id = a.id and r.employee_id = e.id
  where e.company_id = a.company_id
    and (e.status = 'active' or r.read_at is not null)
    and public.announcement_matches(e.id, a.scope, a.zone_id, a.branch_id, a.department_id)
  order by b.name nulls last, r.read_at is not null, e.full_name;
end $$;
revoke all on function public.announcement_progress(uuid) from public, anon;
grant execute on function public.announcement_progress(uuid) to authenticated;

-- Totales para la lista (solo para quien puede ver el avance).
create or replace function public.announcement_counts(p_id uuid)
returns table (audience integer, read_count integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.can_track_announcement(p_id) then
    return query select null::int, null::int;
    return;
  end if;
  return query
  select count(*)::int, count(r.read_at)::int
  from public.announcements a
  join public.employees e on e.company_id = a.company_id
  left join public.announcement_reads r on r.announcement_id = a.id and r.employee_id = e.id
  where a.id = p_id
    and (e.status = 'active' or r.read_at is not null)
    and public.announcement_matches(e.id, a.scope, a.zone_id, a.branch_id, a.department_id);
end $$;
revoke all on function public.announcement_counts(uuid) from public, anon;
grant execute on function public.announcement_counts(uuid) to authenticated;

drop view if exists public.v_announcements;
create view public.v_announcements with (security_invoker = on) as
select a.*, p.full_name as published_by_name, z.name as zone_name, b.name as branch_name, d.name as department_name,
       (a.valid_until is not null and a.valid_until < public.company_today(a.company_id)) as is_expired,
       (select r.read_at from public.announcement_reads r
         where r.announcement_id = a.id and r.employee_id = public.auth_employee_id()) as my_read_at,
       public.announcement_matches(public.auth_employee_id(), a.scope, a.zone_id, a.branch_id, a.department_id) as is_for_me,
       c.audience, c.read_count
from public.announcements a
left join public.employees p on p.id = a.published_by
left join public.zones z on z.id = a.zone_id
left join public.branches b on b.id = a.branch_id
left join public.departments d on d.id = a.department_id
left join lateral public.announcement_counts(a.id) c on true;
grant select on public.v_announcements to authenticated;

-- ─── ADJUNTOS ───────────────────────────────────────────────────────────────
-- Bucket privado: {company_id}/{uuid}.{ext}. Lo lee cualquiera de la empresa
-- (URL firmada); solo sube quien publica.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('announcements', 'announcements', false, 10485760,
        array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists announcements_objects_select on storage.objects;
drop policy if exists announcements_objects_insert on storage.objects;
drop policy if exists announcements_objects_delete on storage.objects;
create policy announcements_objects_select on storage.objects for select to authenticated
  using (bucket_id = 'announcements' and (storage.foldername(name))[1] = (select public.auth_company_id())::text);
create policy announcements_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'announcements' and (storage.foldername(name))[1] = (select public.auth_company_id())::text
              and (select public.has_permission('publish_announcements')));
create policy announcements_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'announcements' and owner_id = (select auth.uid())::text);
