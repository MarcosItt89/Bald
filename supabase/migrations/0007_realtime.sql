-- =============================================================================
-- OPERALIA · 0007 · REALTIME
-- -----------------------------------------------------------------------------
-- Objetivo: que la campana de notificaciones y los tickets se actualicen en
-- vivo sin recargar. Supabase Realtime respeta RLS: cada usuario solo recibe
-- sus propias notificaciones.
-- =============================================================================
do $$
declare t text;
begin
  foreach t in array array['notifications','support_ticket_messages'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null; -- ya estaba agregada
    end;
  end loop;
end $$;
