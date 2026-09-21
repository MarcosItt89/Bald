// TODO: Replace mock functions with real Supabase queries
// import { supabase } from '../lib/supabaseClient'

import { MOCK_PRODUCTS } from '../data/mockData'

export const getInventory = async (branchId) => {
  // TODO: return supabase.from('inventory').select('*, products(*)').eq('branch_id', branchId)
  return { data: MOCK_PRODUCTS, error: null }
}

export const searchProducts = async (query) => {
  // TODO: return supabase.from('products').select('*').or(`name.ilike.%${query}%,sku.eq.${query},barcode.eq.${query}`)
  const data = MOCK_PRODUCTS.filter(p =>
    p.name.toLowerCase().includes(query.toLowerCase()) ||
    p.sku.includes(query) ||
    p.barcode.includes(query)
  )
  return { data, error: null }
}

export const updateStock = async (productId, quantity, type, employeeId) => {
  // TODO: Insert into inventory_movements, trigger will update inventory.stock
  console.log('updateStock mock:', { productId, quantity, type, employeeId })
  return { data: null, error: null }
}
