import { supabase } from './supabase';
import { haalSfeerbeelden, verwijderSfeerbeeld } from './media';
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
