-- =============================================================================
-- OPERALIA · 0018 · PUNTOS DE CONTROL CON QR (ZONA O EQUIPO)
-- -----------------------------------------------------------------------------
--   * checkpoints: punto físico de una sucursal (p. ej. «Cámara de carnes»,
--     «Área de carritos») con un código único que va impreso en un QR.
--   * checklist_templates.checkpoint_required + checkpoint_id: la plantilla
--     exige escanear el QR del punto para iniciar.
--     Las plantillas son de toda la empresa y los puntos de cada sucursal:
--     checkpoint_id señala el punto «modelo» y en cada sucursal vale el punto
--     con el MISMO NOMBRE (cada tienda imprime su propio QR).
--   * start_checklist_with_checkpoint(run, código): valida el código contra
--     la sucursal de la corrida, guarda checkpoint_scanned_at y la inicia.
--   * Sin el escaneo no se puede iniciar ni responder (un trigger lo impide
--     también si alguien intenta iniciarla por otro camino).
--   * Permiso manage_checkpoints (roles en seed/0015_puntos_qr.sql).
-- Re-ejecutable.
-- =============================================================================

create table if not exists public.checkpoints (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references public.companies(id) on delete cascade,
  branch_id      uuid not null references public.branches(id) on delete cascade,
  department_id  uuid references public.departments(id) on delete set null,
  name           text not null,
  code           text not null unique default ('OPQ-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10))),
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (branch_id, name)
);
create index if not exists checkpoints_branch_idx on public.checkpoints (branch_id);

drop trigger if exists trg_updated_at on public.checkpoints;
create trigger trg_updated_at before update on public.checkpoints
  for each row execute function public.tg_set_updated_at();

alter table public.checklist_templates add column if not exists checkpoint_required boolean not null default false;
alter table public.checklist_templates add column if not exists checkpoint_id uuid references public.checkpoints(id) on delete set null;
do $$ begin
  alter table public.checklist_templates add constraint checklist_templates_checkpoint_chk
    check (not checkpoint_required or checkpoint_id is not null);
exception when duplicate_object then null; end $$;
alter table public.checklist_runs add column if not exists checkpoint_scanned_at timestamptz;
alter table public.checklist_runs add column if not exists checkpoint_id uuid references public.checkpoints(id) on delete set null;

insert into public.permissions (code, module, name, description) values
  ('manage_checkpoints', 'Checklists', 'Gestionar puntos QR', 'Crear puntos de control e imprimir sus códigos QR')
on conflict (code) do nothing;

alter table public.checkpoints enable row level security;
drop policy if exists checkpoints_select on public.checkpoints;
create policy checkpoints_select on public.checkpoints for select to authenticated
  using (company_id = (select public.auth_company_id()) and public.can_access_branch(branch_id));
drop policy if exists checkpoints_write on public.checkpoints;
create policy checkpoints_write on public.checkpoints for all to authenticated
  using (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checkpoints'))
         and public.can_access_branch(branch_id))
  with check (company_id = (select public.auth_company_id()) and (select public.has_permission('manage_checkpoints'))
         and public.can_access_branch(branch_id));
grant select, insert, update, delete on public.checkpoints to authenticated;

-- Punto válido para una corrida: el de su sucursal con el nombre del punto modelo.
create or replace function public.checkpoint_for_run(p_run_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select c.id
  from public.checklist_runs r
  join public.checklist_templates t on t.id = r.template_id
  join public.checkpoints model on model.id = t.checkpoint_id
  join public.checkpoints c on c.branch_id = r.branch_id and c.name = model.name and c.is_active
  where r.id = p_run_id
$$;

-- Sin escaneo no se inicia (incluye la respuesta que pasa la corrida a «en progreso»).
create or replace function public.tg_checklist_run_checkpoint()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'in_progress' and old.status in ('pending','reopened') and new.checkpoint_scanned_at is null
     and exists (select 1 from public.checklist_templates t where t.id = new.template_id and t.checkpoint_required)
     and coalesce(current_setting('operalia.bypass', true), '') <> 'on' then
    raise exception 'Escanea el código QR del punto para iniciar este checklist';
  end if;
  return new;
end $$;
drop trigger if exists trg_checklist_run_checkpoint on public.checklist_runs;
create trigger trg_checklist_run_checkpoint before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_checkpoint();

create or replace function public.start_checklist_with_checkpoint(p_run_id uuid, p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  r          public.checklist_runs%rowtype;
  v_expected uuid;
  v_scanned  public.checkpoints%rowtype;
begin
  select * into r from public.checklist_runs where id = p_run_id;
  if not found or r.company_id <> public.auth_company_id()
     or not public.has_permission('fill_checklists')
     or not public.can_access_department(r.branch_id, r.department_id) then
    raise exception 'No puedes iniciar este checklist';
  end if;
  if r.status not in ('pending','reopened','in_progress') then
    raise exception 'Este checklist ya no se puede iniciar';
  end if;

  v_expected := public.checkpoint_for_run(p_run_id);
  if v_expected is null then
    raise exception 'Esta sucursal no tiene registrado el punto QR de este checklist; pide al gerente que lo cree';
  end if;
  select * into v_scanned from public.checkpoints where upper(code) = upper(trim(p_code));
  if not found or v_scanned.id <> v_expected then
    raise exception 'Código incorrecto: escanea el QR de «%»', (select name from public.checkpoints where id = v_expected);
  end if;

  update public.checklist_runs
     set checkpoint_scanned_at = now(), checkpoint_id = v_scanned.id,
         status = case when status in ('pending','reopened') then 'in_progress' else status end
   where id = p_run_id;
  return jsonb_build_object('run_id', p_run_id, 'checkpoint', v_scanned.name);
end $$;
revoke all on function public.start_checklist_with_checkpoint(uuid, text) from public, anon;
grant execute on function public.start_checklist_with_checkpoint(uuid, text) to authenticated;

-- v_checklist_runs: datos del punto QR.
drop view if exists public.v_checklist_runs;
create view public.v_checklist_runs with (security_invoker = on) as
select r.*, t.title, t.shift, t.requires_evidence, t.description as template_description,
       t.repeat_every_minutes, t.checkpoint_required,
       (select m.name from public.checkpoints m where m.id = t.checkpoint_id) as checkpoint_name,
       d.name as department_name, d.color as department_color, b.name as branch_name,
       es.full_name as started_by_name, ec.full_name as completed_by_name, ev.full_name as reviewed_by_name,
       (select count(*) from public.checklist_questions q where q.template_id = r.template_id and q.is_active) as total_questions,
       (select count(*) from public.checklist_answers a
         where a.run_id = r.id and coalesce(trim(a.answer_value), '') <> '') as answered_questions,
       (select count(*) from public.evidence_files e
         where (e.entity_type = 'checklist_run' and e.entity_id = r.id)
            or (e.entity_type = 'checklist_answer'
                and e.entity_id in (select a.id from public.checklist_answers a where a.run_id = r.id))) as evidence_count
from public.checklist_runs r
join public.checklist_templates t on t.id = r.template_id
join public.branches b on b.id = r.branch_id
left join public.departments d on d.id = r.department_id
left join public.employees es on es.id = r.started_by
left join public.employees ec on ec.id = r.completed_by
left join public.employees ev on ev.id = r.reviewed_by;
grant select on public.v_checklist_runs to authenticated;
