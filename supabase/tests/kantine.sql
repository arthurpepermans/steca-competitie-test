begin;
insert into auth.users(id,email,raw_user_meta_data) values
('00000000-aaaa-4000-8000-000000000001','qa-kantine-supporter@example.invalid','{"account_type":"supporter","naam":"QA Supporter"}'),
('00000000-aaaa-4000-8000-000000000002','qa-kantine-lid@example.invalid','{"functie":"speler","voornaam":"QA","achternaam":"Kantine","naam":"QA Kantine"}');
update members set status='actief' where user_id='00000000-aaaa-4000-8000-000000000002';
insert into matches(match_key,seizoen,reeks,datum,uur,thuis_id,uit_id,thuis,uit,status,bron,fetched_at)
values('qa-kantine','QA','QA',current_date+2,'15:00',152,999999,'Steca Juniors','QA','gepland','qa',now());
do $$ begin
 if exists(select 1 from members where user_id='00000000-aaaa-4000-8000-000000000001') then raise exception 'Supporter staat tussen leden'; end if;
 if not exists(select 1 from supporter_profiles where user_id='00000000-aaaa-4000-8000-000000000001') then raise exception 'Supporter ontbreekt'; end if;
 if pronostiek_punten(1,1,2,2)<>5 or pronostiek_punten(2,0,4,2)<>5 or pronostiek_punten(2,0,2,4)<>0 or pronostiek_punten(2,0,2,1)<>3 or pronostiek_punten(2,0,2,0)<>10 then raise exception 'Punten fout'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-aaaa-4000-8000-000000000001',true);
do $$ begin
 if is_actief() or is_staf() or is_admin() or my_member_id() is not null then raise exception 'Supporter kreeg clubrechten';end if;
end $$;
select bewaar_pronostiek('qa-kantine',1,1);
select bewaar_dream_xi('4-3-3','{}','{}',null);
do $$ begin
 if (select count(*) from dream_xi)<>1 then raise exception 'Eigen Dream niet leesbaar';end if;
 begin
  insert into pronostieken values('qa-kantine','00000000-aaaa-4000-8000-000000000002',9,9,now());
  raise exception 'Directe insert toegestaan';
 exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-aaaa-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from dream_xi) or exists(select 1 from pronostieken) or exists(select 1 from supporter_profiles) then raise exception 'Privégegevens van ander zichtbaar';end if;
end $$;
select bewaar_pronostiek('qa-kantine',2,0);
select bewaar_dream_xi('4-3-3','{}','{}',null);
reset role;
select set_config('request.jwt.claim.sub','',true);
update matches set datum=current_date-1,status='gespeeld',thuis_score=2,uit_score=2 where match_key='qa-kantine';
do $$ begin
 if (select punten from kantine_klassement('QA') where user_id='00000000-aaaa-4000-8000-000000000001')<>5 then raise exception 'Gelijkspelklassement fout';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-aaaa-4000-8000-000000000001',true);
do $$ begin
 begin
  perform bewaar_pronostiek('qa-kantine',2,2);
  raise exception 'Te late voorspelling toegestaan';
 exception when raise_exception then if sqlerrm not like 'Pronostieken zijn gesloten%' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
update matches set thuis_score=4,uit_score=2 where match_key='qa-kantine';
do $$ begin
 if (select punten from kantine_klassement('QA') where user_id='00000000-aaaa-4000-8000-000000000002')<>5 then raise exception 'Correctie niet herberekend';end if;
end $$;
set local role anon;
select * from kantine_klassement('QA');
reset role;
rollback;
select 'OK: supporterregistratie apart, geen clubrechten, private opslag, exacte punten, aftrapblokkade en correcties' as resultaat;
