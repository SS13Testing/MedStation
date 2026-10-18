# MedStation

A fork of Monkestation 2.0 (tgstation, BYOND) that is entirely about running a hospital. NPC patients arrive with
ailments and the staff diagnose and treat them: surgery, medication, stasis, transplants. There are no antagonists.
It is playable alone and open to anyone who wants to join.

## The game loop

1. **Patients arrive** two ways, chosen by the patient director (`patient_director.dm`):
   - **Ambulance**: pulls into the ambulance bay and unloads 1-3 patients on stretchers. These are the serious cases.
   - **Walk-in**: appears at the waiting room door, finds a chair and waits. Minor cases. If nobody takes them out of the
     waiting room in time they leave ("left without being seen"), which costs reputation.
2. **Staff diagnose and treat.** Every patient arrives holding an intake chart (crew notes only, no diagnosis).
   Untreated patients get worse once their deadline passes, unless they are on a stasis bed.
3. **Cured patients are discharged**, the medical budget is paid, reputation goes up. Deaths cost twice as much
   reputation as a cure earns.
4. **Spend the budget** at a hospital terminal (triage and staff lounge): surgical tools, blood, drugs, defibrillators,
   donor organs. Orders arrive as a crate in the ambulance bay.

5. **Triage**: tag patients with a triage tagger (green minor, yellow serious, red critical, black beyond help; use it in hand
   to change colour). Tagging a patient the right colour earns a reputation and credit bonus when they are discharged.
6. **Hospital events** (`hospital_events.dm`) shake up a shift every 10-20 minutes: a mass casualty incident, a flu
   outbreak, rush hour. There is no storyteller and no antagonist.

7. **Allergies**: about 30% of patients are allergic to a common medicine and the chart lists it most of the time, not
   always. A wrong dose causes anaphylaxis (epinephrine treats it), blocks discharge and costs reputation.
8. **Hospital tiers**: reputation moves the hospital between Failing clinic, Local clinic, Community, Regional, Teaching
   hospital and Centre of excellence. Higher tiers unlock rarer, harder cases, pay better and hold more patients.

New staff get a welcome guide at spawn (`guide.dm`); the `Hospital Guide` verb shows it again. A shift report (treated, lost,
left unseen, per-case results, budget) is added to the round end report.

The number of patients scales with how many medical staff are on the station, so a solo player gets a calm hospital
and a full team gets a busy one. There is a `Hospital Status` verb (IC tab) and admin verbs under Admin.Fun:
`Spawn Patient`, `Send Ambulance`, `Trigger Hospital Event`, `Toggle Patient Director`.
The shift never ends by itself (no automatic crew transfer vote): the staff call the shuttle when they are done.

## Where things are

| What | Where |
|---|---|
| Patient director, records, arrival logic, admin verbs | `monkestation/code/modules/medstation/patient_director.dm` |
| Patient cases (the ailments) | `monkestation/code/modules/medstation/patient_cases.dm` |
| Ambulance, walk-in and parking landmarks | `monkestation/code/modules/medstation/ambulance.dm` |
| Welcome guide and verb | `monkestation/code/modules/medstation/guide.dm` |
| Hospital events | `monkestation/code/modules/medstation/hospital_events.dm` |
| Triage tags and tagger | `monkestation/code/modules/medstation/triage.dm` |
| Hospital terminal and supply list | `monkestation/code/modules/medstation/hospital_terminal.dm` |
| Hospital areas (no power needed) | `monkestation/code/modules/medstation/areas.dm` |
| Shared defines | `code/__DEFINES/medstation.dm` |
| Unit tests | `code/modules/unit_tests/medstation.dm` |
| The map | `_maps/map_files/debug/medstation.dmm` (generated, see below), `_maps/medstation.json` |
| Map generator | `tools/medstation_mapgen/hospital.py` (+ `dmm.py`, a small .dmm reader/writer) |
| Config changes | `config/config.txt` (`DISABLE_STORYTELLER`, `LOAD_JOBS_FROM_TXT`), `config/jobconfig.toml`, `config/maps.txt` |

Antagonists and random events are off because the storyteller is disabled. Jobs are limited to medical roles in
`config/jobconfig.toml` (Assistant stays open as the overflow role).

## The map is generated

Do not edit `medstation.dmm` by hand. Edit `tools/medstation_mapgen/hospital.py` and run

    python3 tools/medstation_mapgen/hospital.py

It wipes the old Runtime Station interior and builds the hospital (rooms, doors, furniture, landmarks). The hospital
areas do not need APCs, cables or pipes (`requires_power = FALSE`, station air on the floors), so the layout is
self-contained. Powering and atmospherics are a future feature (blackouts as an event, for instance).

## Adding things

- **A new ailment**: add a subtype of `/datum/patient_case` in `patient_cases.dm`. Fill in `name`, `diagnosis`,
  `difficulty` (1-3), `symptoms`, `history`, `arrival_modes`, then `apply()` (inflict it), `is_resolved()` (when it is
  cured, must be FALSE straight after `apply()`) and optionally `worsen()`. The unit tests check the basics for every case.
- **A new hospital event**: add a subtype of `/datum/hospital_event` in `hospital_events.dm` with a `name`, `weight`,
  `min_staff`, `announcement` and a `start_event()` (`run` is a reserved word in DM).
- **A new supply**: add a subtype of `/datum/hospital_supply` in `hospital_terminal.dm`.
- **A new room or furniture**: edit `hospital.py` and regenerate.

## Building, running and testing (macOS or Linux, needs Docker)

BYOND has no macOS build, so everything runs in a Linux container. `tools/medstation_dev.sh`:

    tools/medstation_dev.sh image     # build the dev image (BYOND, rust-g, dreamluau). Once.
    tools/medstation_dev.sh tgui      # build the UI bundle. Once, and after tgui changes.
    tools/medstation_dev.sh compile   # compile the game (about 8 minutes)
    tools/medstation_dev.sh run       # start the server on port 1337 (about 2 minutes to boot)
    tools/medstation_dev.sh status    # ask the running server about itself
    tools/medstation_dev.sh test      # compile with the CI defines (about 7 minutes) and run the MedStation unit tests
    tools/medstation_dev.sh test-run  # re-run those tests without recompiling
    tools/medstation_dev.sh stop

Join with a BYOND 516 client at `<host>:1337`. Compiling rewrites some tracked files under `icons/map_icons/`;
don't commit those.

## Credits

- Base: Monkestation 2.0, tgstation. See `README.md`.
- Ambulance sprite: cut from the cars sheet in https://github.com/Monkestation/crimson-grid, see
  `monkestation/code/modules/medstation/icons/README.md`.

## Ideas queue (from research on Baystation12, ColonialMarines, Goonstation)

Reimplement from the ideas, don't copy Goonstation code (its licence is non-commercial share-alike).

1. Chemical-effect flags (painkiller, stabiliser, antibiotic...) and staged overdoses with side effects.
2. Pain and shock stages, so untreated injuries visibly collapse a patient.
3. Pulse and circulation (hypovolemia, arterial bleeding, arrest, CPR).
4. Richer per-limb scans (triage tags are done).
5. An ailment layer with explicit cure flags and "suggested remedy" on scans.
6. A surgeon error model (sedation, skill).
7. Organ scarring after repair, germ levels and post-op infection.
8. Splints and bone jostling when moving a fracture.
9. A drivable ambulance for field calls.
