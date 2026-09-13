import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { useAuth } from "../lib/auth";
import { ArrowUpRight } from "@phosphor-icons/react/dist/csr/ArrowUpRight";
import { fmtDatum, isEigen, mapsUrl, resultaat, score } from "../lib/datum";
import { EIGEN_PLOEGID } from "../lib/config";
import type { Match } from "../lib/types";

export function MapsKnop({ terrein }: { terrein: string | null }) {
  if (!terrein) return null;
  return (
    <a className="knop licht klein" href={mapsUrl(terrein)} target="_blank" rel="noreferrer">
      Route <ArrowUpRight size={17} aria-hidden="true" />
    </a>
  );
}

export function MatchKaart({ match, children, toonDatum = true, verslagKnop }: { match: Match; children?: ReactNode; toonDatum?: boolean; verslagKnop?: ReactNode }) {
  const { lid } = useAuth();
  const res = isEigen(match) ? resultaat(match) : null;
  const eigenThuis = match.thuis_id === EIGEN_PLOEGID;
  const eigenUit = match.uit_id === EIGEN_PLOEGID;
  return <KalenderTicket toonDatum={toonDatum} datum={fmtDatum(match.datum)} uur={match.uur} reeks={match.reeks} thuis={match.thuis} uit={match.uit} eigenThuis={eigenThuis} eigenUit={eigenUit} status={match.status} scoreTekst={score(match)||"uur volgt"} terrein={match.terrein} res={res} opmerking={match.opmerking} verslagKnop={verslagKnop ?? (lid && isEigen(match) && <p><Link className="knop licht klein" to={`/match/${encodeURIComponent(match.match_key)}`}>Matchverslag bekijken</Link></p>)}>{children}</KalenderTicket>;
}
/** Dezelfde ticketopbouw voor beide ploegen; gegevens en rechten komen van de aanroeper. */
export function KalenderTicket({toonDatum=true,datum,uur,reeks,thuis,uit,eigenThuis,eigenUit,status,scoreTekst,terrein,res,opmerking,verslagKnop,children}:{toonDatum?:boolean;datum:string;uur?:string|null;reeks?:string|null;thuis:string;uit:string;eigenThuis:boolean;eigenUit:boolean;status:string;scoreTekst:string;terrein?:string|null;res?:string|null;opmerking?:string|null;verslagKnop?:ReactNode;children?:ReactNode}){
 return <div className={`kaart ${eigenThuis||eigenUit?'accent':''}`}>
 {toonDatum&&<div className="rij zacht" style={{marginBottom:6}}><span>{datum}{uur?` · ${uur}`:''}</span><span>{reeks}</span></div>}
 <div className="uitslag"><div className="thuis" style={{fontWeight:eigenThuis?700:400}}>{thuis}</div><div className={`score ${status}`}>{scoreTekst}</div><div style={{fontWeight:eigenUit?700:400}}>{uit}</div></div>
 <div className="rij" style={{marginTop:8}}><span className="zacht">{terrein??'terrein onbekend'}</span><span className="rij" style={{gap:6}}>{res&&<span className={`res ${res}`}>{res}</span>}<MapsKnop terrein={terrein??null}/></span></div>
 {opmerking&&<div className="klein zacht" style={{marginTop:4}}>{opmerking}</div>}
 {verslagKnop}{children&&<div className="ticket-scheur" aria-hidden="true"/>}{children}
 </div>;
}
