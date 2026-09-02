<div align="center">

# Proton VPN per Decky

### La VPN nel QAM, senza trasformare il controller in un mouse.

Controlla il client Proton VPN per Windows da Steam Big Picture con stato reale, scelta del Paese e collegamenti recenti.

[![Release](https://img.shields.io/github/v/release/LoZazaMastro/Proton-VPN?style=for-the-badge&label=Release&labelColor=111111&color=ffffff)](https://github.com/LoZazaMastro/Proton-VPN/releases/latest)
[![Licenza MIT](https://img.shields.io/badge/Licenza-MIT-ffffff?style=for-the-badge&labelColor=111111)](LICENSE)

</div>

## Proton VPN, senza lasciare Steam

Il plugin controlla un'installazione esistente di Proton VPN e mantiene il pannello essenziale: interruttore, stato, Paese attivo, selettore e gli ultimi sei collegamenti riusciti. Le bandiere sono incluse localmente e i nomi dei Paesi seguono la lingua di Steam.

- avvio automatico di `ProtonVPN.Client.exe` quando necessario;
- stato e Paese letti dagli eventi reali del client Proton;
- operazioni di connessione e disconnessione serializzate;
- richieste duplicate verso lo stesso Paese ignorate;
- fino a sei Paesi recenti, senza duplicati;
- interfaccia localizzata per tutte le lingue complete attualmente esposte da Steam;
- layout RTL per l'arabo;
- nessuna automazione di mouse o tastiera, injection o modifica dei binari Proton.

## Requisiti

- Windows;
- [Decky Loader](https://decky.xyz) e Steam Big Picture;
- client ufficiale Proton VPN già installato e autenticato almeno una volta.

## Limite tecnico attuale

Proton VPN per Windows non espone una CLI pubblica supportata per cambiare Paese. La versione 1.0.0 usa quindi `RecentConnections.bin` e un passaggio temporaneo su `DefaultConnection=Last`.

Se scegli un Paese diverso mentre la VPN è già connessa, il plugin esegue un singolo reset deterministico del tunnel prima che il client ricarichi la connessione scelta. Se selezioni il Paese già attivo, non riavvia processi o servizi. Non viene presentato come uno switch realmente privo di riavvio.

L'alternativa sarebbe il controller gRPC interno di Proton, che autorizza il client ufficiale. Il plugin non aggira questa protezione con injection o patch invasive.

## Installazione

Puoi installare e aggiornare Proton VPN per Decky dal Plugin Store di [Playhub](https://github.com/LoZazaMastro/Playhub), oppure scaricare lo ZIP dall'[ultima release](https://github.com/LoZazaMastro/Proton-VPN/releases/latest) e installarlo da **Decky → Impostazioni → Sviluppatore → Installa plugin da ZIP**.

## Licenza

Il plugin è distribuito con licenza [MIT](LICENSE). Proton VPN e i relativi marchi appartengono a Proton AG; questo progetto è indipendente e non è affiliato o approvato da Proton.

<div align="center">

Creato e mantenuto da **[LoZazaMastro](https://github.com/LoZazaMastro)**.

</div>
