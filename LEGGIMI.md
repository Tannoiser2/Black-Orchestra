# Black Orchestra – conversione digitale (Godot 4.7)

Da 2 a 5 cospiratori a turni alterni (2 = solitario; da 3 a 5 si gioca a turno sullo stesso computer), ricavata dal modulo TTS (immagini) e dal regolamento italiano. Limiti di dossier e oggetti secondo il numero di giocatori (p.5).

## Avvio
1. Apri Godot 4.7 → *Importa* → seleziona `project.godot` in questa cartella.
2. Al primo avvio Godot importa gli asset (qualche secondo), poi premi ▶ (F5).

## Cosa c'è
- Menu, scelta dei 2 cospiratori (17 schede), difficoltà Facile/Normale/Difficile, varianti
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
e test di regole (`tests/unit.gd`). Non servono per giocare.
