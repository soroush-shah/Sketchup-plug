// Length/area formatting in the model's unit system (glTF space is meters).
export type LengthUnit = 'mm' | 'cm' | 'm' | 'in' | 'ft';

export function fmtLength(meters: number, unit: LengthUnit = 'mm', precision = 0): string {
  switch (unit) {
    case 'mm': return `${(meters * 1000).toFixed(Math.max(0, precision))} mm`;
    case 'cm': return `${(meters * 100).toFixed(Math.max(1, precision))} cm`;
    case 'm': return `${meters.toFixed(Math.max(3, precision))} m`;
    case 'in': return `${(meters / 0.0254).toFixed(Math.max(1, precision))}"`;
    case 'ft': {
      const totalIn = meters / 0.0254;
      const ft = Math.floor(totalIn / 12);
      const inch = totalIn - ft * 12;
      return `${ft}' ${inch.toFixed(1)}"`;
    }
  }
}

export function fmtArea(m2: number, unit: LengthUnit = 'mm'): string {
  if (unit === 'in' || unit === 'ft') return `${(m2 * 10.7639).toFixed(2)} ft²`;
  if (unit === 'mm' && m2 < 0.01) return `${(m2 * 1e6).toFixed(0)} mm²`;
  return `${m2.toFixed(m2 < 10 ? 3 : 2)} m²`;
}

export const fmtAngle = (rad: number) => `${((rad * 180) / Math.PI).toFixed(1)}°`;
