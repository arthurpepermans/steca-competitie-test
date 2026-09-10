import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../lib/auth";
import { ArrowUpRight } from "@phosphor-icons/react/dist/csr/ArrowUpRight";
import { MapPin } from "@phosphor-icons/react/dist/csr/MapPin";
import { Newspaper } from "@phosphor-icons/react/dist/csr/Newspaper";
import { fmtDatum, isEigen, mapsUrl, resultaat, score } from "../lib/datum";
import { EIGEN_PLOEGID } from "../lib/config";
import type { Match } from "../lib/types";

export function MapsKnop({ terrein }: { terrein: string | null }) {
  if (!terrein) return null;
  return (
    <a className="tekst-knop" href={mapsUrl(terrein)} target="_blank" rel="noreferrer">
      Route <ArrowUpRight size={15} aria-hidden="true" />
    </a>
  );
}

export function MatchKaart({ match, children, toonDatum = true }: { match: Match; children?: ReactNode; toonDatum?: boolean }) {
  const { lid } = useAuth();
  const res = isEigen(match) ? resultaat(match) : null;
  const eigenThuis = match.thuis_id === EIGEN_PLOEGID;
  const eigenUit = match.uit_id === EIGEN_PLOEGID;
  return (
    <div className={`kaart matchkaart ${isEigen(match) ? "accent" : ""}`}>
      {toonDatum && (
        <div className="matchkaart-kop">
          <span>{fmtDatum(match.datum)}{match.uur ? ` · ${match.uur}` : ""}</span>
          <span>{match.reeks}</span>
        </div>
      )}
      <div className="uitslag">
        <div className="thuis" style={{ fontWeight: eigenThuis ? 700 : 400 }}>{match.thuis}</div>
        <div className={`score ${match.status}`}>{score(match) || "uur volgt"}</div>
        <div style={{ fontWeight: eigenUit ? 700 : 400 }}>{match.uit}</div>
      </div>
      <div className="matchkaart-terrein">
        <MapPin size={16} aria-hidden="true" />
        <span>{match.terrein ?? "terrein onbekend"}</span>
        {res && <span className={`res ${res}`}>{res}</span>}
        <MapsKnop terrein={match.terrein} />
      </div>
      {match.opmerking && <div className="klein zacht" style={{ marginTop: 4 }}>{match.opmerking}</div>}
      {children}
      {lid && isEigen(match) && (
        <p className="matchkaart-voet">
          <Link className="tekst-knop" to={`/match/${encodeURIComponent(match.match_key)}`}><Newspaper size={16} aria-hidden="true" /> Matchverslag</Link>
        </p>
      )}
    </div>
  );
}
