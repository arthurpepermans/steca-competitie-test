import type { Attendance } from "./types";

export function aanwezigeSpelerIds(matchKey: string | null, aanwezigheden: Attendance[]): Set<string> {
  return new Set(aanwezigheden.filter((a) => a.match_key === matchKey && a.status === "aanwezig").map((a) => a.member_id));
}

export function nietAanwezigeKeuzes(keuze: Record<string, string | null>, aanwezig: Set<string>): string[] {
  return [...new Set(Object.values(keuze).filter((id): id is string => Boolean(id) && !aanwezig.has(id!)))];
}

/** Alleen in deze testrepository: beheerders kunnen hun eigen badgeweergave testen. */
export function isOpstelbaarInTest(lid: {status:string;speelt:boolean;is_admin:boolean;is_hoofdadmin:boolean}):boolean {
  return lid.status==='actief' && (lid.speelt || lid.is_admin || lid.is_hoofdadmin);
}
