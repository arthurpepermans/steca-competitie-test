# Steca Juniors Test

Aparte testomgeving: https://test.stecajuniors.app.

Deze repository gebruikt uitsluitend Supabase-project `fhgghcksvnyxfwkielzx` (Steca Juniors Test), met eigen accounts en fictieve spelers en wedstrijden. Er draait geen competitie-sync. Wijzigingen worden niet automatisch naar de echte clubapp overgenomen.

## Ontwikkelen

1. Clone deze repository en maak een eigen branch.
2. Ga naar `app` en voer `npm ci` uit.
3. Kopieer `.env.example` naar `.env.local` en vul de publieke sleutel van **Steca Juniors Test** in. Gebruik nooit productiesleutels.
4. Start met `npm run dev` en open het adres dat Vite toont.
5. Controleer `npm test` en `npm run build`, push je branch en maak een pull request naar `main` van deze testrepository.
6. Na samenvoegen publiceert GitHub Actions automatisch op het testsubdomein.

## Database en accounts

De structuur staat in `supabase/schema.sql` en `supabase/app_schema.sql`, in die volgorde uitvoeren. Het tweede bestand bevat fictieve startgegevens en kan herhaald worden.

Accounts van de echte clubapp werken hier niet automatisch. Registreer een apart testaccount. Beheerders worden vooraf gekoppeld aan hun e-mailadres; nieuwe registraties krijgen nooit automatisch adminrechten. Laat e-mailbevestiging ingeschakeld.

Supabase-dashboardtoegang is afzonderlijk van GitHub-toegang. Voor structurele databasewijzigingen gebruikt Arthur het testproject in Supabase.

Voor overname naar productie: beoordeel de wijziging en maak een afzonderlijke pull request in de productierepository. Neem de testspecifieke configuratie en fictieve gegevens niet over.
