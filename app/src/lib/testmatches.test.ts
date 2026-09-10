import { expect,it,vi,beforeEach } from 'vitest';
const mock=vi.hoisted(()=>({rpc:vi.fn(),haal:vi.fn(),wis:vi.fn()}));
vi.mock('./supabase',()=>({supabase:{rpc:mock.rpc}}));
vi.mock('./media',()=>({haalSfeerbeelden:mock.haal,verwijderSfeerbeeld:mock.wis}));
import { verwijderTestmatch } from './testmatches';
beforeEach(()=>vi.resetAllMocks());
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
