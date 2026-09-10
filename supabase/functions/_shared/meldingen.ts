export type Soort = 'aanwezig72' | 'aanwezig48' | 'stemmen' | 'stemherinnering';
export type Situatie = { aftrap: number; scoreAt: number | null; antwoord: boolean; aanwezig: boolean; gestemd: boolean; eersteVerzonden: number | null; deadline: number };
const UUR = 3600000;
export function verschuldigd(s: Situatie, nu: number): Soort[] {
  if (!Number.isFinite(s.aftrap)) return [];
  if (!s.antwoord && nu >= s.aftrap - 72 * UUR && nu < s.aftrap) return [nu < s.aftrap - 48 * UUR ? 'aanwezig72' : 'aanwezig48'];
  if (s.scoreAt === null || !s.aanwezig || s.gestemd || nu >= s.deadline || nu < Math.max(s.aftrap + 80 * 60000, s.scoreAt)) return [];
  if (s.eersteVerzonden === null) return ['stemmen'];
  return nu >= s.eersteVerzonden + 3 * UUR ? ['stemherinnering'] : [];
}
export function bericht(soort: Soort, tegenstander: string) {
  if (soort === 'aanwezig72') return { title: 'Speel je mee?', body: `Nog 72 uur tot de match tegen ${tegenstander}. Vul je aanwezigheid in.` };
  if (soort === 'aanwezig48') return { title: 'Je aanwezigheid ontbreekt nog', body: `De match tegen ${tegenstander} is over 48 uur. Laat weten of je erbij bent.` };
  if (soort === 'stemmen') return { title: 'Wie wordt Junior van de match?', body: `De uitslag tegen ${tegenstander} staat klaar. Breng je stem uit.` };
  return { title: 'Jouw stem telt nog mee', body: `Je hebt nog niet gestemd voor Junior van de match tegen ${tegenstander}.` };
}
// Geen zelf opgegeven tijdzones: aftraptijden worden in de database naar UTC omgerekend.
export const TEST_PROJECT = 'https://fhgghcksvnyxfwkielzx.supabase.co';
export const TEST_ORIGIN = 'https://test.stecajuniors.app';
