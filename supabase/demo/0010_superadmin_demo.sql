-- =============================================================================
-- OPERALIA · DEMO 0010 · SUPERADMIN DE PRUEBAS
-- -----------------------------------------------------------------------------
-- SOLO PARA PRUEBAS (lo trae pendiente.sql, no instalacion-limpia.sql).
-- El usuario demo «gatopelon» (contraseña de prueba, demo/0009) queda como
-- superadmin de la plataforma para probar la Consola. En producción el
-- superadmin es una persona con su propio correo: README → «Nombrar al
-- superadmin real». verificar.sql marca ❌ si un superadmin es un usuario demo.
-- Re-ejecutable. Solo aplica si la cuenta demo existe.
-- =============================================================================
insert into public.platform_admins (user_id)
select e.user_id from public.employees e
where e.company_id = 'c0000000-0000-4000-8000-000000000001' and lower(e.username) = 'gatopelon' and e.user_id is not null
on conflict do nothing;
