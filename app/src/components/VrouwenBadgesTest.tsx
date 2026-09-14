import {useState} from 'react';
import {clubRpc,type ClubData} from '../lib/club';
import {VROUWEN_CATALOGUS} from '../lib/vrouwenBadges';
import {seizoenNu} from '../lib/badgeCatalogus';
import {VrouwenBadgeIcoon} from './VrouwenBadgeIcoon';
export function VrouwenBadgesTest({data,herlaad}:{data:ClubData;herlaad:()=>Promise<void>}){
 const [badge,setBadge]=useState(''),[persoon,setPersoon]=useState(''),[seizoen,setSeizoen]=useState(seizoenNu()),[fout,setFout]=useState(''),[bezig,setBezig]=useState(false);
 const gekozen=VROUWEN_CATALOGUS.find(b=>b.id===badge),fan=badge.startsWith('fan:');
 const personen=fan?data.pronoleden.filter(p=>!data.leden.some(l=>l.user_id===p.user_id&&l.functie!=='supporter')).map(p=>({id:p.user_id,naam:p.naam})):data.leden.filter(l=>l.speelt&&l.status==='actief');
 async function bewaar(verwijder=false){setBezig(true);setFout('');try{await clubRpc('club_testbadge',{p_persoon:persoon,p_badge:badge,p_seizoen:gekozen?.soort==='seizoen'?seizoen:null,p_verwijder:verwijder});await herlaad();}catch(e){setFout((e as Error).message);}finally{setBezig(false);}}
 return <details className="v-badges-test"><summary>Badges testen</summary><p>Kies een badge en wijs ze toe aan een persoon. Alleen leidersbadges van dit seizoen en aller tijden verschijnen bij het truitje.</p><div className="badge-test-grid">{VROUWEN_CATALOGUS.map(b=><button type="button" key={b.id} className="badge-test-kaart" aria-pressed={badge===b.id} onClick={()=>{setBadge(b.id);setPersoon('');}}><VrouwenBadgeIcoon id={b.id}/><strong>{b.titel}</strong><span>{b.uitleg}</span></button>)}</div>{gekozen&&<section className="kaart"><h3>{gekozen.titel}</h3><label>Persoon<select value={persoon} onChange={e=>setPersoon(e.target.value)}><option value="">Kies een persoon</option>{personen.map(p=><option key={p.id} value={p.id}>{p.naam}</option>)}</select></label>{gekozen.soort==='seizoen'&&<label>Seizoen<input value={seizoen} onChange={e=>setSeizoen(e.target.value)} placeholder="2026-2027"/></label>}<button className="knop" disabled={!persoon||bezig} onClick={()=>bewaar()}>Badge toewijzen</button> <button className="knop licht" disabled={!persoon||bezig} onClick={()=>bewaar(true)}>Testbadges van deze persoon wissen</button>{persoon&&<p>{data.badgetests?.filter(t=>t.persoon===persoon).length??0} testbadges toegewezen.</p>}{fout&&<p role="alert">{fout}</p>}</section>}</details>;
}
