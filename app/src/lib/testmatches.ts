import { supabase } from './supabase';
import { haalSfeerbeelden, verwijderSfeerbeeld } from './media';
export async function haalTestmatchSleutels(): Promise<string[]> {
  const sleutels:string[]=[];
  for(let vanaf=0;;vanaf+=200) {
    const {data,error}=await supabase.from('matches').select('match_key')
      .or('bron.in.(test-invoer,push-test),match_key.eq.test-matchverslag-voorbeeld')
      .order('match_key').range(vanaf,vanaf+199);
    if(error) throw error;
    const pagina=data ?? [];
    sleutels.push(...pagina.map(m=>m.match_key));
    if(pagina.length<200) return sleutels;
  }
}

export async function verwijderAlleTestmatches(sleutels:string[], voortgang:(klaar:number,totaal:number)=>void=()=>{}) {
  const uniek=[...new Set(sleutels)];
  let verwijderd=0;
  const mislukt:string[]=[];
  for(const [index,key] of uniek.entries()) {
    // Iedere match behoudt de servercontrole en de volledige media-opruiming.
    try { await verwijderTestmatch(key); verwijderd++; }
    catch { mislukt.push(key); }
    voortgang(index+1,uniek.length);
  }
  return {verwijderd,mislukt};
}
export async function maakTestmatch(): Promise<string> {
  const { data,error }=await supabase.rpc('maak_testmatch');
  if(error) throw error;
  return data;
}
export async function verwijderTestmatch(matchKey:string) {
  const controle=await supabase.rpc('controleer_testmatch',{p_match_key:matchKey});
  if(controle.error) throw controle.error;
  // Alleen na controle van testbeheerder én testwedstrijd mogen de beelden mee weg.
  for(let ronde=0;ronde<100;ronde++) {
    const {beelden}=await haalSfeerbeelden(matchKey);
    if(!beelden.length) break;
    for(const beeld of beelden) await verwijderSfeerbeeld(beeld.path);
  }
  const {error}=await supabase.rpc('verwijder_testmatch',{p_match_key:matchKey});
  if(error) throw error;
}

export async function simuleerTestherinnering(matchKey:string) {
  const {error}=await supabase.rpc('simuleer_testherinnering',{p_match_key:matchKey});
  if(error) throw error;
}
