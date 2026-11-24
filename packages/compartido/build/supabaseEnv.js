/**
 * Variables de Supabase para el build (vite.config.js de tiendas y Consola).
 *
 * Acepta los nombres que usamos (VITE_SUPABASE_URL y VITE_SUPABASE_PUBLISHABLE_KEY
 * o VITE_SUPABASE_ANON_KEY) y también los que crea la integración Supabase ↔ Vercel
 * (NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY, SUPABASE_URL /
 * SUPABASE_ANON_KEY). Solo la URL y la llave PÚBLICA: nunca la service_role.
 *
 * En Vercel, si faltan, el build FALLA a propósito: así no se publica una app que
 * solo muestra «Falta configurar Supabase» y sigue en línea la versión anterior.
 */
import process from 'node:process'
import { loadEnv } from 'vite'

const first = (env, names) => names.map((n) => env[n]).find((v) => v && String(v).trim())

export function supabaseDefine(mode, envDir) {
  const env = { ...loadEnv(mode, envDir, ''), ...process.env }
  const url = first(env, ['VITE_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL'])
  const key = first(env, [
    'VITE_SUPABASE_PUBLISHABLE_KEY', 'VITE_SUPABASE_ANON_KEY',
    'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
    'SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY',
  ])

  if ((!url || !key) && process.env.VERCEL) {
    const faltan = [!url && 'VITE_SUPABASE_URL', !key && 'VITE_SUPABASE_PUBLISHABLE_KEY (o VITE_SUPABASE_ANON_KEY)'].filter(Boolean)
    throw new Error(
      `Faltan variables de Supabase en Vercel (entorno «${process.env.VERCEL_ENV}»): ${faltan.join(' y ')}. `
      + 'Agrégalas en Settings → Environment Variables marcando Production Y Preview, y vuelve a desplegar.',
    )
  }

  return {
    'import.meta.env.VITE_SUPABASE_URL': JSON.stringify(url ?? ''),
    'import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY': JSON.stringify(key ?? ''),
  }
}
