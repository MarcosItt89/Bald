-- =============================================================================
-- OPERALIA · 0029 · CONSOLA OPERALIA: MARCA DE CUALQUIER EMPRESA
-- -----------------------------------------------------------------------------
--   La Consola (apps/consola) edita la marca de cualquier empresa. RLS de
--   companies solo deja leer la propia, así que el superadmin lee la marca de
--   las demás con platform_get_company_branding(). Para guardarla ya existe
--   set_company_branding() (0028), que acepta superadmin.
--   A diferencia de get_company_branding() (login, pública), esta incluye las
--   empresas suspendidas y su id, código y estado.
-- Re-ejecutable.
-- =============================================================================

create or replace function public.platform_get_company_branding(p_company_id uuid)
returns table (id uuid, name text, code text, status text, display_name text, logo_url text, brand_color text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Solo un superadmin de la plataforma ve la marca de otras empresas';
  end if;
  return query
  select c.id, c.name, c.code, c.status, c.display_name, c.logo_url, c.brand_color
  from public.companies c
  where c.id = p_company_id;
end $$;
revoke all on function public.platform_get_company_branding(uuid) from public, anon;
grant execute on function public.platform_get_company_branding(uuid) to authenticated;
