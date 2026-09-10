import { useState } from "react";
import { zetWasbeurt } from "../lib/api";
import { fmtDatum, isThuis, sorteerOpDatum, tegenstander } from "../lib/datum";
import { foutTekst } from "../lib/useAsync";
import type { LaundryTurn, Match } from "../lib/types";

type Speler = { id: string; naam: string };

/** Wasmand vol voetbaltruitjes, in de kleuren van de shirts op het veld. */
export function WasmandTekening() {
  const truitjes = [
    { x: 22, y: 26, r: -22 }, { x: 60, y: 14, r: 6 }, { x: 98, y: 24, r: 24 }, { x: 42, y: 38, r: -8 }, { x: 80, y: 40, r: 12 },
  ];
  return (
    <svg className="wasmand-tekening" viewBox="0 0 150 140" role="img" aria-label="Wasmand vol truitjes">
      <g transform="translate(0 4)">
        {truitjes.map((t, i) => (
          <g key={i} transform={`translate(${t.x} ${t.y}) rotate(${t.r}) scale(.72)`}>
            <path d="M19 5 9 10 2 25 13 30 17 23 17 57 43 57 43 23 47 30 58 25 51 10 41 5 36 11 24 11Z" fill="#292929" stroke="#171717" strokeWidth="2" strokeLinejoin="round" />
            <path d="M18 25h24v17H18Z" fill="#f8f5e9" />
            <path d="M21 6q9 13 18 0M3 24l10 5M47 29l10-5" fill="none" stroke="#f8f5e9" strokeWidth="2" />
          </g>
        ))}
      </g>
      {/* rieten mand voor de truitjes */}
      <path d="M14 62 26 132h98l12-70Z" fill="#c9a24f" stroke="#332e24" strokeWidth="3" strokeLinejoin="round" />
      <g stroke="#8a6a2e" strokeWidth="2" fill="none" opacity=".8">
        <path d="M20 78h110M23 94h104M26 110h98M29 124h92" />
        <path d="M34 63l10 69M54 63l6 69M75 63v69M96 63l-6 69M116 63l-10 69" />
      </g>
      <path d="M10 56h130v10H10Z" fill="#d9b565" stroke="#332e24" strokeWidth="3" strokeLinejoin="round" />
      <path d="M40 56c0-14 70-14 70 0" fill="none" stroke="#332e24" strokeWidth="4" strokeLinecap="round" />
    </svg>
  );
}

type KeuzeProps = {
  match: Match;
  beurt: LaundryTurn | undefined;
  spelers: Speler[];
  beschikbaar: Speler[];
  isStaf: boolean;
  fout?: string | null;
  onGewijzigd: () => Promise<void> | void;
};

/** Onder de bank op de opstellingspagina: wie neemt de wasmand mee naar huis. */
export function WasmandKeuze({ match, beurt, spelers, beschikbaar, isStaf, fout: laadFout, onGewijzigd }: KeuzeProps) {
  const [bezig, setBezig] = useState(false);
  const [fout, setFout] = useState<string | null>(null);
  const naam = beurt ? spelers.find((p) => p.id === beurt.member_id)?.naam ?? "onbekende speler" : null;
  // Iedereen is te kiezen, ook wie niet op aanwezig staat; de aanwezigen staan bovenaan.
  const aanwezigIds = new Set(beschikbaar.map((p) => p.id));
  const keuzelijst = [...spelers].sort((a, b) => Number(aanwezigIds.has(b.id)) - Number(aanwezigIds.has(a.id)) || a.naam.localeCompare(b.naam, "nl"));

  async function zet(memberId: string | null) {
    setBezig(true);
    setFout(null);
    try {
      await zetWasbeurt(match.match_key, memberId);
      await onGewijzigd();
    } catch (e) {
      setFout(foutTekst(e));
    } finally {
      setBezig(false);
    }
  }

  return (
    <section className="kaart wasmand-blok" aria-label="Wasmand">
      <WasmandTekening />
      <div className="wasmand-tekst">
        <h3>De wasmand</h3>
        {laadFout ? (
          <p className="zacht">De wasbeurten konden niet geladen worden.</p>
        ) : (
          <p>{naam ? <>Gaat mee met <strong>{naam}</strong>.</> : <span className="zacht">Nog niemand aangeduid voor deze match.</span>}</p>
        )}
        {fout && <div className="melding fout">{fout}</div>}
        {isStaf && !laadFout && (
          <div className="veld" style={{ marginBottom: 0 }}>
            <label htmlFor={`wasmand-${match.match_key}`}>Wie neemt de mand mee?</label>
            <select id={`wasmand-${match.match_key}`} disabled={bezig} value={beurt?.member_id ?? ""} onChange={(e) => zet(e.target.value || null)}>
              <option value="">Nog niet aangeduid</option>
              {keuzelijst.map((p) => <option key={p.id} value={p.id}>{p.naam}{aanwezigIds.size > 0 && !aanwezigIds.has(p.id) ? " (niet op aanwezig)" : ""}</option>)}
            </select>
            <span className="klein zacht">De speler krijgt 100 minuten na de aftrap een melding. Zorg dat de mand bij de volgende match terug is.</span>
          </div>
        )}
      </div>
    </section>
  );
}

type TabelProps = {
  matches: Match[];
  beurten: LaundryTurn[];
  ledenNamen: Map<string, string>;
  eigenLidId: string | null;
};

/** Tabblad Wasmand bij het klassement: per match wie de mand mee naar huis nam. */
export function WasmandTabel({ matches, beurten, ledenNamen, eigenLidId }: TabelProps) {
  const perMatch = new Map(beurten.map((b) => [b.match_key, b]));
  const rijen = sorteerOpDatum(matches).reverse();
  const teller = new Map<string, number>();
  for (const b of beurten) teller.set(b.member_id, (teller.get(b.member_id) ?? 0) + 1);
  return (
    <>
      <div className="tabel-wrap">
        <table className="tabel">
          <thead><tr><th>Match</th><th>Wasmand</th></tr></thead>
          <tbody>
            {rijen.map((m) => {
              const b = perMatch.get(m.match_key);
              return (
                <tr key={m.match_key} className={b && b.member_id === eigenLidId ? "eigen" : ""}>
                  <td style={{ whiteSpace: "normal" }}>{fmtDatum(m.datum)}<br /><span className="zacht">{isThuis(m) ? "thuis" : "uit"} tegen {tegenstander(m)}</span></td>
                  <td style={{ whiteSpace: "normal" }}>{b ? ledenNamen.get(b.member_id) ?? "onbekende speler" : <span className="zacht">{m.status === "gespeeld" ? "niet ingevuld" : "nog niet aangeduid"}</span>}</td>
                </tr>
              );
            })}
            {rijen.length === 0 && <tr><td colSpan={2} className="zacht">Nog geen matchen.</td></tr>}
          </tbody>
        </table>
      </div>
      <p className="klein zacht">Elke speler is één keer per seizoen verantwoordelijk voor de wasmand. De coach of verantwoordelijke duidt de speler aan bij de opstelling.</p>
      {teller.size > 0 && (
        <p className="klein zacht">
          Al geweest: {[...teller.entries()].map(([id, n]) => `${ledenNamen.get(id) ?? "?"}${n > 1 ? ` (${n}×)` : ""}`).join(", ")}.
        </p>
      )}
    </>
  );
}
