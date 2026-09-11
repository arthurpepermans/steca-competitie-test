import { describe, expect, it } from "vitest";
import { aanwezigeSpelerIds, nietAanwezigeKeuzes, isOpstelbaarInTest } from "./opstellingAanwezigheid";
import type { Attendance } from "./types";

const antwoord = (member_id: string, status: Attendance["status"], match_key = "match-a"): Attendance => ({ member_id, status, match_key, gezet_door: null, updated_at: "2026-09-09" });

describe("opstellen op basis van aanwezigheid", () => {
  it("laat alleen expliciet aanwezige spelers van de gekozen wedstrijd toe", () => {
    const rows = [antwoord("a", "aanwezig"), antwoord("b", "afwezig"), antwoord("c", "onzeker"), antwoord("d", "aanwezig", "match-b")];
    expect([...aanwezigeSpelerIds("match-a", rows)]).toEqual(["a"]);
    expect([...aanwezigeSpelerIds(null, rows)]).toEqual([]);
  });
  it("controleert ook bankspelers en spelers zonder antwoord", () => {
    expect(nietAanwezigeKeuzes({ GK: "a", BANK1: "b", BANK2: null, ST: "geen-antwoord" }, new Set(["a"]))).toEqual(["b", "geen-antwoord"]);
  });
  it("markeert een bestaande keuze na een wijziging naar onzeker", () => {
    const keuze = { GK: "a", BANK1: "b" };
    expect(nietAanwezigeKeuzes(keuze, aanwezigeSpelerIds("match-a", [antwoord("a", "aanwezig"), antwoord("b", "aanwezig")]))).toEqual([]);
    expect(nietAanwezigeKeuzes(keuze, aanwezigeSpelerIds("match-a", [antwoord("a", "aanwezig"), antwoord("b", "onzeker")]))).toEqual(["b"]);
  });
});

it('maakt actieve testbeheerders opstelbaar zonder hun spelersfunctie te veranderen',()=>{
  const lid={status:'actief',speelt:false,is_admin:false,is_hoofdadmin:false};
  expect(isOpstelbaarInTest(lid)).toBe(false);
  expect(isOpstelbaarInTest({...lid,is_admin:true})).toBe(true);
  expect(isOpstelbaarInTest({...lid,is_hoofdadmin:true})).toBe(true);
  expect(isOpstelbaarInTest({...lid,speelt:true})).toBe(true);
  expect(isOpstelbaarInTest({...lid,is_admin:true,status:'inactief'})).toBe(false);
});
