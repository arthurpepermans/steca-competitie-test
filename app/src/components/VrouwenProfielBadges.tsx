import {SupporterBadgeIcoon} from './SupporterKlassement';
import {BADGES} from '../lib/badgeCatalogus';
import {BadgeIcoon} from './BadgeIcoon';
import {clubStatistieken,type ClubData} from '../lib/club';
import {berekenFans,FAN_BADGES} from '../lib/supporterBadges';
export function VrouwenProfielBadges({data,id}:{data:ClubData;id?:string}){
 const items:{id:string;titel:string;uitleg:string;seizoen?:string}[]=[];
 const gespeeld=data.matches.filter(m=>m.thuis_score!==null&&m.uit_score!==null&&Date.parse(m.aftrap)+80*60000<=Date.now());
 const voeg=(key:string,seizoen?:string)=>{const b=BADGES.find(b=>b.id===key);if(b)items.push({...b,titel:b.titel.replace('Junior d’Or','Steca Vrouw van het Jaar').replace('Junior van de Match','Vrouw van de Match').replace('Star Boy','Star Girl'),uitleg:b.uitleg.replaceAll('Junior','Vrouw'),seizoen});};
 if(id&&data.leden.find(l=>l.id===id)?.speelt){
 const total=clubStatistieken(data,id);
 const drempels:Record<string,[number,string][]>= {goals:[[1,'eentje_is_geentje'],[10,'dubbele_cijfers'],[25,'goalgetter'],[50,'sluipschutter'],[67,'67'],[100,'triple_digits']],assists:[[1,'wingman'],[10,'facteur'],[25,'de_architect'],[50,'kdb_der_juniors']],cleansheets:[[1,'muur_van_dendermonde'],[5,'veilige_handen'],[10,'opgewarmd_door_georgie'],[25,'golden_glove']],gespeeld:[[1,'official_junior'],[10,'toogplekker'],[25,'sterkhouder'],[50,'georgies_favoriet'],[100,'steca_legend']],rood:[[1,'laat_je_ploeg']]};
 for(const [stat,rijen] of Object.entries(drempels))for(const [n,b] of rijen)if(total[stat as keyof typeof total]>=n)voeg(b);
 const chronological=[...gespeeld].sort((a,b)=>a.aftrap.localeCompare(b.aftrap));let rij=0,aanwezigRij=0,beste=0,besteAanwezig=0,kaartVorige=false;
 for(const m of chronological){const speelt=data.opstellingen.some(o=>o.match_key===m.match_key&&Object.values(o.keuze).includes(id));rij=speelt?rij+1:0;beste=Math.max(beste,rij);const present=data.aanwezigheden.some(a=>a.match_key===m.match_key&&(a.member_id===id||a.user_id===data.user_id)&&a.status==='aanwezig');aanwezigRij=present?aanwezigRij+1:0;besteAanwezig=Math.max(besteAanwezig,aanwezigRij);const st=data.verslagen.find(v=>v.match_key===m.match_key)?.statistieken.find(v=>v.id===id);if((st?.goals??0)>=3)voeg('hattrick',m.thuis+' - '+m.uit+' · '+m.aftrap.slice(0,10));if(speelt){const kaart=(st?.geel??0)+(st?.rood??0)>0;if(kaart&&kaartVorige&&!items.some(b=>b.id==='getikte_zot'))voeg('getikte_zot');kaartVorige=kaart;}}
 if(beste>=5)voeg('vijf_op_een_rij');if(besteAanwezig>=10)voeg('rots_in_de_branding');
 const win=(lid:string,key:string)=>{const punten=(data.stempunten??[]).filter(p=>p.match_key===key);const n=punten.find(p=>p.member_id===lid)?.punten??0;return n>0&&n===Math.max(...punten.map(p=>p.punten));};
 for(const m of gespeeld)if(win(id,m.match_key))voeg('junior_van_de_match',m.thuis+' - '+m.uit+' · '+m.aftrap.slice(0,10));
 const personen=data.leden.filter(l=>l.speelt);
 const punt=(lid:string,s?:string)=>(data.stempunten??[]).filter(p=>p.member_id===lid&&gespeeld.some(m=>m.match_key===p.match_key&&(!s||m.seizoen===s))).reduce((n,p)=>n+p.punten,0);
 for(const seizoen of [undefined,...new Set(gespeeld.map(m=>m.seizoen))]){
 const ms=gespeeld.filter(m=>!seizoen||m.seizoen===seizoen);
 const score=(lid:string,key:string)=>{const c=clubStatistieken(data,lid,seizoen);if(key==='winnaar')return ms.filter(m=>win(lid,m.match_key)).length;if(key==='punten')return punt(lid,seizoen);if(key==='kaarten')return c.geel+c.rood;if(key==='aanwezig')return ms.filter(m=>data.aanwezigheden.some(a=>a.match_key===m.match_key&&(a.member_id===lid||a.user_id===personen.find(l=>l.id===lid)?.user_id)&&a.status==='aanwezig')).length;if(key==='was')return ms.filter(m=>data.wasmand.some(w=>w.match_key===m.match_key&&w.member_id===lid)).length;return c[key as keyof typeof c]??0;};
 const titels=seizoen?[['goals','gouden_stier'],['assists','assistenkoning'],['cleansheets','de_muur'],['gespeeld','vaste_waarde'],['kaarten','beenhouwer'],['rood','rosse_furie'],['aanwezig','fundering'],['was','kuisvrouw'],['punten','junior_dor'],['winnaar','star_boy']]:[['goals','het_kanon'],['assists','maestro'],['cleansheets','betonblok'],['gespeeld','clubmeubilair'],['punten','goat']];
 for(const [key,b] of titels){const n=score(id,key);if(n>0&&n===Math.max(...personen.map(l=>score(l.id,key))))voeg(b,seizoen);}
 }
 }else{
 const fans=berekenFans({personen:data.pronoleden.filter(p=>!data.leden.some(l=>l.user_id===p.user_id&&l.speelt)).map(p=>({id:p.user_id,user_id:p.user_id,naam:p.naam})),matches:data.matches.map(m=>({id:m.match_key,seizoen:m.seizoen,datum:m.aftrap,uit:false,gespeeld:gespeeld.includes(m),label:m.thuis+' - '+m.uit})),bezoeken:data.aanwezigheden.filter(a=>a.status==='aanwezig').map(a=>({persoon:a.user_id,match:a.match_key})),afgerond:[],testbadges:[]},null);
 for(const b of fans.find(f=>f.id===data.user_id)?.badges??[]){const def=FAN_BADGES.find(f=>f.id===b.badge);if(def&&def.veld!=='uit'&&def.veld!=='uitreeks')items.push({id:'fan:'+def.id,titel:def.titel,uitleg:def.uitleg,seizoen:b.seizoen??undefined});}
 }
 return <section className="kaart"><h2>Mijn badges</h2>{!items.length?<p className="zacht">Nog geen badges behaald.</p>:<div className="badge-profiel-grid">{items.map((b,i)=><details className="badge-profiel" key={b.id+String(i)}><summary>{b.id.startsWith('fan:')?<SupporterBadgeIcoon badge={FAN_BADGES.find(f=>f.id===b.id.slice(4))!}/>:<BadgeIcoon id={b.id}/>}<strong>{b.titel}</strong>{b.seizoen&&<small>{b.seizoen.replace('-','/')}</small>}</summary><p>{b.uitleg}</p></details>)}</div>}</section>;
}
