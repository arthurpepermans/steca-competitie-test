import { useState, useEffect, useRef, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { BADGES, seizoenNu, type Badge } from '../lib/badgeCatalogus';
import { magBadgesTesten, useBadges, verwijderTestbadge, wijsTestbadgeToe } from '../lib/badges';
import { haalLedenBasis, haalMatches } from '../lib/api';
import { foutTekst, useAsync } from '../lib/useAsync';
import { Fout, Laden } from './Layout';
import { BadgeIcoon } from './BadgeIcoon';

function BadgeDialoog({children,sluit,bezig}:{children:ReactNode;sluit:()=>void;bezig:boolean}) {
  const ref=useRef<HTMLDialogElement>(null);
  useEffect(()=>{const el=ref.current;el?.showModal();return ()=>el?.close();},[]);
  return <dialog ref={ref} className="badge-dialoog" aria-labelledby="badge-titel" onCancel={e=>{e.preventDefault();if(!bezig) sluit();}} onClick={e=>{if(e.target===e.currentTarget && !bezig) sluit();}}>{children}</dialog>;
}

export function BadgesTest() {
  const info=useAsync(async()=> {
    const beheer=await magBadgesTesten();
    if(!beheer) return {beheer,leden:[],matches:[]};
    const [leden,matches]=await Promise.all([haalLedenBasis(),haalMatches()]);
    return {beheer,leden:leden.filter(l=>l.functie!=='supporter' && l.status==='actief'),matches:matches.filter(m=>m.thuis_id===152 || m.uit_id===152)};
  });
  const badges=useBadges();
  const [gekozen,zetGekozen]=useState<Badge|null>(null);
  const [persoon,zetPersoon]=useState('');
  const [seizoen,zetSeizoen]=useState(seizoenNu());
  const [match,zetMatch]=useState('');
  const [bezig,zetBezig]=useState(false);
  const [fout,zetFout]=useState('');
  const [melding,zetMelding]=useState('');
  const [filter,zetFilter]=useState('');
  async function actie(f:()=>Promise<void>,tekst:string) {
    zetBezig(true);zetFout('');zetMelding('');
    try {await f();await badges.herlaad();zetMelding(tekst);} catch(e){zetFout(foutTekst(e));} finally {zetBezig(false);}
  }
  if(info.laden) return <Laden/>;
  if(info.fout) return <><Fout tekst={info.fout}/><button className="knop" onClick={info.herlaad}>Opnieuw laden</button></>;
  if(!info.data?.beheer) return <p>Alleen de aangewezen testbeheerder kan badges toewijzen.</p>;
  const data=info.data;
  const gekoppeld=(badges.data ?? []).filter(t=>t.badge_id===gekozen?.id);
  const seizoenen=[...new Set([seizoenNu(),`${Number(seizoenNu().slice(0,4))-1}-${seizoenNu().slice(0,4)}`,...data.matches.map(m=>m.seizoen)])].sort().reverse();
  return <>
    <p>Klik op een badge om ze toe te wijzen. Deze testtoewijzingen blijven bewaard tot je ze verwijdert. Er worden hiermee geen wedstrijdcijfers of echte leiders berekend of gewijzigd.</p>
    <label>Zoek een badge<input type="search" value={filter} onChange={e=>zetFilter(e.target.value)} placeholder="Naam of prestatie"/></label>
    <Fout tekst={badges.fout}/>
    {badges.fout && <button className="knop licht" onClick={badges.herlaad}>Badges opnieuw laden</button>}
    {['Leidersbadges','Verzamelbadges'].map(groep=><section key={groep}><h2>{groep}</h2>
      <p className="klein zacht">{groep==='Leidersbadges'?'Actieve titels verschijnen ook op het truitje. Een oud seizoen blijft alleen op het profiel.':'Deze badges verschijnen alleen op het spelersprofiel.'}</p>
      <div className="badge-test-grid">{BADGES.filter(b=>(groep==='Leidersbadges'?b.soort!=='verzameling':b.soort==='verzameling') && `${b.titel} ${b.uitleg}`.toLocaleLowerCase('nl').includes(filter.toLocaleLowerCase('nl'))).map(b=>
        <button className="badge-test-kaart" key={b.id} onClick={()=>{zetGekozen(b);zetFout('');zetMelding('');zetMatch('');zetSeizoen(seizoenNu());}}>
          <BadgeIcoon id={b.id}/><strong>{b.titel}</strong><span>{b.uitleg}</span><small>{(badges.data ?? []).filter(t=>t.badge_id===b.id).length} toewijzingen</small>
        </button>)}
      </div></section>)}
    {gekozen && <BadgeDialoog sluit={()=>zetGekozen(null)} bezig={bezig}>
      <button autoFocus className="knop licht klein" disabled={bezig} onClick={()=>zetGekozen(null)}>Sluiten</button>
      <BadgeIcoon id={gekozen.id}/><h2 id="badge-titel">{gekozen.titel}</h2><p>{gekozen.uitleg}</p>
      <Fout tekst={fout}/>{melding && <p role="status" className="melding ok">{melding}</p>}
      <form onSubmit={e=>{e.preventDefault();void actie(()=>wijsTestbadgeToe(gekozen.id,persoon,gekozen.soort==='seizoen'?seizoen:null,gekozen.herhaalbaar?match:null),'Badge toegewezen. Bekijk het profiel of de opstelling.');}}>
        <label>Persoon<select required value={persoon} onChange={e=>zetPersoon(e.target.value)}><option value="">Kies een persoon</option>{data.leden.map(l=><option key={l.id} value={l.id}>{l.naam}</option>)}</select></label>
        {gekozen.soort==='seizoen' && <label>Seizoen<select value={seizoen} onChange={e=>zetSeizoen(e.target.value)}>{seizoenen.map(s=><option key={s} value={s}>{s.replace('-','/')}</option>)}</select></label>}
        {gekozen.herhaalbaar && <label>Wedstrijd<select required value={match} onChange={e=>zetMatch(e.target.value)}><option value="">Kies de bijbehorende wedstrijd</option>{data.matches.map(m=><option key={m.match_key} value={m.match_key}>{m.datum} · {m.thuis} - {m.uit} · {m.match_key.slice(-6)}</option>)}</select></label>}
        <button className="knop" disabled={bezig || !persoon || Boolean(gekozen.herhaalbaar && !match)}>Badge toewijzen</button>
      </form>
      {persoon && <p className="knoppen"><Link to={`/leden/${persoon}`}>Bekijk spelersprofiel</Link><Link to="/opstelling">Bekijk opstelling</Link></p>}
      <h3>Toegewezen aan</h3>{!gekoppeld.length && <p>Nog niemand.</p>}
      <ul className="badge-toewijzingen">{gekoppeld.map(t=><li key={t.id}><div><strong>{data.leden.find(l=>l.id===t.member_id)?.naam ?? 'Voormalig clublid'}</strong>{t.seizoen && <small>{t.seizoen.replace('-','/')}</small>}{t.match_key && <Link to={`/match/${encodeURIComponent(t.match_key)}`}>Matchverslag</Link>}</div><button className="knop licht klein" disabled={bezig} onClick={()=>void actie(()=>verwijderTestbadge(t.id),'Testtoewijzing verwijderd.')}>Verwijderen</button></li>)}</ul>
    </BadgeDialoog>}
  </>;
}
