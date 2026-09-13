/// <reference types="node" />
import {PGlite} from '@electric-sql/pglite';
import {readFileSync} from 'node:fs';
import {it,expect} from 'vitest';
it('start direct voor admins, voorkomt dubbele starts en houdt planning zonder GitHub-polling',async()=>{
 const db=new PGlite();try{
 await db.exec(`create role anon;create role authenticated;create schema extensions;create schema vault;create schema net;create schema cron;
 create table vrouwen_sync(id boolean,laatste_succes timestamptz,aangevraagd timestamptz,gestart timestamptz,afgerond timestamptz,fout text);
 create table club_matches(club_id text,is_test boolean,aftrap timestamptz);
 create table vault.decrypted_secrets(name text,decrypted_secret text);
 insert into vault.decrypted_secrets values('twizzit_github_token','test');
 create table calls(id serial);
 create function net.http_post(url text,headers jsonb,body jsonb,timeout_milliseconds integer) returns bigint language plpgsql as $$begin insert into calls default values;return 1;end$$;
 create function cron.schedule(text,text,text) returns integer language sql as $$select 1$$;
 create function club_admin(text) returns boolean language sql as $$select current_setting('test.admin',true)='yes'$$;
 select set_config('test.admin','no',false);
 insert into vrouwen_sync values(true,now(),null,null,now(),null);`);
 const sql=readFileSync(new URL('../../../supabase/app_schema.sql',import.meta.url),'utf8').split('-- Rechtstreekse Twizzit-start:')[1];await db.exec('-- Rechtstreekse Twizzit-start:'+sql);
 await expect(db.exec("select club_twizzit('vrouwen',true)")).rejects.toThrow(/admin/);
 await db.exec("set role authenticated");await expect(db.exec('select vrouwen_dispatch(true)')).rejects.toThrow(/permission denied/);await db.exec('reset role');
 expect((await db.query('select vrouwen_dispatch(false) started')).rows[0]).toEqual({started:false});
 await db.exec("select set_config('test.admin','yes',false);select club_twizzit('vrouwen',true);select club_twizzit('vrouwen',true)");
 expect((await db.query('select count(*)::int n from calls')).rows[0]).toEqual({n:1});
 await db.exec("update vrouwen_sync set dispatch_at=null,aangevraagd=null;insert into club_matches values('vrouwen',true,now()-interval '2 hours')");
 expect((await db.query('select vrouwen_dispatch(false) started')).rows[0]).toEqual({started:false});
 await db.exec("update vrouwen_sync set laatste_succes=now()-interval '3 hours';update club_matches set is_test=false");
 expect((await db.query('select vrouwen_dispatch(false) started')).rows[0]).toEqual({started:true});
 }finally{await db.close();}
},30000);
