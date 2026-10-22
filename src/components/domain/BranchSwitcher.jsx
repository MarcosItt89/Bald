/**
 * BranchSwitcher — selector de sucursal del Topbar.
 *
 * Solo aparece para roles con alcance "empresa" (admin, auditor, soporte).
 * El resto de usuarios siempre trabaja sobre su propia sucursal.
 * La elección se guarda en localStorage (AuthProvider → activeBranchId).
 */
import { useCallback } from 'react'
import { Building2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { getBranches } from '../../services/organizationService'

export default function BranchSwitcher() {
  const { isCompanyScope, activeBranchId, setActiveBranchId, profile } = useAuth()
  const load = useCallback(() => (isCompanyScope ? getBranches({ onlyActive: true }) : Promise.resolve([])), [isCompanyScope])
  const { data: branches = [] } = useAsync(load)

  if (!isCompanyScope) {
    return (
      <span className="topbar-branch"><Building2 size={14} /> {profile?.branch_name ?? 'Sin sucursal'}</span>
    )
  }

  return (
    <label className="branch-switcher">
      <Building2 size={14} />
      <select value={activeBranchId ?? ''} onChange={(e) => setActiveBranchId(e.target.value || null)}
        aria-label="Sucursal de trabajo">
        <option value="">Todas las sucursales</option>
        {branches.map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
      </select>
    </label>
  )
}
