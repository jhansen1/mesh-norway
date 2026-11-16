# Innsending til App Store

Status 16. november 2026: bygg 1.0 (3) ligger i TestFlight, tillatelsene er gitt, og tekster og skjermbilder er klare.
Følg stegene under i rekkefølge. Alt som skal limes inn, står enten her eller i filen det vises til.

| Fil | Innhold |
|---|---|
| `tekster-no.md` | Navn, undertittel, beskrivelse, søkeord: norsk (bokmål) |
| `tekster-en.md` | Det samme på engelsk |
| `screenshots/iphone-6.9/` | Seks skjermbilder, 1320 × 2868 (iPhone 6,9") |
| `screenshots/ipad-13/` | Seks skjermbilder, 2064 × 2752 (iPad 13") |
| `screenshots/*-dark/` | De samme i mørk modus. Ikke nødvendige; bruk ett sett, ikke en blanding |
| `../docs/` | Personvern- og støttesiden, klare til publisering |
| `privacy-policy.md`, `support.md` | Kildene til sidene i `docs/` |
| `tillatelse-jim.md` | Svarene fra Jim og Heigre, vilkårene og hvordan appen oppfyller dem |
| `TestFlight.md` | Opplasting og testing |
| `brev-til-jim.md`, `discord/` | Forespørselen og bildene som ble brukt på Discord. Trengs ikke lenger |

## Steg 0: det som må gjøres før du åpner App Store Connect

1. **Velg en kontaktadresse** for appen. Den vises offentlig på støttesiden og i personvernerklæringen. Sett den inn i
   `docs/privacy.md` og `docs/support.md` der det står `[navn og e-postadresse]` / `[name and e-mail address]` (to
   steder i hver fil).
2. **Publiser `docs/`** slik at de to sidene får hver sin adresse. Enklest er GitHub Pages: legg prosjektet i et
   offentlig repo, og slå på Pages for mappen `docs` (Settings > Pages > Deploy from a branch > `main` / `docs`).
   Adressene blir `https://<bruker>.github.io/<repo>/privacy` og `…/support`.
3. **Sett støtteadressen i appen** (`AppConfig.appSupportURL` i `MeshtasticNorwayMap/AppConfig.swift`) og last opp et
   nytt bygg med `TEAM_ID=2MDAAFA36Q Tools/testflight.sh`. Da viser About-siden lenken «Support for this app», som er
   Jims vilkår om at support går via appens eget prosjekt. Bygg 3 har teksten, men ikke lenken.
4. **Ta skjermbilder av tillatelsene:** Jims svar i Discord-tråden «Nytt Meshtastic-kart for Norge», og Heigres svar om
   navnet. Lagre dem som én PDF eller to bilder (`tillatelse-jim.md` har ordlyden).
5. **Test på en ekte enhet** via TestFlight: varsler i bakgrunnen, widgeter på låseskjermen, og overgangene til LinkSim
   og Meshtastic-appen.

## Steg 1: App Information

App Store Connect > appen > **App Information**.

| Felt | Verdi |
|---|---|
| Name | Mesh Norway |
| Subtitle (English) | Unofficial app for map.868.no |
| Primary Language | English (U.K.), slik appen ble opprettet |
| Bundle ID | no.meshnorway.map |
| Primary Category | Utilities |
| Secondary Category | Navigation |
| Content Rights | «Yes, it contains, shows, or accesses third-party content», og bekreft at du har rettighetene |

Legg til norsk: språkvelgeren øverst til høyre > **Norwegian Bokmål**. Navn: Mesh Norway. Undertittel: Uoffisiell app
for map.868.no.

Er «Mesh Norway» opptatt, sier App Store Connect det når du lagrer. Prøv da «Mesh Norway Map».

## Steg 2: Pricing and Availability

- **Price:** Free (0 kr). Jim forutsetter at appen er gratis.
- **Availability:** alle land. Appen er mest relevant i Norge, men det koster ingenting å la nordmenn i utlandet finne
  den. Vil du begrense den, velg bare Norway.

## Steg 3: App Privacy

- **Privacy Policy URL:** adressen til `privacy` fra steg 0.
- **Data collection:** «No, we do not collect data from this app». Appen har ingen kontoer, analyse, reklame eller
  tredjepartsbiblioteker. Serveren til map.868.no bruker IP-adresser bare i minnet til frekvensbegrensning og lagrer
  dem ikke, ifølge nettstedets egen erklæring.

## Steg 4: Age Rating

Svar «None» / «No» på alt. Resultatet blir 4+. Tre spørsmål å være bevisst på:

- **Unrestricted Web Access:** No. Appen viser ett nettsted, og eksterne lenker åpnes uten adressefelt.
- **Messaging and Chat:** No. Appen kan ikke sende noe.
- **User-Generated Content:** No er forsvarlig, fordi appen ikke lar noen legge inn innhold. Nodenavn er likevel
  fritekst som eierne av radioene har valgt. Svarer du «Yes», øker aldersgrensen, og Apple kan spørre om rapportering
  og filtrering (retningslinje 1.2).

## Steg 5: versjonen (1.0)

App Store Connect > appen > **1.0 Prepare for Submission**. Gjør dette to ganger, én gang per språk i språkvelgeren.

| Felt | English | Norwegian Bokmål |
|---|---|---|
| Promotional Text | `tekster-en.md` | `tekster-no.md` |
| Description | `tekster-en.md` | `tekster-no.md` |
| Keywords | `tekster-en.md` | `tekster-no.md` |
| What's New | vises ikke for første versjon | vises ikke for første versjon |
| Support URL | adressen til `support` | samme |
| Marketing URL | tomt | tomt |

Felles for begge språk:

| Felt | Verdi |
|---|---|
| Screenshots, iPhone 6.9" | `screenshots/iphone-6.9/` i rekkefølgen 01, 03, 05, 02, 06, 04 |
| Screenshots, iPad 13" | `screenshots/ipad-13/` i samme rekkefølge |
| Copyright | 2026 Jo Willie Hansen |
| Build | det nyeste bygget fra TestFlight (bygget fra steg 0) |
| Version Release | «Manually release this version», så bestemmer du selv tidspunktet |

Marketing URL står tomt fordi Jim ikke har svart på om https://map.868.no kan brukes der. Spør ham om du vil ha det.

**Export Compliance:** spørsmålet dukker ikke opp. Appen bruker bare systemets HTTPS, og `ITSAppUsesNonExemptEncryption`
er satt til `NO` i bygget.

## Steg 6: App Review Information

- **Sign-in required:** nei, ikke huk av.
- **Contact Information:** navn, telefon og e-post. Ses bare av Apple.
- **Attachment:** skjermbildene av tillatelsene fra steg 0.
- **Notes** (limes inn som den står):

```
This is an unofficial iOS app for the public website https://map.868.no, a live map of the Meshtastic radio mesh in Norway. It is published with the written permission of the site's author and operator, Jim C K Flaten (attached). His conditions are that the app is clearly marked as unofficial, that support is given by the app's own developer, and that the app is free. The app says "Unofficial app" under the map at all times and on its About screen. It needs no account and has no ads, analytics or third-party SDKs.

Beyond the website, the app adds:
- Notifications for watched nodes (quiet, heard again, low battery), also from a background refresh while the app is closed. They are local notifications; no push service is used.
- Home Screen and Lock Screen widgets: "Watched nodes" and "Mesh today".
- Offline start with the last received data.
- Native handling of sharing, of links to the Meshtastic app, and of the LinkSim coverage simulator.

To try the notifications: tap a node on the map, tap "☆ Watch" in its Details, then open the node list (the first button in the tool bar), tick "Notify me" and allow notifications. To try the widgets: watch a node as above, then add the "Mesh Norway" widgets from the Home Screen's widget gallery.

The screenshot of a notification shows the app's own wording, delivered to the simulator for the picture.

The name "Mesh Norway" is used with the consent of the Norwegian community of the same name (attached). Meshtastic is a registered trademark of Meshtastic LLC. The app is not affiliated with Meshtastic LLC, and says so on its About screen and in the description.
```

## Steg 7: send inn

Trykk **Add for Review**, så **Submit to App Review**. Vurderingen tar vanligvis ett til tre døgn. Når appen er
godkjent, slipper du den selv med **Release This Version**.

De mest sannsynlige tilbakemeldingene:

- **4.2 Minimum Functionality** («appen er en nettside»): svar med listen under «Beyond the website» i notatene, og
  pek på varslene og widgetene. Nettstedet kan installeres som PWA, så Apple kan spørre om nettopp dette.
- **5.2.2 Third-Party Sites/Services:** svar med tillatelsen fra Jim.
- **5.2.1 / varemerke:** pek på at «Meshtastic» ikke står i navnet, og på merknaden i beskrivelsen og på About-siden.

## Skjermbildene

Tatt i simulatoren fra det direkte kartet 16. november 2026, med `Tools/screenshots.sh`. Skriptet styrer appen gjennom
UI-testen `ScreenshotTests`, legger widgetene på Hjem-skjermen og tar bildene. Kjør det på nytt når utseendet endrer
seg (tredje argument er `light` eller `dark`):

```sh
Tools/screenshots.sh "iPhone 18 Pro Max" AppStore/screenshots/iphone-6.9
Tools/screenshots.sh "iPad Pro 13-inch (M5)" AppStore/screenshots/ipad-13
```

To ting å vite om dem:

- **Varselet i `06-notification.png` er stilt opp.** Teksten er appens egen, men varselet er sendt til simulatoren for
  bildets skyld; Gråkallen var ikke stille da bildet ble tatt. Notatene til App Review sier det. Vil du ikke vise en
  navngitt node slik, la bildet være.
- **Nodene i bildene er ekte.** Navn og posisjoner er de samme som alle ser på map.868.no.

## Språk

Oppføringen legges inn på engelsk og norsk. Brukere med norsk App Store ser den norske teksten, alle andre den
engelske. Selve appen og kartet er på engelsk, fordi kartet er Jims nettsted, og den norske beskrivelsen sier det rett
ut. Notatene til App Review må være på engelsk.
