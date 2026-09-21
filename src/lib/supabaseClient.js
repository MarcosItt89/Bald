import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// TODO: Connect real auth and RLS when backend tables are ready
export const supabase = createClient(supabaseUrl, supabaseAnonKey)
