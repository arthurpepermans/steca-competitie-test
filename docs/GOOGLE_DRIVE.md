# Google Drive-koppeling (test)

Deze eerste stap verbindt de clubopslag. De bestaande wedstrijdalbums blijven op
Supabase Storage totdat de Drive-upload-, afspeel- en verwijderfuncties gereed en
getest zijn. Er worden geen bestaande beelden verplaatst.

## Beheer

Een actieve admin opent Mijn profiel > Google Drive beheren, of `/#/drive`.
Het afgesproken Google-account is `arthur.pepermanss@gmail.com`.
Na toestemming maakt de server de private map `Steca Juniors - Sfeerbeelden TEST`
aan met het beperkte `drive.file`-recht. De eerder handmatig gemaakte clubmap en
andere bestanden zijn niet toegankelijk met dit recht.

Google-project: `steca-juniors-clubapp`. OAuth-client: `Steca Juniors Drive - test`.
Callback: `https://fhgghcksvnyxfwkielzx.supabase.co/functions/v1/drive-connect/callback`.
Google OAuth staat voorlopig in Testing. De toestemming vervalt daardoor na zeven
dagen; opnieuw verbinden is dan nodig. Voor blijvend gebruik moet de Google-configuratie
worden afgerond voor productie. Dit staat los van het publiceren van de webapp.

## Deployment

Voer de Google Drive-sectie onderaan `supabase/app_schema.sql` uit in de testdatabase.
Bewaar `GOOGLE_DRIVE_CLIENT_ID` en `GOOGLE_DRIVE_CLIENT_SECRET` uitsluitend als Edge
Function Secrets. Deploy `supabase/functions/drive-connect/index.ts` met de
`verify_jwt = false`-instelling in `supabase/config.toml`. De callback heeft geen
Supabase-JWT; alle POST-acties valideren de sessie en actuele adminrechten zelf.

De refresh token is AES-GCM-versleuteld in een tabel zonder anon/authenticated
toegang. De encryptiesleutel wordt afgeleid van het client secret. Na rotatie van
het client secret moet de beheerder opnieuw verbinden. Deel nooit het client
secret, de refresh token of OAuth-codes via chat, frontendcode of GitHub.

OAuth gebruikt PKCE en een gehasht, eenmalig bewijs met tien minuten geldigheid.
De callback controleert opnieuw de adminstatus en de geverifieerde Google-identiteit.
De functie is expliciet beperkt tot het Supabase-testproject en testdomein.

## Gecontroleerd

- Bestaande 49 apptests en productiebuild slagen.
- Deno typecontrole van de Edge Function slaagt.
- Gedeployde functie weigert ontbrekende login (401), vreemde origin (403) en
  een ongeldige callback (400).
- De eerste toestemming met het echte Google-account en het opslaan van de
  verbinding moeten nog in de browser doorlopen worden.
