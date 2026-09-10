import { useState } from "react";
import { Check } from "@phosphor-icons/react/dist/csr/Check";
import { X } from "@phosphor-icons/react/dist/csr/X";
import { Question } from "@phosphor-icons/react/dist/csr/Question";
import { aanwezigheden24u, zetAanwezigheid } from "../lib/api";
import { fmtTijdstip, magAanwezigheidWijzigen } from "../lib/datum";
import { foutTekst } from "../lib/useAsync";
import type { Aanwezigheid24u, AanwezigheidStatus, Attendance, Match } from "../lib/types";

const STATUSSEN: { code: AanwezigheidStatus; label: string; kort: string }[] = [
  { code: "aanwezig", label: "Aanwezig", kort: "Ja" },
  { code: "afwezig", label: "Afwezig", kort: "Nee" },
  { code: "onzeker", label: "Onzeker", kort: "?" },
];

type Speler = { id: string; naam: string };

type Props = {
  match: Match;
  spelers: Speler[];
  aanwezigheden: Attendance[];
  eigenLidId: string | null;
  isSpeler: boolean;
  isStaf: boolean;
  isAdmin: boolean;
  onGewijzigd: () => Promise<void> | void;
};

function Icoon({ code }: { code: AanwezigheidStatus }) {
  if (code === "aanwezig") return <Check size={18} aria-hidden="true" />;
  if (code === "afwezig") return <X size={18} aria-hidden="true" />;
  return <Question size={18} aria-hidden="true" />;
}

/** Eén keuzebalk met drie vakken; het gekozen vak is donker ingekleurd. */
function Keuzebalk({ stand, bezig, compact, onKies }: { stand?: AanwezigheidStatus; bezig: boolean; compact?: boolean; onKies: (s: AanwezigheidStatus) => void }) {
  return (
    <div className={`keuzebalk ${compact ? "compact" : ""}`} role="group" aria-label="Aanwezigheid">
      {STATUSSEN.map((s) => (
        <button key={s.code} type="button" disabled={bezig} aria-pressed={stand === s.code} className={s.code} onClick={() => onKies(s.code)}>
          {compact ? s.kort : <><Icoon code={s.code} /> {s.label}</>}
        </button>
      ))}
    </div>
  );
}

export function Aanwezigheid({ match, spelers, aanwezigheden, eigenLidId, isSpeler, isStaf, isAdmin, onGewijzigd }: Props) {
  const [fout, setFout] = useState<string | null>(null);
  const [bezig, setBezig] = useState(false);
  const [namenOpen, setNamenOpen] = useState(false);
  const [anderen, setAnderen] = useState(false);
  const [lijst24, setLijst24] = useState<Aanwezigheid24u[] | null>(null);
  const [lijst24Laden, setLijst24Laden] = useState(false);
  const magWijzigen = magAanwezigheidWijzigen(match);
  const perLid = new Map(aanwezigheden.filter((a) => a.match_key === match.match_key).map((a) => [a.member_id, a.status]));
  const eigenStatus = eigenLidId ? perLid.get(eigenLidId) : undefined;

  async function zet(memberId: string, status: AanwezigheidStatus) {
    setBezig(true);
    setFout(null);
    try {
      await zetAanwezigheid(match.match_key, memberId, status);
      await onGewijzigd();
    } catch (e) {
      setFout(foutTekst(e));
    } finally {
      setBezig(false);
    }
  }

  async function haal24() {
    if (lijst24 !== null) { setLijst24(null); return; }
    if (lijst24Laden) return;
    setLijst24Laden(true);
    try {
      setLijst24(await aanwezigheden24u(match.match_key));
    } catch (e) {
      setFout(foutTekst(e));
    } finally {
      setLijst24Laden(false);
    }
  }

  const groepen = STATUSSEN.map((s) => ({ ...s, namen: spelers.filter((p) => perLid.get(p.id) === s.code) }));
  const zonder = spelers.filter((p) => !perLid.has(p.id));
  const telling = `${groepen.map((g) => `${g.namen.length} ${g.label.toLowerCase()}`).join(" · ")} · ${zonder.length} nog niets`;
  const eigenTekst = bezig ? "Bezig met opslaan…" : eigenStatus ? `Je staat als ${eigenStatus}.` : isSpeler && magWijzigen ? "Je hebt nog niet geantwoord." : "";

  return (
    <div className="aanwezigheid">
      {fout && <div className="melding fout">{fout}</div>}
      {isSpeler && eigenLidId && magWijzigen && <Keuzebalk stand={eigenStatus} bezig={bezig} onKies={(s) => zet(eigenLidId, s)} />}
      <p className="aanwezig-lijn" role="status">
        {eigenTekst && <strong>{eigenTekst} </strong>}
        <span className="zacht">{telling}</span>
        <button type="button" className="tekst-knop" aria-expanded={namenOpen} onClick={() => setNamenOpen(!namenOpen)}>{namenOpen ? "Namen verbergen" : "Namen tonen"}</button>
      </p>
      {namenOpen && (
        <div className="aanwezig-groepen">
          {groepen.filter((g) => g.namen.length > 0).map((g) => (
            <div key={g.code}>
              <h4>{g.label}<span>{g.namen.length}</span></h4>
              <div className="namen">{g.namen.map((p) => <span key={p.id} className={g.code}>{p.naam}</span>)}</div>
            </div>
          ))}
          {groepen.every((g) => g.namen.length === 0) && <p className="klein zacht">Nog niemand heeft geantwoord.</p>}
        </div>
      )}
      {(isStaf || isAdmin) && (
        <p className="aanwezig-beheer">
          {isStaf && <button type="button" className="tekst-knop" aria-expanded={anderen} onClick={() => setAnderen(!anderen)}>{anderen ? "Aanpassen sluiten" : "Aanwezigheden aanpassen"}</button>}
          {isAdmin && <button type="button" className="tekst-knop" disabled={lijst24Laden} aria-expanded={lijst24 !== null} onClick={haal24}>{lijst24Laden ? "Lijst laden…" : lijst24 !== null ? "Lijst 24 u verbergen" : "Lijst 24 u voor aftrap"}</button>}
        </p>
      )}
      {isStaf && anderen && (
        <ul className="lijst omrand">
          {spelers.map((p) => (
            <li key={p.id} className="rij">
              <span>{p.naam}</span>
              <span style={{ width: 150 }}><Keuzebalk compact stand={perLid.get(p.id)} bezig={bezig} onKies={(s) => zet(p.id, s)} /></span>
            </li>
          ))}
        </ul>
      )}
      {isAdmin && lijst24 && (
        <ul className="lijst omrand log">
          {lijst24.length === 0 && <li className="zacht">Niemand had toen al iets aangegeven.</li>}
          {lijst24.map((r) => (
            <li key={r.member_id} className="rij">
              <span>{r.naam} <span className={`badge ${r.status === "aanwezig" ? "ok" : r.status === "afwezig" ? "fout" : "waarschuwing"}`}>{r.status}</span></span>
              <span className="zacht">{fmtTijdstip(r.gezet_op)}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
