import { createClient } from '@supabase/supabase-js'
import { isSupabaseApi } from '@/config/api-provider'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'http://localhost'
const supabaseKey = import.meta.env.VITE_SUPABASE_KEY || 'java-api-provider'

if (isSupabaseApi && (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_KEY)) {
  throw new Error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_KEY')
}

export const supabase = createClient(supabaseUrl, supabaseKey)
