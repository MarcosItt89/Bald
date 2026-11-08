-- =============================================================================
-- OPERALIA · 0028 · MARCA POR EMPRESA
-- -----------------------------------------------------------------------------
--   * companies: brand_color (#RRGGBB, por defecto el azul de Operalia) y
--     display_name (nombre visible). logo_url ya existía.
--   * La marca (logo_url, brand_color, display_name) solo la cambia un
--     superadmin o el propietario de ESA empresa (trigger, aplica también a
--     la API directa). set_company_branding() es la forma de guardarla.
--   * Bucket público company-branding: carpeta {company_id}/; sube y borra
--     solo el superadmin o el propietario; lectura pública. 500 KB,
--     PNG / SVG / WebP.
--   * get_company_branding(código): para la pantalla de login (anon). Solo
--     devuelve name, display_name, logo_url y brand_color de una empresa activa.
--   * get_my_profile() trae la marca de la empresa del empleado.
-- Re-ejecutable.
-- =============================================================================

-- ─── 1. Columnas ────────────────────────────────────────────────────────────
alter table public.companies add column if not exists brand_color text not null default '#2563eb';
alter table public.companies add column if not exists display_name text;

do $$ begin
  alter table public.companies add constraint companies_brand_color_chk check (brand_color ~ '^#[0-9a-fA-F]{6}$');
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.companies add constraint companies_display_name_chk
    check (display_name is null or length(trim(display_name)) between 1 and 60);
exception when duplicate_object then null; end $$;

-- ─── 2. Quién cambia la marca ───────────────────────────────────────────────
-- companies_update (0023) ya exige propietario o superadmin para editar la
-- empresa propia; este trigger cubre además el caso del superadmin editando
-- otra empresa (vía set_company_branding) y deja la regla explícita.
create or replace function public.tg_company_branding_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.logo_url, new.brand_color, new.display_name) is distinct from (old.logo_url, old.brand_color, old.display_name)
     and not public.is_system_context()
     and not public.is_platform_admin()
     and not (public.auth_is_owner() and new.id = public.auth_company_id()) then
    raise exception 'Solo el propietario de la empresa o un superadmin cambia su marca';
  end if;
  return new;
end $$;
drop trigger if exists trg_company_branding_guard on public.companies;
create trigger trg_company_branding_guard before update on public.companies
  for each row execute function public.tg_company_branding_guard();

-- Guarda la marca. El propietario, solo la de su empresa; el superadmin, la de
-- cualquiera. p_logo_url debe ser un archivo del bucket company-branding de
-- esa empresa (o null para quitar el logo).
create or replace function public.set_company_branding(
  p_company_id uuid, p_display_name text, p_brand_color text, p_logo_url text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_color text := lower(trim(coalesce(p_brand_color, '')));
  v_name  text := nullif(trim(coalesce(p_display_name, '')), '');
  v_logo  text := nullif(trim(coalesce(p_logo_url, '')), '');
  v_prev  text;
begin
  if not public.is_platform_admin()
     and not (public.auth_is_owner() and p_company_id is not distinct from public.auth_company_id()) then
    raise exception 'Solo el propietario de la empresa o un superadmin cambia su marca';
  end if;
  if not exists (select 1 from public.companies where id = p_company_id) then
    raise exception 'Empresa no encontrada';
  end if;
  if v_color !~ '^#[0-9a-f]{6}$' then raise exception 'Color inválido: usa el formato #RRGGBB'; end if;
  if v_name is not null and length(v_name) > 60 then raise exception 'El nombre visible admite hasta 60 caracteres'; end if;
  if v_logo is not null and position('/storage/v1/object/public/company-branding/' || p_company_id || '/' in v_logo) = 0 then
    raise exception 'El logo debe estar en la carpeta de la empresa (bucket company-branding)';
  end if;

  v_prev := public.set_bypass('on');
  update public.companies
     set display_name = v_name, brand_color = v_color, logo_url = v_logo
   where id = p_company_id;
  insert into public.audit_logs (company_id, table_name, record_id, action, performed_by, new_data)
  values (p_company_id, 'companies', p_company_id::text, 'UPDATE', public.auth_employee_id(),
          jsonb_build_object('evento', 'marca_actualizada', 'display_name', v_name, 'brand_color', v_color,
                             'logo_url', v_logo, 'por', auth.uid()));
  perform public.set_bypass(v_prev);
  return jsonb_build_object('display_name', v_name, 'brand_color', v_color, 'logo_url', v_logo);
end $$;
revoke all on function public.set_company_branding(uuid, text, text, text) from public, anon;
grant execute on function public.set_company_branding(uuid, text, text, text) to authenticated;

-- ─── 3. Bucket company-branding ─────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('company-branding', 'company-branding', true, 512000,
        array['image/png', 'image/svg+xml', 'image/webp'])
on conflict (id) do update
  set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ¿Quien llama puede administrar la marca de la empresa de esta carpeta?
create or replace function public.can_manage_branding_folder(p_folder text)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_platform_admin()
      or (public.auth_is_owner() and p_folder = public.auth_company_id()::text)
$$;
revoke all on function public.can_manage_branding_folder(text) from public, anon;
grant execute on function public.can_manage_branding_folder(text) to authenticated;

drop policy if exists branding_objects_select on storage.objects;
drop policy if exists branding_objects_insert on storage.objects;
drop policy if exists branding_objects_update on storage.objects;
drop policy if exists branding_objects_delete on storage.objects;
-- Lectura pública (el bucket es público; la política permite además listar).
create policy branding_objects_select on storage.objects for select to anon, authenticated
  using (bucket_id = 'company-branding');
create policy branding_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'company-branding' and (select public.can_manage_branding_folder((storage.foldername(name))[1])));
create policy branding_objects_update on storage.objects for update to authenticated
  using (bucket_id = 'company-branding' and (select public.can_manage_branding_folder((storage.foldername(name))[1])))
  with check (bucket_id = 'company-branding' and (select public.can_manage_branding_folder((storage.foldername(name))[1])));
create policy branding_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'company-branding' and (select public.can_manage_branding_folder((storage.foldername(name))[1])));

-- ─── 4. Marca para la pantalla de login (sin sesión) ────────────────────────
create or replace function public.get_company_branding(p_code text)
returns table (name text, display_name text, logo_url text, brand_color text)
language sql stable security definer set search_path = public as $$
  select c.name, c.display_name, c.logo_url, c.brand_color
  from public.companies c
  where c.code = lower(trim(coalesce(p_code, ''))) and c.status = 'active'
$$;
revoke all on function public.get_company_branding(text) from public;
grant execute on function public.get_company_branding(text) to anon, authenticated;

-- ─── 5. Perfil (0023) + marca de la empresa ─────────────────────────────────
create or replace function public.get_my_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', e.id, 'user_id', e.user_id, 'username', e.username, 'full_name', e.full_name,
    'employee_code', e.employee_code, 'position', e.position, 'email', e.email,
    'company_id', e.company_id, 'company_name', c.name, 'company_code', c.code,
    'company_display_name', c.display_name, 'company_logo_url', c.logo_url, 'company_brand_color', c.brand_color,
    'branch_id', e.branch_id, 'branch_name', b.name,
    'department_id', e.department_id, 'department_name', d.name,
    'role_id', r.id, 'role_code', r.code, 'role_name', r.name, 'role_scope', r.scope,
    'is_owner', e.is_owner,
    'is_platform_admin', public.is_platform_admin(),
    'zone_ids', coalesce((select jsonb_agg(ez.zone_id) from public.employee_zones ez where ez.employee_id = e.id), '[]'::jsonb),
    'zone_names', coalesce((select jsonb_agg(z.name order by z.name) from public.employee_zones ez
                              join public.zones z on z.id = ez.zone_id where ez.employee_id = e.id), '[]'::jsonb),
    'permissions', coalesce((select jsonb_agg(p) from public.my_permissions() p), '[]'::jsonb)
  )
  from public.employees e
  join public.companies c on c.id = e.company_id and c.status = 'active'
  join public.roles r on r.id = e.role_id
  left join public.branches b on b.id = e.branch_id
  left join public.departments d on d.id = e.department_id
  where e.user_id = auth.uid() and e.status = 'active'
  limit 1
$$;
