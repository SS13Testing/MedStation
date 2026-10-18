/// How long after the round starts before the first patient arrives
#define PATIENT_FIRST_DELAY (45 SECONDS)
/// How long a patient who is cured stays around before they are discharged
#define PATIENT_DISCHARGE_DELAY (20 SECONDS)
/// Chance that the next arrival is an ambulance (if the bay is free), otherwise somebody walks in
#define PATIENT_AMBULANCE_CHANCE 40
/// How long the ambulance waits in the bay after unloading
#define AMBULANCE_STAY_TIME (3 MINUTES)
/// A walk-in that has not reached a chair after this long is simply placed on one
#define WALKIN_SEAT_TIMEOUT (60 SECONDS)
/// Hospital levels: [name, minimum reputation, payout multiplier]. The index into this list is the level.
GLOBAL_LIST_INIT(hospital_levels, list(
	list("Failing clinic", -9999, 0.75),
	list("Local clinic", -10, 1),
	list("Community hospital", 10, 1.1),
	list("Regional hospital", 40, 1.25),
	list("Teaching hospital", 100, 1.4),
	list("Centre of excellence", 200, 1.6),
))
/// The level a new hospital starts at (index into hospital_levels)
#define HOSPITAL_START_LEVEL 2

/// Hospital events: first one after this long, then one every so often
#define EVENT_FIRST_DELAY (12 MINUTES)
#define EVENT_MIN_GAP (10 MINUTES)
#define EVENT_MAX_GAP (20 MINUTES)
/// Credits for tagging a patient with the right triage colour
#define TRIAGE_BONUS 50
/// Credits the medical budget starts the round with
#define HOSPITAL_STARTING_FUNDS 800

GLOBAL_LIST_EMPTY(patient_spawn_points)

/// Where patients get unloaded from the ambulance (behind its rear doors). Place a few of these.
/obj/effect/landmark/patient_spawn
	name = "patient spawn"

/obj/effect/landmark/patient_spawn/Initialize(mapload)
	. = ..()
	GLOB.patient_spawn_points += src

/obj/effect/landmark/patient_spawn/Destroy()
	GLOB.patient_spawn_points -= src
	return ..()

/**
 * The patient director replaces the storyteller: it sends ambulances and walk-ins to the hospital, scales the rate
 * with how many medical staff are on the station, makes untreated patients worse over time and keeps score.
 */
SUBSYSTEM_DEF(patient_director)
	name = "Patient Director"
	wait = 10 SECONDS
	flags = SS_KEEP_TIMING
	runlevels = RUNLEVEL_GAME

	/// Set to FALSE to stop new patients arriving (admins)
	var/enabled = TRUE
	/// Active patients, as /datum/patient_record
	var/list/datum/patient_record/active = list()
	/// When the next arrival is due. Set on the first fire of the round.
	var/next_patient_time
	/// Patients cured and sent home
	var/treated = 0
	/// Patients that died in our care
	var/deceased = 0
	/// Walk-ins that gave up waiting and left
	var/walked_out = 0
	/// Hospital reputation. Goes up for cured patients, down (faster) for deaths.
	var/reputation = 0
	/// Weighted list of case types
	var/list/case_weights
	/// Hospital event types and the instances we roll from
	var/list/event_weights
	/// When the next hospital event is due
	var/next_event_time
	/// While this is in the future, patients arrive faster (rush hour)
	var/rush_until = 0
	/// Index into GLOB.hospital_levels. Moves with reputation.
	var/level = HOSPITAL_START_LEVEL
	/// Per case name: list("treated" = n, "died" = n, "left" = n), for the shift report
	var/list/case_stats = list()

/datum/controller/subsystem/patient_director/Initialize()
	case_weights = list()
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		if(case.weight > 0)
			case_weights[case_type] = case
	event_weights = list()
	for(var/event_type in subtypesof(/datum/hospital_event))
		var/datum/hospital_event/event = new event_type()
		if(event.name)
			event_weights[event_type] = event
	return SS_INIT_SUCCESS

/datum/controller/subsystem/patient_director/stat_entry(msg)
	return ..("[length(active)] active | [treated] treated | [deceased] died | [walked_out] left | rep [reputation]")

/datum/controller/subsystem/patient_director/fire(resumed)
	if(isnull(next_patient_time))
		next_patient_time = world.time + PATIENT_FIRST_DELAY
		SSeconomy.get_dep_account(ACCOUNT_MED)?.adjust_money(HOSPITAL_STARTING_FUNDS, "Hospital opening grant")
	for(var/datum/patient_record/record as anything in active.Copy())
		record.process_record(src)
	if(!enabled)
		return
	if(isnull(next_event_time))
		next_event_time = world.time + EVENT_FIRST_DELAY
	if(world.time >= next_event_time)
		var/event_staff = count_staff()
		if(event_staff)
			run_event(null, event_staff)
		next_event_time = world.time + rand(EVENT_MIN_GAP, EVENT_MAX_GAP)
	if(world.time < next_patient_time)
		return
	var/staff = count_staff()
	var/room = max_patients(staff) - length(active)
	if(!staff || room <= 0)
		return
	var/arrived = FALSE
	if(room >= 1 && !ambulance_present() && prob(PATIENT_AMBULANCE_CHANCE))
		arrived = launch_ambulance(staff, room)
	if(!arrived)
		arrived = !!spawn_patient(staff = staff, arrival_mode = PATIENT_ARRIVE_WALKIN)
	next_patient_time = world.time + (arrived ? patient_interval(staff) : 15 SECONDS)

/// Living players currently working a medical job.
/datum/controller/subsystem/patient_director/proc/get_staff()
	. = list()
	for(var/mob/living/player as anything in GLOB.alive_player_list)
		if(player.stat != CONSCIOUS || !player.client)
			continue
		if(player.mind?.assigned_role?.departments_bitflags & DEPARTMENT_BITFLAG_MEDICAL)
			. += player

/datum/controller/subsystem/patient_director/proc/count_staff()
	return length(get_staff())

/datum/controller/subsystem/patient_director/proc/max_patients(staff)
	return min(2 + staff * 2 + max(0, level - HOSPITAL_START_LEVEL), 18)

/datum/controller/subsystem/patient_director/proc/level_name()
	return GLOB.hospital_levels[level][1]

/// Payout multiplier for the current level.
/datum/controller/subsystem/patient_director/proc/payout_multiplier()
	return GLOB.hospital_levels[level][3]

/// Moves the hospital up or down a level to match its reputation, and tells the staff.
/datum/controller/subsystem/patient_director/proc/update_level()
	var/new_level = 1
	for(var/i in 1 to length(GLOB.hospital_levels))
		if(reputation >= GLOB.hospital_levels[i][2])
			new_level = i
	if(new_level == level)
		return
	var/went_up = new_level > level
	level = new_level
	if(went_up)
		dispatch("<b>The hospital has been upgraded to: [level_name()].</b> Expect a bigger caseload, rarer and harder cases, and better payouts.")
	else
		dispatch("<b>The hospital's standing has dropped to: [level_name()].</b> Funding and patient numbers will suffer until it recovers.")

/// Records how a case went for the shift report.
/datum/controller/subsystem/patient_director/proc/record_stat(datum/patient_case/case, outcome)
	var/list/stats = case_stats[case.name]
	if(!stats)
		stats = list("treated" = 0, "died" = 0, "left" = 0)
		case_stats[case.name] = stats
	stats[outcome]++

/datum/controller/subsystem/patient_director/proc/patient_interval(staff)
	var/interval = max(30 SECONDS, rand(90, 180) SECONDS / sqrt(staff))
	if(world.time < rush_until)
		interval *= 0.4
	return interval

/// Runs a hospital event (a specific type, or a random one that this much staff can cope with).
/datum/controller/subsystem/patient_director/proc/run_event(event_type, staff)
	if(!event_type)
		var/list/candidates = list()
		for(var/type in event_weights)
			var/datum/hospital_event/candidate = event_weights[type]
			if(candidate.min_staff <= staff)
				candidates[type] = candidate.weight
		if(!length(candidates))
			return null
		event_type = pick_weight(candidates)
	var/datum/hospital_event/event = event_weights[event_type] || new event_type()
	if(event.announcement)
		dispatch("<b>[event.announcement]</b>")
	event.start_event(src, staff)
	return event

/// Sends a message to all medical staff.
/datum/controller/subsystem/patient_director/proc/dispatch(message)
	for(var/mob/living/staff as anything in get_staff())
		to_chat(staff, "<span class='notice'><b>Hospital dispatch:</b> [message]</span>")

/// Picks a case that can arrive the given way and that this much staff can cope with.
/datum/controller/subsystem/patient_director/proc/pick_case(staff = 1, arrival_mode)
	var/list/candidates = list()
	for(var/case_type in case_weights)
		var/datum/patient_case/case = case_weights[case_type]
		if(case.min_staff > staff || case.get_min_level() > level)
			continue
		if(arrival_mode && !(arrival_mode in case.arrival_modes))
			continue
		candidates[case_type] = case.weight
	if(!length(candidates))
		return /datum/patient_case/flu
	return pick_weight(candidates)

// ------------------------------------------------------------------ ambulance

/datum/controller/subsystem/patient_director/proc/ambulance_present()
	for(var/obj/effect/landmark/ambulance_park/park as anything in GLOB.ambulance_park_points)
		if(locate(/obj/structure/medstation_ambulance) in get_turf(park))
			return TRUE
	return FALSE

/// Free unloading spots behind the ambulance.
/datum/controller/subsystem/patient_director/proc/free_offload_turfs()
	. = list()
	for(var/obj/effect/landmark/patient_spawn/point as anything in GLOB.patient_spawn_points)
		var/turf/point_turf = get_turf(point)
		if(point_turf && !(locate(/obj/structure/bed/medical) in point_turf) && !(locate(/mob/living) in point_turf))
			. += point_turf

/// Sends an ambulance to the bay with 1-3 patients. Returns FALSE if there was no free parking or unloading space.
/datum/controller/subsystem/patient_director/proc/launch_ambulance(staff, room = 3, count)
	var/list/parks = list()
	for(var/obj/effect/landmark/ambulance_park/park as anything in GLOB.ambulance_park_points)
		parks += get_turf(park)
	if(!length(parks) || !length(free_offload_turfs()))
		return FALSE
	if(!count)
		count = 1
		if(staff >= 2)
			count += rand(0, min(2, staff - 1))
	count = clamp(count, 1, min(room, length(free_offload_turfs())))
	var/obj/structure/medstation_ambulance/ambulance = new(pick(parks))
	ambulance.drive_in()
	dispatch("An ambulance is pulling into the bay with [count] patient[count > 1 ? "s" : ""].")
	addtimer(CALLBACK(src, PROC_REF(unload_ambulance), ambulance, count, staff), 4 SECONDS)
	return TRUE

/datum/controller/subsystem/patient_director/proc/unload_ambulance(obj/structure/medstation_ambulance/ambulance, count, staff)
	if(QDELETED(ambulance))
		return
	ambulance.visible_message(span_notice("The rear doors of [ambulance] swing open."))
	for(var/i in 1 to count)
		var/list/free = free_offload_turfs()
		if(!length(free))
			break
		spawn_patient(null, pick(free), staff, PATIENT_ARRIVE_AMBULANCE)
	addtimer(CALLBACK(ambulance, TYPE_PROC_REF(/obj/structure/medstation_ambulance, drive_off)), AMBULANCE_STAY_TIME)

// ------------------------------------------------------------------ patients

/// A free chair in the same room as `near`.
/datum/controller/subsystem/patient_director/proc/find_waiting_chair(turf/near)
	var/area/room = get_area(near)
	var/list/chairs = list()
	for(var/turf/room_turf as anything in room.get_turfs_from_all_zlevels())
		for(var/obj/structure/chair/chair in room_turf)
			if(!length(chair.buckled_mobs))
				chairs += chair
	if(length(chairs))
		return pick(chairs)

/**
 * Brings in a patient. Ambulance patients appear on a stretcher at `where` (an unloading spot); walk-ins appear at the
 * waiting room door and go and sit down. Returns the record, or null if there was nowhere to put them.
 */
/datum/controller/subsystem/patient_director/proc/spawn_patient(case_type, turf/where, staff = 1, arrival_mode = PATIENT_ARRIVE_AMBULANCE)
	var/turf/arrival = where
	if(!arrival)
		if(arrival_mode == PATIENT_ARRIVE_WALKIN)
			var/obj/effect/landmark/patient_walkin/door = length(GLOB.patient_walkin_points) ? pick(GLOB.patient_walkin_points) : null
			arrival = get_turf(door)
		else
			arrival = pick_n_take_offload()
	if(!arrival)
		return null
	case_type ||= pick_case(staff, arrival_mode)
	var/datum/patient_case/case = new case_type()

	var/mob/living/carbon/human/patient = new(arrival)
	randomize_human(patient)
	patient.equip_to_slot_or_del(new /obj/item/clothing/under/color/random(patient), ITEM_SLOT_ICLOTHING)
	patient.equip_to_slot_or_del(new /obj/item/clothing/shoes/sneakers/random(patient), ITEM_SLOT_FEET)

	var/datum/patient_record/record = new(patient, case, arrival_mode)
	if(arrival_mode == PATIENT_ARRIVE_WALKIN)
		var/obj/structure/chair/chair = find_waiting_chair(arrival)
		if(chair)
			record.chair_ref = WEAKREF(chair)
			walk_to(patient, chair, 0, 3)
		record.patience_until = world.time + case.get_patience()
	else
		var/obj/structure/bed/medical/emergency/stretcher = new(arrival)
		stretcher.buckle_mob(patient, force = TRUE)
	case.apply(patient)
	patient.updatehealth()

	active += record
	var/obj/item/paper/chart = record.make_chart()
	if(!patient.put_in_hands(chart))
		chart.forceMove(arrival)

	if(arrival_mode == PATIENT_ARRIVE_WALKIN)
		playsound(arrival, 'sound/machines/ding_short.ogg', 40, FALSE)
		dispatch("A patient has walked into the waiting room: [record.triage_label()], [case.name].")
	else
		dispatch("[record.triage_label()] patient off the ambulance: [case.name].")
	return record

/// A free unloading spot, or null.
/datum/controller/subsystem/patient_director/proc/pick_n_take_offload()
	var/list/free = free_offload_turfs()
	if(length(free))
		return pick(free)

/// Called by a record when it ends, whatever the outcome.
/datum/controller/subsystem/patient_director/proc/finish(datum/patient_record/record, outcome)
	active -= record
	var/datum/patient_case/case = record.case
	switch(outcome)
		if(PATIENT_OUTCOME_TREATED)
			treated++
			record_stat(case, "treated")
			reputation += case.difficulty
			var/datum/bank_account/department/medical = SSeconomy.get_dep_account(ACCOUNT_MED)
			var/payout = round(case.get_payout() * payout_multiplier())
			medical?.adjust_money(payout, "Patient discharged: [case.name]")
			dispatch("[record.patient_name] has been discharged. Diagnosis: [case.diagnosis]. (+[payout] credits)")
			if(record.tag_level == case.difficulty)
				reputation++
				medical?.adjust_money(TRIAGE_BONUS, "Correct triage: [case.name]")
				dispatch("Good triage on [record.patient_name]: +1 reputation, +[TRIAGE_BONUS] credits.")
		if(PATIENT_OUTCOME_DIED)
			deceased++
			record_stat(case, "died")
			reputation -= case.difficulty * 2
			dispatch("[record.patient_name] has died. Diagnosis: [case.diagnosis]. Reputation falls.")
		if(PATIENT_OUTCOME_LEFT)
			walked_out++
			record_stat(case, "left")
			reputation -= case.difficulty
			dispatch("[record.patient_name] got tired of waiting and left without being seen. Reputation falls.")
	update_level()

/// The hospital's page in the round end report.
/datum/controller/subsystem/patient_director/proc/shift_report()
	var/list/parts = list("<div class='panel stationborder'><span class='header'>Hospital shift report</span><br>")
	parts += "Final rating: <b>[level_name()]</b> (reputation [reputation])<br>"
	parts += "Patients treated: <b>[treated]</b> | lost: <b>[deceased]</b> | left without being seen: <b>[walked_out]</b><br>"
	parts += "Medical budget at close: <b>[SSeconomy.get_dep_account(ACCOUNT_MED)?.account_balance || 0]</b> credits<br>"
	if(length(case_stats))
		parts += "<br><table><tr><th>Case</th><th>Treated</th><th>Died</th><th>Left</th></tr>"
		for(var/case_name in case_stats)
			var/list/stats = case_stats[case_name]
			parts += "<tr><td>[case_name]</td><td>[stats["treated"]]</td><td>[stats["died"]]</td><td>[stats["left"]]</td></tr>"
		parts += "</table>"
	else
		parts += "<i>No patients were seen this shift.</i>"
	parts += "</div>"
	return parts.Join()

/// A member of staff tagged a patient (see triage.dm).
/datum/controller/subsystem/patient_director/proc/note_tag(mob/living/carbon/human/patient, level)
	for(var/datum/patient_record/record as anything in active)
		if(record.patient_ref?.resolve() == patient)
			record.tag_level = level
			return

/// Short human readable summary for the staff.
/datum/controller/subsystem/patient_director/proc/get_status_text()
	var/list/lines = list("<b>Hospital status</b>")
	lines += "Rating: [level_name()] (reputation [reputation])"
	lines += "Patients in the hospital: [length(active)]"
	lines += "Treated: [treated] | Lost: [deceased] | Left unseen: [walked_out] | Reputation: [reputation]"
	lines += "Medical budget: [SSeconomy.get_dep_account(ACCOUNT_MED)?.account_balance || 0] credits"
	for(var/datum/patient_record/record as anything in active)
		lines += "- [record.patient_name] ([record.arrival_mode]): [record.triage_label()][isnull(record.tag_level) ? "" : " | tagged [triage_level_name(record.tag_level)]"]"
	return lines.Join("<br>")

/// One patient in the hospital.
/datum/patient_record
	var/datum/weakref/patient_ref
	var/datum/patient_case/case
	var/patient_name = "Unknown"
	/// PATIENT_ARRIVE_*
	var/arrival_mode
	/// When the patient starts getting worse if they are not in stasis
	var/deadline
	/// Set once the patient is cured: when to send them home
	var/discharge_at
	/// Walk-ins: the chair they are heading for / sitting in
	var/datum/weakref/chair_ref
	/// Walk-ins: they leave if still in the waiting room at this time
	var/patience_until
	/// Walk-ins: when they appeared (for the seat timeout)
	var/arrived_at
	/// TRIAGE_* colour a member of staff tied to the patient, if any
	var/tag_level
	/// Walk-ins: has a member of staff taken them out of the waiting room yet?
	var/admitted = FALSE

/datum/patient_record/New(mob/living/carbon/human/patient, datum/patient_case/case, arrival_mode)
	patient_ref = WEAKREF(patient)
	src.case = case
	src.arrival_mode = arrival_mode
	patient_name = patient.real_name
	arrived_at = world.time
	deadline = world.time + case.get_deadline()

/datum/patient_record/proc/triage_label()
	switch(case.difficulty)
		if(1)
			return "<font color='green'>minor</font>"
		if(2)
			return "<font color='orange'>serious</font>"
	return "<font color='red'>CRITICAL</font>"

/// The paper the patient arrives holding.
/datum/patient_record/proc/make_chart()
	var/obj/item/paper/chart = new()
	chart.name = "intake chart: [patient_name]"
	var/list/lines = list("<b>INTAKE CHART</b>", "Patient: [patient_name]", "Arrived: [station_time_timestamp()] ([arrival_mode])",
		"Triage level: [triage_label()]", "<br><b>Notes from the crew:</b>")
	for(var/line in case.history)
		lines += "- [line]"
	lines += "<br><i>No diagnosis recorded. Scan the patient.</i>"
	chart.add_raw_text(lines.Join("<br>"))
	chart.update_appearance()
	return chart

/datum/patient_record/proc/process_record(datum/controller/subsystem/patient_director/director)
	var/mob/living/carbon/human/patient = patient_ref?.resolve()
	if(QDELETED(patient))
		director.active -= src // body destroyed (gibbed, deleted): nothing to score
		return
	if(patient.stat == DEAD)
		director.finish(src, PATIENT_OUTCOME_DIED)
		return
	if(discharge_at)
		if(world.time >= discharge_at)
			discharge(patient, director)
		return
	if(arrival_mode == PATIENT_ARRIVE_WALKIN && !admitted && !process_walkin(patient, director))
		return
	if(case.is_resolved(patient))
		discharge_at = world.time + PATIENT_DISCHARGE_DELAY
		patient.SetUnconscious(0)
		to_chat(patient, span_notice("You feel much better."))
		patient.say("I think I'm feeling a lot better now, thank you.")
		return
	if(world.time > deadline && !HAS_TRAIT(patient, TRAIT_STASIS))
		case.worsen(patient)
		patient.updatehealth()
	if(patient.stat == CONSCIOUS && prob(25))
		patient.say(pick(case.symptoms))

/// Walk-in behaviour: find the chair, sit, wait, give up. Returns FALSE if the patient left.
/datum/patient_record/proc/process_walkin(mob/living/carbon/human/patient, datum/controller/subsystem/patient_director/director)
	if(!istype(get_area(patient), /area/station/medical/hospital/lobby))
		admitted = TRUE // staff moved them somewhere else: they are being looked after
		return TRUE
	var/obj/structure/chair/chair = chair_ref?.resolve()
	if(chair && !QDELETED(chair) && !patient.buckled && patient.stat == CONSCIOUS)
		if(get_dist(patient, chair) <= 1 || world.time > arrived_at + WALKIN_SEAT_TIMEOUT)
			if(!length(chair.buckled_mobs))
				patient.forceMove(get_turf(chair))
				chair.buckle_mob(patient, force = TRUE)
		else
			walk_to(patient, chair, 0, 3)
	if(world.time >= patience_until && patient.stat == CONSCIOUS)
		patient.say("I can't wait any longer. I'm leaving!")
		patient.visible_message(span_notice("[patient] gets up and storms out."))
		director.finish(src, PATIENT_OUTCOME_LEFT)
		vanish(patient)
		return FALSE
	return TRUE

/datum/patient_record/proc/discharge(mob/living/carbon/human/patient, datum/controller/subsystem/patient_director/director)
	patient.visible_message(span_notice("[patient] gets up, thanks the staff and heads home."))
	director.finish(src, PATIENT_OUTCOME_TREATED)
	vanish(patient)

/// Fades the patient out and removes them.
/datum/patient_record/proc/vanish(mob/living/carbon/human/patient)
	patient.buckled?.unbuckle_mob(patient, force = TRUE)
	animate(patient, alpha = 0, time = 1 SECONDS)
	QDEL_IN(patient, 1 SECONDS)

// ------------------------------------------------------------------ player / admin interface

/mob/living/carbon/human/verb/hospital_status()
	set name = "Hospital Status"
	set category = "IC"
	to_chat(src, SSpatient_director.get_status_text())

ADMIN_VERB(spawn_patient, R_ADMIN|R_FUN, FALSE, "Spawn Patient", "Bring a patient into the hospital. Pick a case or leave it random, and how they arrive.", ADMIN_CATEGORY_FUN)
	var/list/choices = list("Random" = null)
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = case_type
		choices[initial(case.name)] = case_type
	var/choice = tgui_input_list(user, "Which case?", "Spawn Patient", choices)
	if(!choice)
		return
	var/mode = tgui_input_list(user, "How do they arrive?", "Spawn Patient", list(PATIENT_ARRIVE_AMBULANCE, PATIENT_ARRIVE_WALKIN))
	if(!mode)
		return
	if(!SSpatient_director.spawn_patient(choices[choice], null, max(1, SSpatient_director.count_staff()), mode))
		to_chat(user, span_warning("There is nowhere to put them (no free unloading spot / waiting room door)."))

ADMIN_VERB(send_ambulance, R_ADMIN|R_FUN, FALSE, "Send Ambulance", "Send an ambulance with patients to the bay now.", ADMIN_CATEGORY_FUN)
	if(!SSpatient_director.launch_ambulance(max(1, SSpatient_director.count_staff())))
		to_chat(user, span_warning("The bay is full or the map has no ambulance parking."))

ADMIN_VERB(trigger_hospital_event, R_ADMIN|R_FUN, FALSE, "Trigger Hospital Event", "Run a hospital event (mass casualty, outbreak, rush hour) now.", ADMIN_CATEGORY_FUN)
	var/list/choices = list()
	for(var/event_type in subtypesof(/datum/hospital_event))
		var/datum/hospital_event/event = event_type
		if(initial(event.name))
			choices[initial(event.name)] = event_type
	var/choice = tgui_input_list(user, "Which event?", "Trigger Hospital Event", choices)
	if(!choice)
		return
	SSpatient_director.run_event(choices[choice], max(1, SSpatient_director.count_staff()))

ADMIN_VERB(toggle_patient_director, R_ADMIN|R_FUN, FALSE, "Toggle Patient Director", "Pause or resume new patients arriving.", ADMIN_CATEGORY_FUN)
	SSpatient_director.enabled = !SSpatient_director.enabled
	message_admins("[key_name_admin(user)] [SSpatient_director.enabled ? "resumed" : "paused"] the patient director.")

#undef PATIENT_FIRST_DELAY
#undef PATIENT_DISCHARGE_DELAY
#undef PATIENT_AMBULANCE_CHANCE
#undef AMBULANCE_STAY_TIME
#undef WALKIN_SEAT_TIMEOUT
#undef HOSPITAL_STARTING_FUNDS
#undef TRIAGE_BONUS
#undef HOSPITAL_START_LEVEL
#undef EVENT_FIRST_DELAY
#undef EVENT_MIN_GAP
#undef EVENT_MAX_GAP
