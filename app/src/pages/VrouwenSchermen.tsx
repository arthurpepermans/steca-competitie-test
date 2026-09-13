import {useState,type ReactNode} from 'react';
import {Link} from 'react-router-dom';
import {CalendarBlank} from '@phosphor-icons/react/dist/csr/CalendarBlank';
import {MapPin} from '@phosphor-icons/react/dist/csr/MapPin';
import {ArrowUpRight} from '@phosphor-icons/react/dist/csr/ArrowUpRight';
import {Aftelling} from '../components/Aftelling';
import {MapsKnop} from '../components/MatchKaart';
import {clubRpc,clubStatistieken,type ClubData,type ClubMatch} from '../lib/club';

export const vrouwenDatum=(iso:string)=>new Date(iso).toLocaleDateString('nl-BE',{weekday:'short',day:'numeric',month:'short',year:'numeric',timeZone:'Europe/Brussels'});
const vrouwenUur=(iso:string)=>new Date(iso).toLocaleTimeString('nl-BE',{hour:'2-digit',minute:'2-digit',timeZone:'Europe/Brussels'});
export const vrouwenSeizoen=(_data:ClubData)=>{
 const nu=new Date(),jaar=nu.getMonth()<6?nu.getFullYear()-1:nu.getFullYear();
 return `${jaar}-${jaar+1}`;
};
const labels:Record<string,string>={speler:'Speelster',spelercoach:'Speelster-coach',coach:'Coach',verantwoordelijke:'Verantwoordelijke',supporter:'Supporter'};
const stats:Record<string,string>={goals:'Goals',assists:'Assists',geel:'Geel',rood:'Rood',cleansheets:'Clean sheets',gespeeld:'Gespeeld'};
export function VrouwenTicket({match,children}:{match:ClubMatch;children?:ReactNode}){
 const terrein=match.locaties?.map(l=>[l.zaal,l.adres].filter(Boolean).join(' · ')).join(' / ')||null;
 return <section className="match-blok"><div className="sectie-kop"><h2>01 / Volgende match</h2><Link to="/vrouwen/kalender" aria-label="Bekijk de kalender"><ArrowUpRight size={23}/></Link></div>
 <div className="match-affiche"><div className="affiche-meta"><span>WEDSTRIJDTICKET · {match.reeks??'Dames Zele'}</span><span className="locatie-label">{match.thuis==='STECA VROUWEN'?'Thuismatch':'Uitmatch'}</span></div>
 <div className="affiche-ploegen"><div className="team-naam"><span className="team-boven">{match.thuis}</span><span className="versus">tegen</span><span className="team-onder">{match.uit}</span></div><img className="affiche-logo" src={import.meta.env.BASE_URL+'logo-vrouwen.png'} alt="Clublogo Steca Vrouwen" width="150" height="150"/></div>
 <div className="match-moment"><CalendarBlank size={22}/><span>{vrouwenDatum(match.aftrap)}</span><strong>{vrouwenUur(match.aftrap)}</strong></div><Aftelling aftrapIso={match.aftrap}/>
 <div className="match-terrein"><MapPin size={20}/><span>{terrein??'Terrein nog niet bekend'}</span><MapsKnop terrein={match.locaties?.[0]?.adres??null}/></div></div>
 {children&&<div className="match-aanwezigheid">{children}</div>}</section>;
}
export function VrouwenKalender({data}:{data:ClubData}){
 const [filter,setFilter]=useState('komend');
 const wedstrijden=data.matches.filter(m=>filter==='alles'||(filter==='komend'?Date.parse(m.aftrap)>Date.now():Date.parse(m.aftrap)<=Date.now())).sort((a,b)=>filter==='gespeeld'?b.aftrap.localeCompare(a.aftrap):a.aftrap.localeCompare(b.aftrap));
 return <><h1>Kalender</h1><div className="tabs">{[['komend','Komend'],['gespeeld','Gespeeld'],['alles','Alles']].map(([k,l])=><button key={k} className={filter===k?'actief':''} onClick={()=>setFilter(k)}>{l}</button>)}</div>
 {wedstrijden.map(m=><article className="kaart accent" key={m.match_key}><div className="rij zacht"><span>{vrouwenDatum(m.aftrap)} · {vrouwenUur(m.aftrap)}</span><span>{m.reeks??'Dames Zele'}</span></div><div className="uitslag"><div>{m.thuis}</div><div className="score">{m.thuis_score===null?vrouwenUur(m.aftrap):`${m.thuis_score} - ${m.uit_score}`}</div><div>{m.uit}</div></div><div className="rij"><span className="zacht">{m.locaties?.map(l=>[l.zaal,l.adres].filter(Boolean).join(' · ')).join(' / ')||'Terrein nog niet bekend'}</span><MapsKnop terrein={m.locaties?.[0]?.adres??null}/></div><p><Link className="knop licht klein" to={'/vrouwen/match/'+encodeURIComponent(m.match_key)}>Matchverslag bekijken</Link> <Link className="knop licht klein" to={'/vrouwen/opstelling/'+encodeURIComponent(m.match_key)}>Opstelling</Link></p></article>)}
 {!wedstrijden.length&&<p className="zacht">Geen wedstrijden in deze periode.</p>}</>;
}
export function VrouwenHome({data,children,stand}:{data:ClubData;children?:ReactNode;stand?:{positie:number;punten:number;gespeeld:number;voor:number}}){
 const komend=data.matches.filter(m=>Date.parse(m.aftrap)>Date.now()&&m.thuis_score===null).sort((a,b)=>a.aftrap.localeCompare(b.aftrap));
 const laatste=data.matches.filter(m=>m.thuis_score!==null&&Date.parse(m.aftrap)<=Date.now()).sort((a,b)=>b.aftrap.localeCompare(a.aftrap))[0];
 return <div className="home-pagina"><div className="matchdag-kop"><h1>Matchdag</h1><span>Seizoen {vrouwenSeizoen(data)}</span></div><div className="home-grid">
 {komend[0]?<VrouwenTicket match={komend[0]}>{children}</VrouwenTicket>:<section className="match-blok"><h2>Even geen match gepland</h2><Link to="/vrouwen/kalender">Bekijk de kalender</Link></section>}
 <aside className="home-zijde"><div className="club-embleem"><span>SAMEN UIT. SAMEN THUIS.</span><img src={import.meta.env.BASE_URL+'logo-vrouwen.png'} alt="Steca Vrouwen"/><span>DE DERDE HELFT</span><strong>STECA VROUWEN.</strong></div>
 <section className="stand-blok"><div className="sectie-kop"><h2>02 / De rangschikking</h2></div><p className="zacht">DAMES ZELE</p>{stand?<><div className="stand-cijfer"><strong>{stand.positie}</strong><span>e plaats</span></div><div className="stand-statistieken">{[[stand.punten,'punten'],[stand.gespeeld,'gespeeld'],[stand.voor,'goals']].map(([n,l])=><div key={l}><strong>{n}</strong><span>{l}</span></div>)}</div></>:<p>Klassement laden…</p>}<Link className="tekst-link" to="/vrouwen/klassement">Volledig klassement ↗</Link></section>
 <section className="resultaat-blok"><div className="sectie-kop"><h2>Laatste uitslag</h2></div>{laatste?<><p className="zacht">{vrouwenDatum(laatste.aftrap)}</p><div className="laatste-score"><strong>{laatste.thuis_score} : {laatste.uit_score}</strong></div><p>{laatste.thuis} - {laatste.uit}</p><Link to={'/vrouwen/match/'+encodeURIComponent(laatste.match_key)}>Matchverslag bekijken</Link></>:<p>Nog geen uitslag.</p>}</section></aside>
 {komend.length>1&&<section className="binnenkort"><div className="sectie-kop"><h2>Daarna op de kalender</h2></div><div className="komende-lijst">{komend.slice(1,3).map(m=><Link className="komende-match" to="/vrouwen/kalender" key={m.match_key}><time><strong>{new Date(m.aftrap).getDate()}</strong><span>{new Date(m.aftrap).toLocaleDateString('nl-BE',{month:'short'})}</span></time><div><h3>{m.thuis==='STECA VROUWEN'?m.uit:m.thuis}</h3><p>{m.thuis==='STECA VROUWEN'?'Thuis':'Uit'} / {vrouwenUur(m.aftrap)}</p></div><ArrowUpRight size={22}/></Link>)}</div></section>}
 </div></div>;
}

export function VrouwenLeden({data,beheer}:{data:ClubData;beheer?:ReactNode}){
 const [zoek,setZoek]=useState(''),[functie,setFunctie]=useState(''),[supporters,setSupporters]=useState(false);
 const leden=data.leden.filter(l=>l.functie!=='supporter'&&(l.status==='actief'||data.admin));
 const ultras=vrouwenSupporters(data);
 return <><h1>Leden</h1><div className="tabs"><button className={!supporters?'actief':''} onClick={()=>setSupporters(false)}>Clubleden</button>{data.admin&&<button className={supporters?'actief':''} onClick={()=>setSupporters(true)}>Supporters beheren</button>}</div>
 <div className="rij v-leden-filters"><input aria-label="Zoek een lid" placeholder="Zoeken…" value={zoek} onChange={e=>setZoek(e.target.value)}/>{!supporters&&<select aria-label="Filter op functie" value={functie} onChange={e=>setFunctie(e.target.value)}><option value="">Alle functies</option>{Object.entries(labels).filter(([k])=>k!=='supporter').map(([k,l])=><option value={k} key={k}>{l}</option>)}</select>}</div>
 <ul className="lijst omrand">{(supporters?ultras.map(s=>({id:s.user_id,naam:s.naam,functie:'supporter',user_id:s.user_id,status:'actief',is_admin:false})):leden).filter(l=>(!functie||supporters||l.functie===functie)&&l.naam.toLocaleLowerCase().includes(zoek.toLocaleLowerCase())).sort((a,b)=>a.naam.localeCompare(b.naam)).map(l=><li key={l.id}><Link className="rij" to={'/vrouwen/'+(supporters?'supporters/':'leden/')+l.id}><span><strong>{l.naam}</strong>{l.is_admin?' ☆':''}<br/><span className="zacht klein">{labels[l.functie]}{l.status!=='actief'?' · '+l.status.replaceAll('_',' '):''}{!l.user_id?' · geen account':''}</span></span><span>›</span></Link></li>)}</ul>
 <p className="klein zacht">{supporters?`${ultras.length} supporters`:`${leden.length} clubleden`}</p>{!supporters&&beheer}</>;
}
export function VrouwenSpelerProfiel({data,id,beheer,herlaad}:{data:ClubData;id:string;beheer?:ReactNode;herlaad?:()=>Promise<void>}){
 const [alles,setAlles]=useState(false);const lid=data.leden.find(l=>l.id===id);if(!lid)return <p>Lid niet gevonden.</p>;
 const seizoen=vrouwenSeizoen(data),cijfers=clubStatistieken(data,id,alles?undefined:seizoen);
 const wedstrijden=data.matches.filter(m=>m.thuis_score!==null&&Date.parse(m.aftrap)<=Date.now()&&(alles||m.seizoen===seizoen)&&data.opstellingen.some(o=>o.match_key===m.match_key&&Object.values(o.keuze).includes(id))).sort((a,b)=>b.aftrap.localeCompare(a.aftrap));
 return <><p><Link to="/vrouwen/leden">‹ Alle leden</Link></p><h1>{lid.naam}</h1><p className="zacht">{labels[lid.functie]}</p><div className="kaart"><div className="rij"><h3>Statistieken {alles?'alle seizoenen':'seizoen '+seizoen}</h3><button className="knop licht klein" onClick={()=>setAlles(!alles)}>{alles?'Dit seizoen':'All time'}</button></div><div className="stand-statistieken speler-cijfers">{Object.entries(stats).map(([key,label])=><div key={key}><strong>{cijfers[key as keyof typeof cijfers]}</strong><span>{label}</span></div>)}</div>
 <ul className="lijst">{wedstrijden.map(m=><li key={m.match_key}><Link className="rij" to={'/vrouwen/match/'+encodeURIComponent(m.match_key)}><span>{vrouwenDatum(m.aftrap)}<br/>{m.thuis} - {m.uit}</span><strong>{m.thuis_score}-{m.uit_score} ›</strong></Link></li>)}</ul>{!wedstrijden.length&&<p className="zacht">Nog geen gespeelde matchen.</p>}</div>{data.admin&&herlaad&&<VrouwenFunctie key={lid.id} lidId={lid.id} naam={lid.naam} functie={lid.functie} speelt={lid.speelt} herlaad={herlaad}/>} {beheer}</>;
}
export function vrouwenSupporters(data:ClubData){return data.pronoleden.filter(p=>!data.leden.some(l=>l.user_id===p.user_id&&l.functie!=='supporter'));}
export function supporterCijfers(data:ClubData,user:string,seizoen?:string){
 const keys=new Set(data.aanwezigheden.filter(a=>a.user_id===user&&!a.speler&&a.status==='aanwezig').map(a=>a.match_key));
 const matches=data.matches.filter(m=>keys.has(m.match_key)&&m.thuis_score!==null&&Date.parse(m.aftrap)+80*60000<=Date.now()&&(!seizoen||m.seizoen===seizoen));
 return {matches,uit:matches.filter(m=>m.thuis!=='STECA VROUWEN').length};
}
export function VrouwenSupporterProfiel({data,user,beheer,herlaad}:{data:ClubData;user:string;beheer?:ReactNode;herlaad?:()=>Promise<void>}){
 const persoon=vrouwenSupporters(data).find(p=>p.user_id===user);if(!persoon)return <p>Supporter niet gevonden.</p>;
 const jaar=supporterCijfers(data,user,vrouwenSeizoen(data)),alles=supporterCijfers(data,user);
 return <><Link to="/vrouwen/leden">‹ Alle leden</Link><h1>{persoon.naam}</h1><p className="zacht">Supporter</p><section className="kaart"><h2>Supportersstatistieken</h2><div className="stand-statistieken speler-cijfers">{[[jaar.matches.length,'Matchen dit seizoen'],[alles.matches.length,'Matchen all time'],[jaar.uit,'Uitmatchen dit seizoen'],[alles.uit,'Uitmatchen all time']].map(([n,l])=><div key={l}><strong>{n}</strong><span>{l}</span></div>)}</div><ul className="lijst">{alles.matches.map(m=><li key={m.match_key}><Link to={'/vrouwen/match/'+encodeURIComponent(m.match_key)}>{vrouwenDatum(m.aftrap)} · {m.thuis} - {m.uit}</Link></li>)}</ul></section>{data.admin&&herlaad&&<VrouwenFunctie userId={user} naam={persoon.naam} functie="supporter" speelt={false} herlaad={herlaad}/>} {beheer}</>;
}
function VrouwenFunctie({lidId,userId,naam,functie,speelt,herlaad}:{lidId?:string;userId?:string;naam:string;functie:string;speelt:boolean;herlaad:()=>Promise<void>}){
 const [fout,setFout]=useState(''),[bezig,setBezig]=useState(false),[klaar,setKlaar]=useState(false);
 return <details className="kaart"><summary>Functie aanpassen</summary><form onSubmit={async e=>{e.preventDefault();const velden=new FormData(e.currentTarget);setBezig(true);setFout('');setKlaar(false);try{if(lidId)await clubRpc('club_wijzig_lid',{p_lid:lidId,p_functie:velden.get('functie'),p_speelt:velden.get('speelt')==='on'});else await clubRpc('club_zet_lid',{p_user:userId,p_functie:velden.get('functie'),p_speelt:velden.get('speelt')==='on'});await herlaad();setKlaar(true);}catch(e){setFout((e as Error).message);}finally{setBezig(false);}}}><p>{naam}</p><label>Functie<select name="functie" defaultValue={functie}>{Object.entries(labels).map(([k,l])=><option value={k} key={k}>{l}</option>)}</select></label><label><input type="checkbox" name="speelt" defaultChecked={speelt}/>Speelt mee</label><button className="knop" disabled={bezig}>Opslaan</button>{fout&&<p role="alert">{fout}</p>}{klaar&&<p role="status">Functie opgeslagen.</p>}</form></details>;
}
export function VrouwenStatistieken({data}:{data:ClubData}){
 const [stat,setStat]=useState('goals'),[alles,setAlles]=useState(false),[supporters,setSupporters]=useState(false);
 const seizoen=alles?undefined:vrouwenSeizoen(data),kolommen=[stat,...Object.keys(stats).filter(k=>k!==stat)];
 const rijen=data.leden.filter(l=>l.speelt).map(l=>({...l,cijfers:clubStatistieken(data,l.id,seizoen)})).sort((a,b)=>b.cijfers[stat as keyof typeof b.cijfers]-a.cijfers[stat as keyof typeof a.cijfers]||a.naam.localeCompare(b.naam));
 return <section><div className="tabs"><button className={!supporters?'actief':''} onClick={()=>setSupporters(false)}>Speelsters</button><button className={supporters?'actief':''} onClick={()=>setSupporters(true)}>Supporters</button></div><div className="rij"><h2>{supporters?'Supportersklassement':'Statistieken'}</h2><button className="knop licht klein" onClick={()=>setAlles(!alles)}>{alles?'Dit seizoen':'All time'}</button></div><p className="zacht">{alles?'Alle seizoenen':'Seizoen '+seizoen}</p>
 {supporters?<ul className="lijst omrand">{vrouwenSupporters(data).map(p=>({...p,aantal:supporterCijfers(data,p.user_id,seizoen).matches.length})).sort((a,b)=>b.aantal-a.aantal||a.naam.localeCompare(b.naam)).map((p,i)=><li key={p.user_id}><Link className="rij" to={'/vrouwen/supporters/'+p.user_id}><span>{i+1}. {p.naam}</span><strong>{p.aantal}</strong></Link></li>)}</ul>:<><label>Klassement<select value={stat} onChange={e=>setStat(e.target.value)}>{Object.entries(stats).map(([k,l])=><option value={k} key={k}>{l}</option>)}</select></label><div className="tabel-wrap"><table className="tabel"><thead><tr><th>#</th><th>Speelster</th>{kolommen.map(k=><th className="num" key={k}>{stats[k]}</th>)}</tr></thead><tbody>{rijen.map((l,i)=><tr key={l.id}><td>{i+1}</td><td><Link to={'/vrouwen/leden/'+l.id}>{l.naam}</Link></td>{kolommen.map(k=><td className="num" key={k}>{l.cijfers[k as keyof typeof l.cijfers]}</td>)}</tr>)}</tbody></table></div></>}
 </section>;
}
