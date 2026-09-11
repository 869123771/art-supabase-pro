import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import dayjs from 'dayjs'
import { buildMaterialCodePreview } from '../../modules/art-supabase-mdm/src/views/material/reference/modules/material-code-preview'

describe('buildMaterialCodePreview', () => {
  it('uses business prefix values and pads before the fixed field', () => {
    assert.deepEqual(
      buildMaterialCodePreview({
        fixedField: 'X',
        segments: [{ source: 'material_type' }, { source: 'date', format: 'YYYY' }],
        sequenceDigits: 4,
        codeLength: 12,
        materialTypePrefix: 'RM',
        date: dayjs('2026-09-11')
      }),
      { code: 'RM20260X0001', overflow: 0, padding: 1 }
    )
  })

  it('reports overflow instead of truncating the generated code', () => {
    assert.deepEqual(
      buildMaterialCodePreview({
        fixedField: '-',
        segments: [{ source: 'material_category' }],
        sequenceDigits: 4,
        codeLength: 5,
        materialCategoryPrefix: 'LONG'
      }),
      { code: 'LONG-0001', overflow: 4, padding: 0 }
    )
  })
})
