import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { maakTestmatch } from '../lib/testmatches';
import { pushActie, pushOndersteund, zetMeldingenAan, zetMeldingenUit, type PushStatus } from '../lib/push';
import { foutTekst, useAsync } from '../lib/useAsync';
import { Fout, Laden } from '../components/Layout';

const scenarios = [
  ['aanwezig72','72 uur: nog niet ingevuld','Verwacht: een herinnering voor je aanwezigheid.'],
  ['aanwezig48','48 uur: nog niet ingevuld','Verwacht: de tweede aanwezigheidsherinnering.'],
  ['ingevuld','Aanwezigheid al ingevuld','Verwacht: géén herinnering.'],
  ['vroeg','Score vóór 80 minuten','Verwacht: nu géén melding, later wel vanaf 80 minuten.'],
  ['stemmen','Score na 80 minuten','Verwacht: uitnodiging voor Junior van de match.'],
  ['stemherinnering','Drie uur later, nog geen stem','Verwacht: herinnering om te stemmen.'],
  ['gestemd','Stem al uitgebracht','Verwacht: géén stemherinnering.'],
];
export function MeldingenTest() {
  const navigate=useNavigate();
  const info = useAsync(() => pushActie<PushStatus>('status'));
  const [fout,setFout] = useState('');
  const [melding,setMelding] = useState('');
  const [bezig,setBezig] = useState(false);
  const [matchKey,setMatchKey] = useState('');
  async function doe(f: () => Promise<unknown>, tekst:string) { setBezig(true);setFout('');setMelding('');try { await f();setMelding(tekst);await info.herlaad(); }catch(e){setFout(foutTekst(e));}finally{setBezig(false);} }
  if(info.laden) return <Laden />;
  return <>
    <h1>Meldingen testen</h1>
    <p className="melding info">Afgeschermde testomgeving. Alleen het aangewezen testaccount krijgt meldingen. De officiële app blijft ongewijzigd.</p>
    <Fout tekst={info.fout || fout} />
    {melding && <p role="status" className="melding ok">{melding}</p>}
    {!info.data ? <button className="knop" onClick={info.herlaad}>Opnieuw controleren</button> : <>
      <section className="kaart"><h2>Jouw toestel</h2><p>Op iPhone: zet <strong>test.stecajuniors.app</strong> op je beginscherm, open dat testicoon en tik hieronder op Meldingen aanzetten.</p>
        {!pushOndersteund() && <p className="melding waarschuwing">Deze browser kan nu geen pushmeldingen ontvangen. Open de testapp vanaf je beginscherm.</p>}
        <div className="knoppen"><button className="knop" disabled={bezig || !pushOndersteund()} onClick={()=>doe(()=>zetMeldingenAan(info.data!.publicKey),'Dit toestel is gekoppeld voor testmeldingen.')}>Meldingen aanzetten</button><button className="knop licht" disabled={bezig || !pushOndersteund()} onClick={()=>doe(zetMeldingenUit,'Meldingen uitgeschakeld op dit toestel.')}>Meldingen uitzetten</button></div>
        {!info.data.enabled && <p className="melding waarschuwing">Verzending staat nog uit op de server.</p>}
      </section>
      <section className="kaart"><h2>Zelf een testmatch invullen</h2><p>Maak een wedstrijd alsof ze net gespeeld is. Vul zelf de uitslag, goals en assists in. Bij het opslaan kan de stemmelding naar jouw testaccount vertrekken.</p><button className="knop" disabled={bezig} onClick={()=>doe(async()=>{const key=await maakTestmatch();navigate(`/match/${encodeURIComponent(key)}?invullen=1`);},'Testmatch aangemaakt.')}>Gespeelde testmatch aanmaken</button><p className="klein zacht">Je kunt de testmatch daarna weer verwijderen via het matchverslag.</p></section>
      <section className="kaart"><h2>Een match nabootsen</h2><p>Elke knop maakt een nieuwe fictieve match met het gekozen tijdstip. Je echte wedstrijden veranderen niet. Alle meldingen beginnen met TEST.</p>
        <div className="test-scenario-lijst">{scenarios.map(([code,titel,uitleg])=><div className="test-scenario" key={code}><button className="knop licht" disabled={bezig} onClick={()=>doe(async()=>{const r=await pushActie<{matchKey:string;verzonden:number}>('scenario',{scenario:code});setMatchKey(r.matchKey);},'Testmatch aangemaakt. Controleer de melding en het verzendoverzicht.')}>{titel}</button><p className="klein zacht">{uitleg}</p></div>)}</div>
        {matchKey && <p><Link className="knop" to={`/match/${encodeURIComponent(matchKey)}`}>Open het testmatchverslag</Link></p>}
        <p><button className="knop licht klein" disabled={bezig} onClick={()=>doe(()=>pushActie('stop-tests'),'De bestaande testscenario’s zijn gestopt. Je krijgt daarvoor geen volgende herinneringen.')}>Bestaande testscenario’s stoppen</button></p>
      </section>
      <section className="kaart"><h2>Verzendoverzicht</h2><p className="klein zacht">Verzonden betekent dat de pushdienst de melding heeft aangenomen. De instellingen en verbinding van je telefoon bepalen wanneer je ze ziet.</p><button className="knop licht klein" disabled={bezig} onClick={()=>doe(()=>pushActie('run'),'Planning gecontroleerd.')}>Planning nu controleren</button>
        {!info.data.jobs.length && <p>Nog geen meldingen ingepland.</p>}
        <ul className="lijst">{info.data.jobs.map(j=><li key={j.match_key+j.soort}><Link to={`/match/${encodeURIComponent(j.match_key)}`}>{scenarios.find(s=>s[0]===j.soort)?.[1] ?? j.soort}</Link><strong> · {({sent:'Verzonden',pending:'Wacht op verzending',sending:'Wordt verzonden',skipped:'Niet meer nodig'} as Record<string,string>)[j.status]}</strong>{j.sent_at && <small> · {new Date(j.sent_at).toLocaleString('nl-BE')}</small>}{j.fout && <p className="klein zacht">{j.fout}</p>}</li>)}</ul>
      </section>
    </>}
  </>;
}
