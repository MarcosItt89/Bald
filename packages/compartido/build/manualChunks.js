/**
 * Partición del bundle compartida por las dos apps (vite.config.js de cada una).
 * Las librerías grandes y estables van en su propio archivo: el navegador las
 * guarda en caché entre despliegues y el bundle principal queda chico.
 *   react    react, react-dom, react-router y scheduler
 *   supabase @supabase/*
 *   lucide   íconos
 * ZXing (escáner) ya se carga aparte, bajo demanda.
 */
const GROUPS = [
  ['react', /node_modules[\\/](react|react-dom|react-router|react-router-dom|scheduler)[\\/]/],
  ['supabase', /node_modules[\\/]@supabase[\\/]/],
  ['lucide', /node_modules[\\/]lucide-react[\\/]/],
]

export function manualChunks(id) {
  return GROUPS.find(([, re]) => re.test(id))?.[0]
}
