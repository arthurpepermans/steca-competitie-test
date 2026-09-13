export type ZaalFormatie='2-2'|'3-1'|'1-2-1';
export const zaalFormatie=(waarde:unknown):ZaalFormatie=>waarde==='3-1'||waarde==='1-2-1'?waarde:'2-2';
// Vaste plaatscodes bewaren de speelsters en slotjes bij een formatiewissel.
export const zaalRijen:Record<ZaalFormatie,string[][]>={'2-2':[['GK'],['LB','RB'],[],['LW','RW']],'3-1':[['GK'],['LB','RB','LW'],[],['RW']],'1-2-1':[['GK'],['LB'],['RB','LW'],['RW']]};
export const zaalLabels:Record<ZaalFormatie,Record<string,string>>={'2-2':{GK:'Doelvrouw',LB:'Linksachter',RB:'Rechtsachter',LW:'Linksvoor',RW:'Rechtsvoor'},'3-1':{GK:'Doelvrouw',LB:'Linksachter',RB:'Centrale verdediger',LW:'Rechtsachter',RW:'Spits'},'1-2-1':{GK:'Doelvrouw',LB:'Verdediger',RB:'Linksmidden',LW:'Rechtsmidden',RW:'Spits'}};
export const zaalKort:Record<ZaalFormatie,Record<string,string>>={'2-2':{GK:'GK',LB:'LB',RB:'RB',LW:'LW',RW:'RW'},'3-1':{GK:'GK',LB:'LB',RB:'CB',LW:'RB',RW:'ST'},'1-2-1':{GK:'GK',LB:'CB',RB:'LM',LW:'RM',RW:'ST'}};
