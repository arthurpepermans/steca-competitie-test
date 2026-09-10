import { expect,it,vi,beforeEach } from 'vitest';
const mock=vi.hoisted(()=>({rpc:vi.fn(),haal:vi.fn(),wis:vi.fn(),range:vi.fn()}));
vi.mock('./supabase',()=>({supabase:{rpc:mock.rpc,from:()=>{
 const q={select:()=>q,or:()=>q,order:()=>q,range:mock.range};return q;
}}}));
vi.mock('./media',()=>({haalSfeerbeelden:mock.haal,verwijderSfeerbeeld:mock.wis}));
import { haalTestmatchSleutels, verwijderAlleTestmatches, verwijderTestmatch } from './testmatches';
beforeEach(()=>vi.resetAllMocks());
it('haalt ook testmatches voorbij de eerste pagina op',async()=>{
 mock.range.mockResolvedValueOnce({data:Array.from({length:200},(_,i)=>({match_key:`test-${i}`})),error:null}).mockResolvedValueOnce({data:[{match_key:'laatste'}],error:null});
 const sleutels=await haalTestmatchSleutels();
 expect(sleutels).toHaveLength(201);expect(sleutels.at(-1)).toBe('laatste');
 expect(mock.range.mock.calls).toEqual([[0,199],[200,399]]);
});
it('gaat na een geweigerde match verder en rapporteert gedeeltelijk succes correct',async()=>{
 mock.rpc.mockImplementation(async(_naam,args)=>({error:args.p_match_key==='echte-match' ? new Error('Geen testmatch') : null}));
 mock.haal.mockResolvedValue({beelden:[]});
 const voortgang=vi.fn();
 expect(await verwijderAlleTestmatches(['test-a','echte-match','test-b','test-a'],voortgang)).toEqual({verwijderd:2,mislukt:['echte-match']});
 expect(mock.haal.mock.calls).toEqual([['test-a'],['test-b']]);
 expect(mock.rpc.mock.calls.filter(c=>c[0]==='verwijder_testmatch').map(c=>c[1].p_match_key)).toEqual(['test-a','test-b']);
 expect(voortgang).toHaveBeenLastCalledWith(3,3);
});
it('raakt beelden niet aan wanneer de server de testmatch weigert',async()=>{
 mock.rpc.mockResolvedValue({error:new Error('Geen testmatch')});
 await expect(verwijderTestmatch('gewone-match')).rejects.toThrow('Geen testmatch');
 expect(mock.haal).not.toHaveBeenCalled();expect(mock.wis).not.toHaveBeenCalled();
});
it('ruimt beelden op voor de wedstrijd zelf wordt verwijderd',async()=>{
 mock.rpc.mockResolvedValue({error:null});
 mock.haal.mockResolvedValueOnce({beelden:[{path:'test/foto.jpg'}]}).mockResolvedValueOnce({beelden:[]});
 await verwijderTestmatch('test-invoer-123');
 expect(mock.wis).toHaveBeenCalledWith('test/foto.jpg');
 expect(mock.rpc.mock.calls.map(c=>c[0])).toEqual(['controleer_testmatch','verwijder_testmatch']);
 expect(mock.wis.mock.invocationCallOrder[0]).toBeLessThan(mock.rpc.mock.invocationCallOrder[1]);
});
