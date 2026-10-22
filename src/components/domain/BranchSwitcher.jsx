/**
 * BranchSwitcher — selector de sucursal del Topbar.
 *
 * Solo aparece para roles con alcance "empresa" (admin, auditor, soporte) o
 * "zona" (jefe de escáner: solo las sucursales de sus zonas).
 * El resto de usuarios siempre trabaja sobre su propia sucursal.
 * La elección se guarda en localStorage (AuthProvider → activeBranchId).
 */
import { useCallback, useEffect } from 'react'
import { Building2 } from 'lucide-react'
import { useAuth } from '../../hooks/useAuth'
import { useAsync } from '../../hooks/useAsync'
import { getMyBranches } from '../../services/organizationService'

export default function BranchSwitcher() {
  const { isCompanyScope, isZoneScope, isMultiBranch, zoneIds, activeBranchId, setActiveBranchId, profile } = useAuth()
  const zoneKey = zoneIds.join(',')
  const load = useCallback(
    () => getMyBranches({ isCompanyScope, isZoneScope, zoneIds: zoneKey ? zoneKey.split(',') : [] }),
    [isCompanyScope, isZoneScope, zoneKey],
  )
  const { data: branches } = useAsync(load)

  // Una sucursal guardada que ya no está en sus zonas se descarta.
  useEffect(() => {
    if (branches && activeBranchId && !branches.some((b) => b.id === activeBranchId)) setActiveBranchId(null)
  }, [branches, activeBranchId, setActiveBranchId])

  if (!isMultiBranch) {
    return (
      <span className="topbar-branch"><Building2 size={14} /> {profile?.branch_name ?? 'Sin sucursal'}</span>
    )
  }

  return (
    <label className="branch-switcher">
      <Building2 size={14} />
      <select value={activeBranchId ?? ''} onChange={(e) => setActiveBranchId(e.target.value || null)}
        aria-label="Sucursal de trabajo">
        <option value="">{isZoneScope ? `Mis sucursales (${(profile?.zone_names ?? []).join(', ')})` : 'Todas las sucursales'}</option>
        {(branches ?? []).map((b) => <option key={b.id} value={b.id}>{b.code} · {b.name}</option>)}
      </select>
    </label>
  )
}
