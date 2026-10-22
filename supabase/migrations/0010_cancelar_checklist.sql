-- =============================================================================
-- OPERALIA · 0010 · CANCELAR UN CHECKLIST DEL DÍA
-- -----------------------------------------------------------------------------
-- Caso: un departamento no abrió o el checklist no aplica hoy.
--   * Solo quien tiene review_checklists puede cancelar.
--   * Se exige motivo (se guarda en review_comment) y queda quién/cuándo.
--   * No se cancelan checklists completados (lo impide tg_checklist_run_rules).
-- Re-ejecutable.
-- =============================================================================
create or replace function public.tg_checklist_run_cancel()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' and not public.is_system_context() then
    if not public.has_permission('review_checklists') then
      raise exception 'Solo un supervisor puede cancelar checklists';
    end if;
    if coalesce(trim(new.review_comment), '') = '' then
      raise exception 'Indica el motivo de la cancelación';
    end if;
    new.reviewed_by := public.auth_employee_id();
    new.reviewed_at := now();
  end if;
  return new;
end $$;

drop trigger if exists trg_checklist_run_cancel on public.checklist_runs;
create trigger trg_checklist_run_cancel before update on public.checklist_runs
  for each row execute function public.tg_checklist_run_cancel();
