/// How long after the round starts before the first patient arrives
#define PATIENT_FIRST_DELAY (90 SECONDS)
/// The first few patients are a training period: more time on their clocks and longer gaps between arrivals
#define TRAINING_PATIENTS 5
#define TRAINING_DEADLINE_MULTIPLIER 1.5
#define TRAINING_INTERVAL_MULTIPLIER 1.3
/// A lone medic gets longer gaps between patients
#define SOLO_INTERVAL_MULTIPLIER 1.4
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
	list("Community hospital", 6, 1.1),
	list("Regional hospital", 25, 1.25),
	list("Teaching hospital", 60, 1.4),
	list("Centre of excellence", 120, 1.6),
))
/// The level a new hospital starts at (index into hospital_levels)
#define HOSPITAL_START_LEVEL 2

/// Hospital events: first one after this long, then one every so often
#define EVENT_FIRST_DELAY (12 MINUTES)
#define EVENT_MIN_GAP (10 MINUTES)
#define EVENT_MAX_GAP (20 MINUTES)
/// Chance that a patient is allergic to a medicine, and that the chart says so when they are
#define ALLERGY_CHANCE 30
#define ALLERGY_KNOWN_CHANCE 85
/// How long a dead patient's body stays around before the funeral service collects it
#define BODY_COLLECTION_TIME (8 MINUTES)
/// Ambulance calls: how many can wait at once, how long they wait for an answer, how far away patients are
#define MAX_PENDING_CALLS 2
#define CALL_WAIT_TIME (4 MINUTES)
#define CALL_TRAVEL_MIN (40 SECONDS)
#define CALL_TRAVEL_MAX (90 SECONDS)
/// Credits for keeping a contagious patient in the isolation lab until they are cured
#define QUARANTINE_BONUS 50
/// A death or a bad allergic reaction costs the hospital compensation: this fraction of the case's payout, or a flat fee
#define DEATH_COMPENSATION_FRACTION 0.5
#define ALLERGY_COMPENSATION 50
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
	/// Patients that reacted badly to a medicine they were allergic to
	var/allergic_reactions = 0
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
	/// Set once the first few patients are over (see TRAINING_PATIENTS)
	var/training_done = FALSE
	/// Index into GLOB.hospital_levels. Moves with reputation.
	var/level = HOSPITAL_START_LEVEL
	/// The field scene being answered right now (the ambulance is on its way there, at it, or coming back), if any
	var/datum/field_scene/active_scene
	/// Ambulance calls waiting for somebody to answer them (/datum/ambulance_call)
	var/list/datum/ambulance_call/pending_calls = list()
	/// While this is in the future the ambulance is out on a call
	var/ambulance_away_until = 0
	/// Ambulance calls nobody answered in time
	var/missed_calls = 0
	/// Case types the staff have seen at least once, for the case library
	var/list/discovered = list()
	/// Per case name: list("treated" = n, "died" = n, "left" = n), for the shift report
	var/list/case_stats = list()

/datum/controller/subsystem/patient_director/Initialize()
	case_weights = list()
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		if(case.weight > 0)
			case_weights[case_type] = case
	RegisterSignal(SSdcs, COMSIG_GLOB_JOB_AFTER_SPAWN, PROC_REF(on_job_spawn))
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
	expire_calls()
	process_scene()
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
	if(room >= 1 && !ambulance_busy() && length(pending_calls) < MAX_PENDING_CALLS && prob(PATIENT_AMBULANCE_CHANCE))
		arrived = paramedic_on_duty() ? !!post_call(staff, room, null, pick_scene_type()) : launch_ambulance(staff, room)
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
	discovered[case.type] = TRUE
	var/list/stats = case_stats[case.name]
	if(!stats)
		stats = list("treated" = 0, "died" = 0, "left" = 0)
		case_stats[case.name] = stats
	stats[outcome]++

/// Multiplier on how long a patient's clock lasts: generous during the training period.
/datum/controller/subsystem/patient_director/proc/deadline_multiplier()
	return training_done ? 1 : TRAINING_DEADLINE_MULTIPLIER

/datum/controller/subsystem/patient_director/proc/patient_interval(staff)
	var/interval = max(30 SECONDS, rand(90, 180) SECONDS / sqrt(staff))
	if(staff <= 1)
		interval *= SOLO_INTERVAL_MULTIPLIER
	if(!training_done)
		interval *= TRAINING_INTERVAL_MULTIPLIER
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
/datum/controller/subsystem/patient_director/proc/launch_ambulance(staff, room = 3, count, list/case_types, datum/ambulance_call/emergency)
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
	addtimer(CALLBACK(src, PROC_REF(unload_ambulance), ambulance, count, staff, case_types, emergency), 4 SECONDS)
	return TRUE

/datum/controller/subsystem/patient_director/proc/unload_ambulance(obj/structure/medstation_ambulance/ambulance, count, staff, list/case_types, datum/ambulance_call/emergency)
	if(QDELETED(ambulance))
		return
	ambulance.visible_message(span_notice("The rear doors of [ambulance] swing open."))
	for(var/i in 1 to count)
		var/list/free = free_offload_turfs()
		if(!length(free))
			break
		var/datum/patient_record/record = spawn_patient(length(case_types) >= i ? case_types[i] : null, pick(free), staff, PATIENT_ARRIVE_AMBULANCE)
		if(record && emergency) // the clock started when the call came in
			record.deadline = max(world.time + 30 SECONDS, record.deadline - (world.time - emergency.posted_at))
	addtimer(CALLBACK(ambulance, TYPE_PROC_REF(/obj/structure/medstation_ambulance, drive_off)), AMBULANCE_STAY_TIME)

// ------------------------------------------------------------------ ambulance calls

/// The docking port of the scene being answered, if there is one.
/datum/controller/subsystem/patient_director/proc/get_scene_dock()
	return active_scene?.dock

/// Is the ambulance parked in the bay or out on a call?
/datum/controller/subsystem/patient_director/proc/ambulance_busy()
	return ambulance_present() || world.time < ambulance_away_until || !!active_scene || ambulance_away_from_home()

/// A living paramedic is on duty, so ambulance arrivals become calls somebody has to answer.
/datum/controller/subsystem/patient_director/proc/paramedic_on_duty()
	for(var/mob/living/staff_member as anything in get_staff())
		if(staff_member.mind?.assigned_role?.title == JOB_PARAMEDIC)
			return TRUE
	return FALSE

/datum/controller/subsystem/patient_director/proc/ambulance_status()
	if(active_scene)
		return active_scene.departed ? "The ambulance is out at [active_scene.template.location_text]." : "A call is being answered: the ambulance is ready to drive out to [active_scene.template.location_text]."
	if(ambulance_present())
		return "The ambulance is in the bay."
	if(world.time < ambulance_away_until)
		return "The ambulance is out on a call, back in about [max(0, round((ambulance_away_until - world.time) / (1 SECONDS)))] seconds."
	return "The ambulance is free."

/// Puts a call on the board: 1-3 patients somewhere on the station waiting for the ambulance.
/datum/controller/subsystem/patient_director/proc/post_call(staff, room = 3, list/case_types, scene_type)
	var/datum/medstation_scene/scene_definition = scene_type ? new scene_type() : null
	if(scene_definition && !length(case_types))
		var/scene_count = clamp(rand(scene_definition.min_patients, scene_definition.max_patients), 1, max(1, min(room, staff + 1, 3)))
		case_types = list()
		for(var/i in 1 to scene_count)
			case_types += pick_weight(scene_definition.cases)
	if(!length(case_types))
		var/count = 1
		if(staff >= 2)
			count += rand(0, min(2, staff - 1))
		count = clamp(count, 1, max(1, min(room, 3)))
		case_types = list()
		for(var/i in 1 to count)
			case_types += pick_case(staff, PATIENT_ARRIVE_AMBULANCE)
	var/static/list/locations = list(
		"a transit ring corridor", "the hydroponics deck", "the cargo hangar", "a crew quarters block",
		"the observation deck", "the engineering annex", "the docking arm", "the promenade",
	)
	var/datum/ambulance_call/emergency = new(scene_definition ? scene_definition.location_text : pick(locations), case_types, CALL_WAIT_TIME, rand(CALL_TRAVEL_MIN, CALL_TRAVEL_MAX), scene_type)
	pending_calls += emergency
	dispatch("<b>AMBULANCE CALL</b>: [emergency.label()]. Answer it from the dispatch console[scene_type ? ", then take the ambulance out" : ""].")
	return emergency

/// Calls nobody answered in time are lost.
/datum/controller/subsystem/patient_director/proc/expire_calls()
	for(var/datum/ambulance_call/emergency as anything in pending_calls.Copy())
		if(world.time < emergency.expires_at)
			continue
		pending_calls -= emergency
		missed_calls++
		reputation -= emergency.urgency()
		dispatch("The call at [emergency.location] went unanswered. The patients were taken elsewhere. Reputation falls.")
		update_level()

/// Sends the ambulance to a call. The patients come back on it after the travel time. Returns FALSE if it can't go.
/datum/controller/subsystem/patient_director/proc/dispatch_call(datum/ambulance_call/emergency, mob/user)
	if(!(emergency in pending_calls) || ambulance_busy())
		return FALSE
	if(emergency.scene_type)
		if(!start_scene(emergency))
			return FALSE
		pending_calls -= emergency
		dispatch("[user ? "[user.real_name] is" : "The staff are"] answering the call at [emergency.location]. The scene is ready: take the ambulance out (the console is in the cab).")
		return TRUE
	pending_calls -= emergency
	ambulance_away_until = world.time + emergency.travel_time + 20 SECONDS
	dispatch("[user ? "[user.real_name] has sent" : "The staff have sent"] the ambulance to [emergency.location]. It will be back in about [round(emergency.travel_time / (1 SECONDS))] seconds.")
	addtimer(CALLBACK(src, PROC_REF(ambulance_returns), emergency), emergency.travel_time)
	return TRUE

/datum/controller/subsystem/patient_director/proc/ambulance_returns(datum/ambulance_call/emergency)
	var/staff = max(1, count_staff())
	if(!launch_ambulance(staff, length(emergency.case_types), length(emergency.case_types), emergency.case_types, emergency))
		// no space in the bay right now: try again shortly
		addtimer(CALLBACK(src, PROC_REF(ambulance_returns), emergency), 10 SECONDS)

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
	else if(arrival_mode != PATIENT_ARRIVE_FIELD)
		var/obj/structure/bed/medical/emergency/stretcher = new(arrival)
		stretcher.buckle_mob(patient, force = TRUE)
		record.stretcher_ref = WEAKREF(stretcher)
	case.apply(patient)
	patient.updatehealth()
	// a case must never start out cured (a wound failing to take, say): hurt them again until it holds
	for(var/attempt in 1 to 5)
		if(!case.is_resolved(patient))
			break
		case.apply(patient)
		patient.updatehealth()
	if(arrival_mode == PATIENT_ARRIVE_FIELD)
		patient.set_resting(TRUE) // lying where they were hurt
	patient.updatehealth()

	active += record
	var/obj/item/paper/chart = record.make_chart()
	if(!patient.put_in_hands(chart))
		chart.forceMove(arrival)

	if(arrival_mode == PATIENT_ARRIVE_WALKIN)
		playsound(arrival, 'sound/machines/ding_short.ogg', 40, FALSE)
		dispatch("A patient has walked into the waiting room: [record.triage_label()], [case.name].")
	else if(arrival_mode == PATIENT_ARRIVE_AMBULANCE)
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
	if(!training_done && treated + deceased + walked_out >= TRAINING_PATIENTS)
		training_done = TRUE
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
			if(case.infectious && record.isolated)
				reputation++
				medical?.adjust_money(QUARANTINE_BONUS, "Good infection control: [case.name]")
				dispatch("Good infection control on [record.patient_name]: +1 reputation, +[QUARANTINE_BONUS] credits.")
			if(record.tag_level == case.difficulty)
				reputation++
				medical?.adjust_money(TRIAGE_BONUS, "Correct triage: [case.name]")
				dispatch("Good triage on [record.patient_name]: +1 reputation, +[TRIAGE_BONUS] credits.")
		if(PATIENT_OUTCOME_DIED)
			deceased++
			record_stat(case, "died")
			reputation -= case.difficulty * 2
			var/compensation = round(case.get_payout() * DEATH_COMPENSATION_FRACTION)
			SSeconomy.get_dep_account(ACCOUNT_MED)?.adjust_money(-compensation, "Compensation: [case.name]")
			dispatch("[record.patient_name] has died. Diagnosis: [case.diagnosis]. Reputation falls and the family is owed [compensation] credits.")
		if(PATIENT_OUTCOME_ABANDONED)
			deceased++
			record_stat(case, "died")
			reputation -= case.difficulty * 2
			var/abandoned_compensation = round(case.get_payout() * DEATH_COMPENSATION_FRACTION)
			SSeconomy.get_dep_account(ACCOUNT_MED)?.adjust_money(-abandoned_compensation, "Compensation: [case.name]")
			dispatch("[record.patient_name] was left behind at the scene and is lost. Diagnosis: [case.diagnosis]. Reputation falls and the family is owed [abandoned_compensation] credits.")
		if(PATIENT_OUTCOME_LEFT)
			walked_out++
			record_stat(case, "left")
			reputation -= case.difficulty
			dispatch("[record.patient_name] got tired of waiting and left without being seen. Reputation falls.")
	update_level()

/// The case library: every kind of case the staff have handled, with diagnosis and treatment.
/datum/controller/subsystem/patient_director/proc/get_library_text()
	var/list/lines = list("<b>Case library</b>")
	var/unseen = 0
	for(var/case_type in case_weights)
		if(!discovered[case_type])
			unseen++
			continue
		var/datum/patient_case/case = case_weights[case_type]
		lines += "<br><b>[case.name]</b> ([case.difficulty == 1 ? "minor" : (case.difficulty == 2 ? "serious" : "critical")])"
		lines += "Diagnosis: [case.diagnosis]"
		lines += "Treatment: [case.treatment]"
	if(unseen)
		lines += "<br><i>[unseen] kind[unseen == 1 ? "" : "s"] of patient you have not seen yet. Treat them (or lose them) to add them here.</i>"
	return lines.Join("<br>")

/// The hospital's page in the round end report.
/datum/controller/subsystem/patient_director/proc/shift_report()
	var/list/parts = list("<div class='panel stationborder'><span class='header'>Hospital shift report</span><br>")
	parts += "Final rating: <b>[level_name()]</b> (reputation [reputation])<br>"
	parts += "Patients treated: <b>[treated]</b> | lost: <b>[deceased]</b> | left without being seen: <b>[walked_out]</b><br>"
	parts += "Ambulance calls missed: <b>[missed_calls]</b><br>"
	parts += "Allergic reactions to treatment: <b>[allergic_reactions]</b><br>"
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
	lines += "Patients in the hospital: [length(active)] | Ambulance calls waiting: [length(pending_calls)] | [ambulance_status()]"
	lines += "Treated: [treated] | Lost: [deceased] | Left unseen: [walked_out] | Missed calls: [missed_calls] | Allergic reactions: [allergic_reactions] | Reputation: [reputation]"
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
	/// Ambulance patients: the stretcher they arrived on
	var/datum/weakref/stretcher_ref
	/// Walk-ins: the chair they are heading for / sitting in
	var/datum/weakref/chair_ref
	/// Walk-ins: they leave if still in the waiting room at this time
	var/patience_until
	/// Walk-ins: when they appeared (for the seat timeout)
	var/arrived_at
	/// A medicine this patient is allergic to (reagent type), or null. Giving it triggers anaphylaxis.
	var/datum/reagent/allergy
	/// Does the intake chart say so? Usually, but not always.
	var/allergy_known = FALSE
	/// Has the reaction happened already?
	var/reacted = FALSE
	/// Contagious patients: were they kept in the isolation lab?
	var/isolated = FALSE
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
	deadline = world.time + case.get_deadline() * SSpatient_director.deadline_multiplier()
	if(prob(ALLERGY_CHANCE))
		var/static/list/possible_allergies = list(
			/datum/reagent/medicine/c2/libital, /datum/reagent/medicine/c2/lenturi, /datum/reagent/medicine/c2/aiuri,
			/datum/reagent/medicine/c2/multiver, /datum/reagent/medicine/c2/convermol, /datum/reagent/medicine/salbutamol,
			/datum/reagent/medicine/mannitol, /datum/reagent/medicine/oculine,
		)
		allergy = pick(possible_allergies)
		allergy_known = prob(ALLERGY_KNOWN_CHANCE)

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
	if(case.infectious)
		lines += "<br><b>Nurse's note: feverish and coughing, may be contagious. Keep away from the other patients.</b>"
	lines += "<br>Known allergies: [allergy && allergy_known ? "<b>[initial(allergy.name)]</b>" : "none reported"]"
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
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(collect_patient_body), WEAKREF(patient)), BODY_COLLECTION_TIME)
		return
	if(case.infectious && istype(get_area(patient), /area/station/medical/hospital/virology))
		isolated = TRUE
	if(discharge_at)
		if(world.time >= discharge_at)
			discharge(patient, director)
		return
	if(arrival_mode == PATIENT_ARRIVE_WALKIN && !admitted && !process_walkin(patient, director))
		return
	if(allergy && !reacted && patient.reagents?.has_reagent(allergy))
		react(patient, SSpatient_director)
	if(case.is_resolved(patient) && !(locate(/datum/disease/anaphylaxis) in patient.diseases))
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

/// The patient was given something they are allergic to.
/datum/patient_record/proc/react(mob/living/carbon/human/patient, datum/controller/subsystem/patient_director/director)
	reacted = TRUE
	director.allergic_reactions++
	director.reputation--
	SSeconomy.get_dep_account(ACCOUNT_MED)?.adjust_money(-ALLERGY_COMPENSATION, "Allergic reaction: [patient_name]")
	patient.visible_message(span_danger("[patient] breaks out in hives and starts wheezing!"))
	to_chat(patient, span_userdanger("Your skin itches and your throat is closing up!"))
	patient.ForceContractDisease(new /datum/disease/anaphylaxis(), make_copy = FALSE)
	director.dispatch("[patient_name] is having an allergic reaction to [initial(allergy.name)]! Epinephrine, fast!")
	director.update_level()

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
	var/obj/structure/bed/medical/emergency/stretcher = stretcher_ref?.resolve()
	if(stretcher && patient.buckled == stretcher)
		QDEL_IN(stretcher, 2 SECONDS) // the ambulance crew take their stretcher back
	patient.buckled?.unbuckle_mob(patient, force = TRUE)
	animate(patient, alpha = 0, time = 1 SECONDS)
	QDEL_IN(patient, 1 SECONDS)

/// The funeral service collects a dead patient's body (unless they have been revived since).
/proc/collect_patient_body(datum/weakref/body_ref)
	var/mob/living/carbon/human/body = body_ref?.resolve()
	if(QDELETED(body) || body.stat != DEAD)
		return
	body.visible_message(span_notice("The funeral service collects [body]."))
	body.buckled?.unbuckle_mob(body, force = TRUE)
	qdel(body)

// ------------------------------------------------------------------ player / admin interface

/mob/living/carbon/human/verb/case_library()
	set name = "Case Library"
	set category = "IC"
	to_chat(src, boxed_message(SSpatient_director.get_library_text()))

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
#undef DEATH_COMPENSATION_FRACTION
#undef ALLERGY_COMPENSATION
#undef QUARANTINE_BONUS
#undef TRAINING_PATIENTS
#undef TRAINING_DEADLINE_MULTIPLIER
#undef TRAINING_INTERVAL_MULTIPLIER
#undef SOLO_INTERVAL_MULTIPLIER
#undef MAX_PENDING_CALLS
#undef CALL_WAIT_TIME
#undef CALL_TRAVEL_MIN
#undef CALL_TRAVEL_MAX
#undef BODY_COLLECTION_TIME
#undef ALLERGY_CHANCE
#undef ALLERGY_KNOWN_CHANCE
#undef HOSPITAL_START_LEVEL
#undef EVENT_FIRST_DELAY
#undef EVENT_MIN_GAP
#undef EVENT_MAX_GAP
