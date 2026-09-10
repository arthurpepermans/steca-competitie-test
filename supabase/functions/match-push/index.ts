import { createClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';
import { bericht, verschuldigd, TEST_ORIGIN, TEST_PROJECT, type Soort, type Uitslag } from '../_shared/meldingen.ts';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const cors = { 'Access-Control-Allow-Origin': TEST_ORIGIN, 'Access-Control-Allow-Headers': 'authorization,apikey,content-type,x-client-info', 'Cache-Control': 'no-store' };
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
class Fout extends Error { constructor(message: string, public status = 400) { super(message); } }
function check<T>(r: { data: T; error: unknown }): T { if (r.error) throw new Fout('Databasebewerking mislukt. Probeer opnieuw.',503); return r.data; }
function abonnement(s: any) {
  const u = new URL(s?.endpoint ?? '');
  const toegestaan = ['fcm.googleapis.com','updates.push.services.mozilla.com','web.push.apple.com','wns.windows.com'];
  if (u.protocol !== 'https:' || u.port || u.username || u.password || !toegestaan.some(h => u.hostname === h || u.hostname.endsWith('.' + h)) || s.endpoint.length > 4096 || !/^[\w-]{80,100}$/.test(s?.keys?.p256dh ?? '') || !/^[\w-]{20,30}$/.test(s?.keys?.auth ?? '')) throw new Fout('Ongeldig pushabonnement.');
  return { endpoint: s.endpoint, keys: { p256dh: s.keys.p256dh, auth: s.keys.auth } };
}
type Planning = Uitslag & { match_key: string; member_id: string; tegenstander: string; aftrap: string | null; score_at: string | null; deadline: string; antwoord: boolean; aanwezig: boolean; gestemd: boolean; eerste_verzonden: string | null; wasmand?: boolean };
function soorten(p: Planning) { return verschuldigd({ aftrap: p.aftrap ? Date.parse(p.aftrap) : NaN, scoreAt: p.score_at ? Date.parse(p.score_at) : null, deadline: Date.parse(p.deadline), antwoord:p.antwoord, aanwezig:p.aanwezig, gestemd:p.gestemd, wasmand:Boolean(p.wasmand), eersteVerzonden:p.eerste_verzonden ? Date.parse(p.eerste_verzonden) : null }, Date.now()); }
async function planning(): Promise<Planning[]> { return check(await db.rpc('push_planning')); }
async function verzendRij(config: any, matchKey?: string) {
  if (!config.enabled || !config.allowed_member || !config.vapid_private) return { verzonden:0 };
  for (const p of (await planning()).filter(p=>!matchKey || p.match_key===matchKey)) for (const soort of soorten(p)) check(await db.from('push_jobs').upsert({ match_key:p.match_key, member_id:p.member_id, soort }, { onConflict:'match_key,member_id,soort', ignoreDuplicates:true }));
  let query = db.from('push_jobs').select('*').eq('member_id',config.allowed_member).in('status',['pending','sending']).order('created_at');
  if (matchKey) query=query.eq('match_key',matchKey);
  const jobs = check(await query.limit(40)) ?? [];
  let verzonden = 0;
  for (const j of jobs) {
    if (!check(await db.rpc('claim_push_job',{p_id:j.id}))) continue;
    // Controleer antwoorden en stemmen opnieuw vlak voor verzending, niet alleen bij het plannen.
    const p = (await planning()).find(p => p.match_key===j.match_key && p.member_id===j.member_id);
    if (!p || !soorten(p).includes(j.soort as Soort)) { check(await db.from('push_jobs').update({status:'skipped',fout:null}).eq('id',j.id)); continue; }
    const subs = check(await db.from('push_subscriptions').select('subscription,endpoint').eq('member_id',j.member_id)) ?? [];
    let gelukt = false;
    for (const sub of subs) {
      try {
        const inhoud = bericht(j.soort,p.tegenstander,p);
        const route = j.soort === 'wasmand' ? '/opstelling' : j.soort.startsWith('aanwezig') ? `/kalender?match=${encodeURIComponent(j.match_key)}` : `/match/${encodeURIComponent(j.match_key)}`;
        await webpush.sendNotification(abonnement(sub.subscription),JSON.stringify({...inhoud,title:'TEST · '+inhoud.title,url:`${TEST_ORIGIN}/#${route}`,tag:j.id}),{vapidDetails:{subject:TEST_ORIGIN,publicKey:config.vapid_public,privateKey:config.vapid_private},TTL:3600,timeout:10000,topic:j.id.replaceAll('-','')});
        gelukt = true;
      } catch(e) {
        if ([404,410].includes((e as any)?.statusCode)) check(await db.from('push_subscriptions').delete().eq('endpoint',sub.endpoint));
      }
    }
    if (gelukt) { check(await db.from('push_jobs').update({status:'sent',sent_at:new Date().toISOString(),fout:null,lease_until:null}).eq('id',j.id)); verzonden++; }
    else check(await db.from('push_jobs').update({status:'pending',lease_until:null,next_attempt:new Date(Date.now()+Math.min(30,2**Math.min(j.attempts,5))*60000).toISOString(),fout:subs.length ? 'Pushdienst niet bereikbaar. Automatisch opnieuw proberen.' : 'Nog geen actief toestel gekoppeld.'}).eq('id',j.id));
  }
  return {verzonden};
}
async function scenario(soort: string, memberId: string) {
  if (soort==='stemherinnering') throw new Fout('Kies een bestaande testmatch bij Herinnering voor jouw testmatch. Herlaad de testapp als je die keuze nog niet ziet.');
  if (!['aanwezig72','aanwezig48','vroeg','stemmen','stemherinnering','ingevuld','gestemd'].includes(soort)) throw new Fout('Onbekend testscenario.');
  const recent = await db.from('matches').select('match_key',{count:'exact',head:true}).eq('bron','push-test').gt('fetched_at',new Date(Date.now()-60000).toISOString());
  if ((recent.count ?? 0)>=8) throw new Fout('Wacht even voor je een nieuw scenario start.',429);
  const uren = soort==='aanwezig72' ? 71.99 : ['aanwezig48','ingevuld'].includes(soort) ? 47.99 : soort==='vroeg' ? -.5 : soort==='stemherinnering' ? -5 : -1.35;
  const aftrap = new Date(Date.now()+uren*3600000);
  const delen = new Intl.DateTimeFormat('sv-SE',{timeZone:'Europe/Brussels',year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(aftrap).split(' ');
  const key = 'push-test-'+crypto.randomUUID();
  check(await db.from('matches').insert({match_key:key,seizoen:'2026-2027',reeks:'TESTMATCH',datum:delen[0],uur:delen[1],thuis_id:152,uit_id:9901,thuis:'Steca Juniors',uit:'FC Test United',status:'gepland',bron:'push-test',fetched_at:new Date().toISOString(),terrein:'Testterrein'}));
  const spelers = check(await db.from('members').select('id').like('email','testspeler%@example.invalid').limit(4)) ?? [];
  const isStem = ['vroeg','stemmen','stemherinnering','gestemd'].includes(soort);
  if (isStem || soort==='ingevuld') check(await db.from('attendance').upsert([{match_key:key,member_id:memberId,status:'aanwezig'},...spelers.map(m=>({match_key:key,member_id:m.id,status:'aanwezig'}))]));
  if (isStem) check(await db.from('match_reports').insert({match_key:key,thuis_score:2,uit_score:1,ingevoerd_door:memberId,score_at:new Date(soort==='stemherinnering' ? Date.now()-4*3600000 : Date.now()).toISOString(),momenten:[{minuut:18,soort:'goal',kant:'thuis',speler:'Testspeler 1',assist:'Testspeler 2'},{minuut:36,soort:'goal',kant:'uit',speler:'Speler FC Test United',assist:''},{minuut:67,soort:'goal',kant:'thuis',speler:'Testspeler 3',assist:'Testspeler 1'}]}));
  if (soort==='stemherinnering') check(await db.from('push_jobs').insert({match_key:key,member_id:memberId,soort:'stemmen',status:'sent',sent_at:new Date(Date.now()-3*3600000-60000).toISOString(),fout:'Test: eerste verzendmoment gesimuleerd.'}));
  if (soort==='gestemd' && spelers.length>=3) check(await db.from('match_votes').insert({match_key:key,voter_id:memberId,eerste:spelers[0].id,tweede:spelers[1].id,derde:spelers[2].id}));
  return key;
}
Deno.serve(async req => {
  if (Deno.env.get('SUPABASE_URL') !== TEST_PROJECT) return json({error:'Deze proef is uitsluitend voor de testdatabase.'},403);
  if (req.method==='OPTIONS') return new Response('ok',{headers:cors});
  if (req.method!=='POST') return json({error:'POST vereist.'},405);
  try {
    let config = check(await db.from('push_config').select('*').eq('id',1).single());
    const token = req.headers.get('authorization')?.replace(/^Bearer /i,'') ?? '';
    if (token && token===config.cron_secret) return json(await verzendRij(config));
    const {data:{user}} = await db.auth.getUser(token);
    if (!user) throw new Fout('Log in op de testapp.',401);
    const lid = check(await db.from('members').select('id,is_admin,status').eq('user_id',user.id).maybeSingle());
    if (!lid || lid.status!=='actief' || lid.id!==config.allowed_member) throw new Fout('Testmeldingen zijn uitsluitend voor het aangewezen testaccount.',403);
    const inhoud = await req.text();
    if (inhoud.length>12000) throw new Fout('Aanvraag te groot.');
    const body = JSON.parse(inhoud || '{}');
    if (body.action==='status') {
      if (!config.vapid_public) {
        const keys = webpush.generateVAPIDKeys();
        check(await db.from('push_config').update({vapid_public:keys.publicKey,vapid_private:keys.privateKey}).eq('id',1).is('vapid_public',null));
        config = check(await db.from('push_config').select('*').eq('id',1).single());
      }
      const jobs = check(await db.from('push_jobs').select('match_key,soort,status,sent_at,fout').eq('member_id',lid.id).order('created_at',{ascending:false}).limit(20));
      return json({publicKey:config.vapid_public,enabled:config.enabled,jobs,planning:await planning()});
    }
    if (body.action==='subscribe') {
      const sub = abonnement(body.subscription);
      check(await db.from('push_subscriptions').upsert({endpoint:sub.endpoint,member_id:lid.id,subscription:sub}));
      return json({ok:true});
    }
    if (body.action==='unsubscribe') { check(await db.from('push_subscriptions').delete().eq('member_id',lid.id).eq('endpoint',String(body.endpoint))); return json({ok:true}); }
    if (!lid.is_admin) throw new Fout('Alleen de testbeheerder mag scenario’s starten.',403);
    if (body.action==='stop-tests') {
      const matches = check(await db.from('matches').select('match_key').eq('bron','push-test')) ?? [];
      // Antwoord op de fictieve matches en markeer alleen hun meldingen als afgehandeld.
      // Daardoor blijven verslagen en sfeerbeelden staan en komen er geen latere herinneringen.
      for (const m of matches) {
        check(await db.from('attendance').upsert({match_key:m.match_key,member_id:lid.id,status:'afwezig'}));
        for (const soort of ['aanwezig72','aanwezig48','stemmen','stemherinnering']) check(await db.from('push_jobs').upsert({match_key:m.match_key,member_id:lid.id,soort,status:'skipped',fout:'Testscenario gestopt.'},{onConflict:'match_key,member_id,soort'}));
      }
      return json({ok:true});
    }
    if (body.action==='scenario') { const matchKey=await scenario(body.scenario,lid.id); return json({matchKey,...await verzendRij(config)}); }
    if (body.action==='run') return json(await verzendRij(config,typeof body.matchKey==='string' ? body.matchKey : undefined));
    throw new Fout('Onbekende actie.');
  } catch(e) { return json({error:e instanceof Fout ? e.message : 'Meldingen verwerken mislukt. Probeer opnieuw.'},e instanceof Fout ? e.status : 500); }
});
