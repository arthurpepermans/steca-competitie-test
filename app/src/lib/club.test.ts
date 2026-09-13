import {it,expect} from 'vitest';
import {clubPunten} from './club';
it('kent de afgesproken pronopunten toe in de juiste richting',()=>{expect(clubPunten(2,0,2,0)).toBe(10);expect(clubPunten(2,0,4,2)).toBe(5);expect(clubPunten(1,1,3,3)).toBe(5);expect(clubPunten(2,0,1,0)).toBe(3);expect(clubPunten(2,0,2,4)).toBe(0);});
