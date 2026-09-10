# Matchverslag en pushmeldingen: testproef

Deze implementatie wordt uitsluitend gepubliceerd via `steca-competitie-test` op `test.stecajuniors.app`, met database `fhgghcksvnyxfwkielzx`. Productie is niet gewijzigd. De recente opstellingsfuncties en de openbare homepage zijn naar de testbasis bijgewerkt; testdatabasebeveiliging, fictieve gegevens en de eigen opslag zijn behouden.

## Gebruiken

Maak een testlogin met het e-mailadres van het bestaande hoofdadmin-testprofiel. Accounts staan los van productie. Op iPhone installeer je het testsubdomein als aparte beginschermapp. Ga naar Profiel > Meldingen en testcentrum en zet meldingen aan. De server laat uitsluitend `push_config.allowed_member` toe, ook voor het koppelen van een toestel. Alleen de databasebeheerder kan die ontvanger wijzigen.

Het testcentrum maakt fictieve wedstrijden en simuleert 72 uur, 48 uur, een vroege score, een late score, drie uur sinds de eerste melding, reeds ingevulde aanwezigheid en reeds uitgebrachte stemmen. Bij het scenario van drie uur wordt het eerste verzendmoment uitdrukkelijk gesimuleerd. Met Bestaande testscenario's stoppen voorkom je latere herinneringen voor die scenarios. Het verslag en eventuele beelden blijven bewaard.

## Timing en verzending

Aftraptijden worden in PostgreSQL met Europe/Brussels naar UTC omgerekend. Geen geldige datum of tijd betekent geen melding. Aanwezigheidsherinneringen: vanaf 72 uur en vanaf 48 uur, uitsluitend zonder aanwezigheidsrecord; onzeker en afwezig gelden ook als ingevuld. Er wordt geen 72-uursbericht ingehaald zodra de 48-uursperiode begonnen is.

De stemuitnodiging vertrekt vanaf het maximum van aftrap + 80 minuten en het eerste door staf ingevoerde scoremoment. Scorecorrecties verschuiven het eerste scoremoment niet. Alleen aanwezige leden zonder stem komen in aanmerking, tot de bestaande stemdeadline. De herinnering is drie uur na de eerste door de pushdienst aangenomen verzending. De cron draait elke minuut, dus er kan maximaal ongeveer een minuut planningsvertraging zijn, naast vertraging bij de pushdienst of het toestel.

Een unieke job per wedstrijd, lid en soort voorkomt normale dubbelen. Een databaselease voorkomt parallelle verzending. Bij storing volgen herpogingen en bij een verlopen abonnement wordt dat verwijderd. De status Verzonden betekent aangenomen door een pushdienst, niet aantoonbaar gelezen of ontvangen door een telefoon. Bij een procescrash na aannemen en voor databasebevestiging is een herhaling mogelijk; een vaste notification-tag en push-topic beperken dubbelen. Dit is geen exactly-once transport.

De Edge Function weigert iedere andere Supabase-project-URL. VAPID-sleutels worden eenmalig in de backend gegenereerd en blijven in een afgeschermde tabel. Geen geheime sleutel gaat naar de browser of git. `verify_jwt=false` is nodig voor de geheime cronoproep; gebruikersacties valideren hun JWT via Supabase Auth en controleren daarna exact het toegestane lid. Abonnements-URL's zijn begrensd tot de pushdiensten van Apple, Google, Mozilla en Microsoft.

## Matchverslag

Kalender > Matchverslag bekijken toont uitslag, thuis/uit-tijdlijn, assist per goal en kaarten in de clubstijl. Sfeerbeelden opent eronder. Staf kan het verslag en de score bewerken, met versiecontrole tegen gelijktijdig overschrijven. De geregistreerde clubuitslag wordt apart bewaard; officiële federatiegegevens worden niet overschreven. Bestaande `match_stats` zonder tijdlijn worden als totalen getoond zonder verzonnen minuten. De gedetailleerde tijdlijn is aanvullend en wijzigt de bestaande seizoensstatistieken niet automatisch.

## Validatie en installatie

`npm test` en `npm run build` in app. `supabase/tests/match-proef.sql` controleert rechten, tijdzone, opslag, versieconflicten, stabiel scoremoment en exclusief claimen van jobs; de gehele testtransactie wordt teruggedraaid. Het mobiele ontwerp is op 390px gecontroleerd, inclusief openen/sluiten van het album en horizontale overflow.

Alle schemawijzigingen staan in `supabase/app_schema.sql`. De Edge Function is `match-push` met `_shared/meldingen.ts`; bij publiceren via de dashboardeditor zijn die twee bestanden samengevoegd. Bij CLI-publicatie blijven ze afzonderlijke bronbestanden. De cron maakt uitsluitend een oproep als push_config.enabled waar is en er een publieke VAPID-sleutel bestaat. De ontvanger wordt bewust apart in de testdatabase ingesteld, niet vanuit de app.

Echte ontvangst op een iPhone moet nog bevestigd worden na registratie en toestemming op het testtoestel. Voor later gebruik door de hele ploeg is een afzonderlijke, expliciet goedgekeurde productiemigratie nodig; neem de testcron, testontvanger en scenariofuncties niet blind over.
