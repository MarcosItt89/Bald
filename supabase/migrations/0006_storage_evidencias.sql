-- =============================================================================
-- OPERALIA · 0006 · STORAGE (archivos de evidencia)
-- -----------------------------------------------------------------------------
-- Objetivo: bucket privado "evidence" para fotos y PDFs.
--
-- Estructura de rutas (la arma src/services/evidenceService.js):
--     {company_id}/{entity_type}/{yyyy-mm}/{uuid}.{ext}
--
-- La primera carpeta es la empresa → las políticas solo permiten leer/subir
-- dentro de la carpeta de tu propia empresa. Las imágenes se muestran con
-- URLs firmadas temporales (createSignedUrl), nunca públicas.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('evidence', 'evidence', false, 10485760, -- 10 MB
        array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists evidence_objects_select on storage.objects;
drop policy if exists evidence_objects_insert on storage.objects;
drop policy if exists evidence_objects_delete on storage.objects;

create policy evidence_objects_select on storage.objects for select to authenticated
  using (bucket_id = 'evidence'
         and (storage.foldername(name))[1] = (select public.auth_company_id())::text);

create policy evidence_objects_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'evidence'
              and (storage.foldername(name))[1] = (select public.auth_company_id())::text
              and ((select public.has_permission('upload_evidence')) or (select public.has_permission('create_tickets'))));

-- Solo quien subió el archivo puede borrarlo.
create policy evidence_objects_delete on storage.objects for delete to authenticated
  using (bucket_id = 'evidence' and owner_id = (select auth.uid())::text);
