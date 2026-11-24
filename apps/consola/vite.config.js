// Consola Operalia (superadmins). Sin PWA: es una herramienta de escritorio.
// envDir: lee el .env de la raíz del repo (las mismas VITE_SUPABASE_* que la app de tiendas).
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { manualChunks } from '../../packages/compartido/build/manualChunks.js'
import { supabaseDefine } from '../../packages/compartido/build/supabaseEnv.js'

export default defineConfig(({ mode }) => ({
  envDir: '../..',
  server: { port: 5174 },
  preview: { port: 4174 },
  // Marca el build como Consola (env.app en el paquete compartido).
  // Supabase (acepta también los nombres de la integración con Vercel) y build marcado como Consola.
  define: { ...supabaseDefine(mode, '../..'), 'import.meta.env.VITE_OPERALIA_APP': JSON.stringify('consola') },
  build: { rolldownOptions: { output: { manualChunks } } },
  plugins: [react()],
}))
