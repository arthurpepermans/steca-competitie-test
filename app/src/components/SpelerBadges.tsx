import { haalMatches } from '../lib/api';
import { useAsync } from '../lib/useAsync';
import { Link } from 'react-router-dom';
import { BADGES, seizoenNu } from '../lib/badgeCatalogus';
import { useBadges } from '../lib/badges';
import { BadgeIcoon } from './BadgeIcoon';
import { Fout } from './Layout';

export function SpelerBadges({memberId}:{memberId:string}) {
  const info = useBadges();
  const matches = useAsync(haalMatches);
  const eigen = (info.data ?? []).filter(b => b.member_id === memberId);
  const seizoen = seizoenNu();
  return <section className="kaart speler-badges"><h2>Badges</h2>
    <Fout tekst={info.fout}/>
    {info.fout && <button className="knop licht" onClick={info.herlaad}>Opnieuw laden</button>}
    {!info.data && info.laden && <p>Badges laden…</p>}
    {info.data && !eigen.length && <p className="zacht">Nog geen badges verzameld.</p>}
    {(['Actieve titels','Verzameling','Vorige seizoenen'] as const).map(groep => {
      const records = eigen.filter(t => {
        const b=BADGES.find(b=>b.id===t.badge_id);
        return groep==='Verzameling' ? b?.soort==='verzameling' : groep==='Vorige seizoenen'
          ? b?.soort==='seizoen' && t.seizoen!==seizoen : b?.soort==='alltime' || (b?.soort==='seizoen' && t.seizoen===seizoen);
      });
      return records.length>0 && <div key={groep}><h3>{groep}</h3><div className="badge-profiel-grid">
        {BADGES.filter(b=>records.some(t=>t.badge_id===b.id)).map(b => {
          const lijst=records.filter(t=>t.badge_id===b.id);
          return <details className="badge-profiel" key={b.id}><summary><BadgeIcoon id={b.id}/><strong>{b.titel}</strong>{lijst.length>1 && <small>{lijst.length}×</small>}{b.soort==='seizoen' && <small>{[...new Set(lijst.map(t=>t.seizoen?.replace('-','/')))].join(', ')}</small>}</summary>
            <p>{b.uitleg}</p>{lijst.map(t => <div key={t.id}>{t.match_key && <Link to={`/match/${encodeURIComponent(t.match_key)}`}>{(() => {const m=matches.data?.find(m=>m.match_key===t.match_key);return m ? `${m.datum} · ${m.thuis} - ${m.uit}` : 'Bekijk matchverslag';})()}</Link>}</div>)}
          </details>;
        })}
      </div></div>;
    })}
  </section>;
}
