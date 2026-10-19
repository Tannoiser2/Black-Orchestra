# Black Orchestra – conversione digitale (Godot 4.7)

Da 2 a 5 cospiratori a turni alterni (2 = solitario; da 3 a 5 si gioca a turno sullo stesso computer), ricavata dal modulo TTS (immagini) e dal regolamento italiano. Limiti di dossier e oggetti secondo il numero di giocatori (p.5).

## Avvio
1. Apri Godot 4.7 → *Importa* → seleziona `project.godot` in questa cartella.
2. Al primo avvio Godot importa gli asset (qualche secondo), poi premi ▶ (F5).

## Cosa c'è
- Menu, scelta dei cospiratori (17 schede base + 6 dell'espansione), difficoltà Facile/Normale/Difficile, varianti
  *Senso di Urgenza*, *Documenti Sorvegliati* e complotto promo *P*.
- Tabellone originale con caselle cliccabili e tooltip (consegne, effetti, chi è presente).
- Tutte le regole: penalità di Hitler e delegati, 3 azioni, Cospirare/Dissenso, consegne,
  Rilasciare, Trasferire, 7 stadi con eventi chiave/importanti, Raid della Gestapo, prigione e
  24 carte interrogatorio, Stadio 7 con caselle inaccessibili, complotti con requisiti facoltativi.
- Tutte le 84 carte evento, 51 carte cospiratore (+ promo), 17 capacità implementate.
- Carte ⚡ proposte automaticamente nel momento giusto (complotti, eventi che muovono Hitler...);
  *Comunicato Urgente* e *Niente di Nuovo* compaiono tra le azioni a costo zero.
- Salvataggio automatico all'inizio di ogni turno → "Continua partita" dal menu.

## Interfaccia
- Pedine con il volto del cospiratore; animazione del movimento lungo il percorso (pedine, Hitler e delegati), con il nome di chi si sta muovendo.
- Oggetti nella tua casella evidenziati in verde: cliccali per rivelarli o raccoglierli.
- Complotti tentabili: la carta nel dossier lampeggia in verde, Hitler viene cerchiato in rosso e compare un riquadro con requisiti necessari/facoltativi (✔ soddisfatti) e il numero di dadi che userai. Lo stesso riepilogo appare cliccando qualsiasi carta complotto.
- Con 3 o più cospiratori solo quello attivo è mostrato per esteso; clicca un riquadro compatto per espanderlo.

## Espansione «La Resistenza»
Nella schermata di preparazione compaiono i 6 nuovi cospiratori (Bernardis, von Oven, Moltke,
Erika von Tresckow, Libertas Schulze-Boysen, Mildred Fish-Harnack), usabili anche senza moduli,
e i tre moduli, attivabili insieme o separatamente:
- **Orchestra Rossa** – azione *Collocare* (telescriventi e volantini), 27 missioni su 3 colori,
  +1 dado ai complotti per ogni missione completata, oggetti Prove e Combattente della Resistenza,
  6 eventi *Telescrivente Scoperta*, 4 carte cospiratore.
- **Horst Kopkow** – Kopkow entra al QG Gestapo con il primo evento dello Stadio 2, si muove a fine
  turno verso il sospetto più alto, blocca la sua casella e provoca le 18 carte incontro; azione
  *Diversivo*; 12 eventi e 4 carte cospiratore. Se il mazzo incontro finisce, la partita è persa.
- **Circolo di Kreisau** – 2 tessere per casella (alleati, Raid, Qualsiasi Oggetto, +1 Motivazione/−1
  Supporto), azioni *Svelare* e *Reclutare*, 15 alleati con capacità monouso, status del Circolo
  applicato ai complotti, 6 eventi *Alleato Arrestato*.
Il pulsante con lo stato di ogni modulo (sotto l'intestazione) apre il pannello con missioni,
carte incontro scartate e alleati.

### Scelte di interpretazione dell'espansione
- Con più moduli insieme, le carte evento da rimuovere si sommano (es. tutti e tre: 6 carte dagli Stadi 2-7).
- Missioni: quelle che descrivono una situazione (es. *Arresto Imminente*, *Promuovere la Resistenza*)
  si completano da sole; quelle che chiedono di scartare qualcosa si completano gratis quando
  le condizioni sono soddisfatte; quelle con ➡ costano un'azione (il tiro).
- *Goebbels Informato*: si completa quando viene arrestato il cospiratore più vicino a Goebbels
  (per qualsiasi motivo); c'è anche l'azione per farsi arrestare apposta.
- *Combattente della Resistenza*: un Raid scarta la missione solo se il Combattente è già stato preso.
- *Telescrivente Scoperta* non rimuove la telescrivente permanente.
- Kopkow si muove lungo i collegamenti senza limiti di stadio.
- Moltke nei tiri di un solo dado: un'aquila non ha effetto (né penalità né successo).
- Mildred può ignorare qualsiasi evento pescato nel suo turno tranne i Raid (anche *Documenti Compromettenti*).
- Harald Poelchau si attiva da solo quando un cospiratore sta per essere arrestato e c'è già qualcuno in prigione.
- Margarete von Trotha su una tessera Alleato recluta subito un alleato.

## Scelte di interpretazione da verificare
- **Olbricht** "Muoviti di 2 caselle": implementato come *fino a* 2 caselle.
- **Carte interrogatorio**: in solitario la carta è visibile per intero (non c'è nessuno a cui nasconderla).
  Le opzioni non risolvibili per intero sono nascoste, come da regola.
- **Inizio Stadio 7**: lo spostamento di Hitler fuori dalle caselle (7) non conta come
  "evento che muove Hitler" (niente *Rallentare Hitler*/complotti C-D); *Ritirata Graduale* invece sì.
- **Requisiti facoltativi degli oggetti**: puoi usare anche gli oggetti degli altri cospiratori
  nella tua casella (regola p.10).
- Il primo giocatore è il primo cospiratore scelto.
- Variante *Luogotenenti Fidati* non implementata.

## Test
`tests/` contiene simulazioni headless (`godot --headless -s res://tests/sim.gd -- 200`)
e test di regole (`tests/unit.gd`, `tests/unit_res.gd`, `tests/sim_res.gd` per l'espansione). Non servono per giocare.
