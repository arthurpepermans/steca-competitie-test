# Badges testen

Alleen test.stecajuniors.app en Supabase fhgghcksvnyxfwkielzx.

Open Profiel > Meldingen en testcentrum > Badges. De aangewezen beheerder uit
push_config.allowed_member kan elk van de 40 badges aan actieve clubleden
toewijzen en weer verwijderen. Supporters verschijnen niet in de keuzelijst.
De RPC's controleren dezelfde rechten; rechtstreeks schrijven naar de tabel
is niet toegestaan voor gebruikers.

Naast handmatige voorbeelden worden badges nu automatisch berekend uit de wedstrijdcijfers. Zie BADGES.md voor de regels. Alle testtoewijzingen staan
apart in test_badge_toewijzingen en mogen nooit naar productie gekopieerd worden.

## Proefgevallen

- Wijs Gouden Stier van het huidige seizoen toe: zichtbaar op profiel, veld en bank.
- Wijs dezelfde titel ook aan een tweede speler toe: gedeelde leiders zijn mogelijk.
- Wijs een oud seizoen toe: alleen bij Vorige seizoenen op het profiel.
- Wijs GOAT toe: blijft op het truitje staan bij een nieuw seizoen.
- Wijs een verzamelbadge toe: alleen op het profiel.
- Wijs Hattrick of Junior van de Match toe voor verschillende wedstrijden:
  het profiel toont het aantal en links naar de afzonderlijke matchverslagen.
- Dezelfde badge/persoon/seizoen/wedstrijd nogmaals invoeren: foutmelding.
- Verwijderen: verdwijnt op profiel en opstelling. Andere tabbladen vernieuwen
  bij focus, of binnen 30 seconden zolang ze zichtbaar zijn.
- Veel leidersbadges tegelijk: drie kleine iconen en aantal+ links net boven de naambalk;
  tikken opent de volledige lijst. De positie en spelernaam blijven leesbaar.

Alle iconen gebruiken dezelfde cirkel, achtergrond en vaste kleuren. De
truitjes en wasmand gebruiken de bestaande tekeningen van de app.
Seizoenen wisselen op 1 juli. Collectibles worden nooit als actieve titel getoond.

## Database en controles

Het idempotente SQL-blok staat onderaan supabase/app_schema.sql. Ook
openbare_opstellingen bevat nu member_id als koppeling naar de publieke badges.
Dit is in de testdatabase uitgevoerd. De tabel bevat geen accountgegevens.

Gecontroleerd: alle 40 RPC-toewijzingen en verwijderingen, duplicaten,
matchvereiste, ongeldige seizoenen en geweigerde onbevoegde mutaties. Die
proefgegevens zijn in een transactie teruggedraaid. Unit-tests bewaken
seizoenswissels, gedeelde leiders en de scheiding tussen titels en collectibles.

## Eigen badgevolgorde

Op het eigen profiel rangschikt een clublid badges met de pijltjes. Dit wordt
meteen opgeslagen in test_badge_voorkeuren en in de opstelling gebruikt.
Drie actieve badges zijn zichtbaar, gevolgd door het aantal extra badges.
Nieuwe badges zonder voorkeur sluiten achteraan aan. Andere profielen zijn
alleen te bekijken. De RPC leidt de eigenaar af uit de sessie en laat alleen
badges toe die deze persoon bezit; toewijzingen blijven ongewijzigd.

