#ifdef UNIT_TESTS
/// Every patient case must inflict something, not be cured straight away, and carry intake chart text.
/datum/unit_test/patient_cases

/datum/unit_test/patient_cases/Run()
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		// wounds are random: do it a number of times so a rare "already cured" can't hide
		for(var/attempt in 1 to 15)
			var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent)
			case.apply(patient)
			patient.updatehealth()
			TEST_ASSERT(!case.is_resolved(patient), "[case_type] is already resolved straight after apply() (attempt [attempt])")
		var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent)
		case.apply(patient)
		patient.updatehealth()
		TEST_ASSERT(length(case.symptoms) && length(case.history), "[case_type] has no symptoms/history for the chart")
		TEST_ASSERT(case.diagnosis != "Unknown", "[case_type] has no diagnosis")
		TEST_ASSERT(length(case.treatment) > 30 && case.treatment != /datum/patient_case::treatment, "[case_type] has no treatment hint for the case library")
		case.worsen(patient)

/// The director can bring a patient in, score a cure and score a death.
/datum/unit_test/patient_director

/datum/unit_test/patient_director/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	var/treated_before = director.treated
	var/deceased_before = director.deceased

	var/datum/patient_record/record = director.spawn_patient(/datum/patient_case/flu, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(record, "spawn_patient returned no record")
	var/mob/living/carbon/human/patient = record.patient_ref.resolve()
	TEST_ASSERT_NOTNULL(patient, "record has no patient")
	TEST_ASSERT(patient.buckled, "patient should arrive buckled to a stretcher")
	TEST_ASSERT(length(patient.diseases), "flu patient should be sick")
	TEST_ASSERT(record in director.active, "record should be active")

	// cure them: should schedule a discharge, then discharge on the next pass
	for(var/datum/disease/disease as anything in patient.diseases.Copy())
		disease.cure(add_resistance = FALSE)
	patient.setToxLoss(0)
	record.process_record(director)
	TEST_ASSERT_NOTNULL(record.discharge_at, "cured patient should be queued for discharge")
	record.discharge_at = world.time
	record.process_record(director)
	TEST_ASSERT_EQUAL(director.treated, treated_before + 1, "discharge should count as treated")
	TEST_ASSERT(!(record in director.active), "discharged record should leave the active list")

	// a walk-in: no stretcher, arrives at the door and heads for a chair
	var/datum/patient_record/walkin = director.spawn_patient(/datum/patient_case/flu, run_loc_floor_bottom_left, 1, PATIENT_ARRIVE_WALKIN)
	TEST_ASSERT_NOTNULL(walkin, "walk-in spawn_patient returned no record")
	TEST_ASSERT_EQUAL(walkin.arrival_mode, PATIENT_ARRIVE_WALKIN, "walk-in record has the wrong arrival mode")
	var/mob/living/carbon/human/walker = walkin.patient_ref.resolve()
	TEST_ASSERT(!walker.buckled, "walk-in should not arrive on a stretcher")
	TEST_ASSERT(walkin.patience_until > world.time, "walk-in should have a patience timer")
	director.active -= walkin

	// triage: tagging works, the colour is recorded, and the right colour earns a bonus on discharge
	var/datum/patient_record/tagged = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/tagged_patient = tagged.patient_ref.resolve()
	var/mob/living/carbon/human/medic = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/triage_tagger/tagger = allocate(/obj/item/triage_tagger)
	TEST_ASSERT_EQUAL(tagger.level, TRIAGE_GREEN, "tagger should start on green")
	tagger.interact_with_atom(tagged_patient, medic)
	TEST_ASSERT_EQUAL(tagged.tag_level, TRIAGE_GREEN, "the record should remember the tag colour")
	TEST_ASSERT_NOTNULL(tagged_patient.GetComponent(/datum/component/triage_tag), "patient should carry a triage tag")
	tagger.attack_self(medic)
	TEST_ASSERT_EQUAL(tagger.level, TRIAGE_YELLOW, "attack_self should cycle the colour")
	var/reputation_before = director.reputation
	tagged.discharge_at = world.time
	// burns are difficulty 1 = green, so the green tag was right
	tagged.process_record(director)
	TEST_ASSERT(director.reputation >= reputation_before + 1 + tagged.case.difficulty, "correct triage should add a reputation bonus")

	// an allergy: giving the wrong medicine sets off anaphylaxis (which blocks discharge until cured)
	var/datum/patient_record/allergic = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/allergic_patient = allergic.patient_ref.resolve()
	allergic.allergy = /datum/reagent/medicine/c2/libital
	var/reactions_before = director.allergic_reactions
	allergic_patient.reagents.add_reagent(/datum/reagent/medicine/c2/libital, 5)
	allergic.process_record(director)
	TEST_ASSERT_EQUAL(director.allergic_reactions, reactions_before + 1, "the allergic reaction should be counted")
	TEST_ASSERT(locate(/datum/disease/anaphylaxis) in allergic_patient.diseases, "an allergic reaction should give anaphylaxis")
	TEST_ASSERT(allergic.reacted, "the record should remember the reaction")
	director.active -= allergic

	// a death
	var/datum/patient_record/doomed = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	TEST_ASSERT_NOTNULL(doomed, "second spawn_patient returned no record")
	var/mob/living/carbon/human/body = doomed.patient_ref.resolve()
	body.death()
	doomed.process_record(director)
	TEST_ASSERT_EQUAL(director.deceased, deceased_before + 1, "death should count as deceased")
	// the funeral service collects the body, but not someone who has been revived
	var/datum/patient_record/revived = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/revived_body = revived.patient_ref.resolve()
	collect_patient_body(WEAKREF(revived_body))
	TEST_ASSERT(!QDELETED(revived_body), "a living patient must not be collected")
	director.active -= revived
	collect_patient_body(WEAKREF(body))
	TEST_ASSERT(QDELETED(body), "a dead patient's body should be collected")
	director.active.Cut()

/// An ambulance run sets up the vehicle and its blockers, and picks cases that can arrive that way.
/datum/unit_test/medstation_ambulance

/datum/unit_test/medstation_ambulance/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	TEST_ASSERT(!director.ambulance_present(), "an ambulance is already parked at the start of the test")
	TEST_ASSERT(director.launch_ambulance(1, 1), "launch_ambulance failed (no parking or no unloading spot)")
	TEST_ASSERT(director.ambulance_present(), "no ambulance after launch_ambulance")
	var/obj/structure/medstation_ambulance/ambulance
	for(var/obj/effect/landmark/ambulance_park/park as anything in GLOB.ambulance_park_points)
		ambulance = locate() in get_turf(park)
	TEST_ASSERT_NOTNULL(ambulance, "could not find the ambulance")
	TEST_ASSERT_EQUAL(length(ambulance.blockers), 8, "ambulance should block the 8 tiles around its centre")
	qdel(ambulance)
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		TEST_ASSERT(length(case.arrival_modes), "[case_type] can't arrive any way")
	// the picker honours arrival modes: chest wounds only come by ambulance, flu only walks in
	for(var/i in 1 to 30)
		TEST_ASSERT(director.pick_case(5, PATIENT_ARRIVE_WALKIN) != /datum/patient_case/chest_wound, "chest wound picked as a walk-in")
		TEST_ASSERT(director.pick_case(5, PATIENT_ARRIVE_AMBULANCE) != /datum/patient_case/flu, "flu picked as an ambulance patient")

/// Reputation moves the hospital between levels, levels gate cases and change payouts, and the report renders.
/datum/unit_test/medstation_levels

/datum/unit_test/medstation_levels/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_level = director.level
	var/old_reputation = director.reputation
	var/old_stats = director.case_stats
	director.case_stats = list()

	director.reputation = -50
	director.update_level()
	TEST_ASSERT_EQUAL(director.level_name(), "Failing clinic", "very low reputation should be a failing clinic")
	TEST_ASSERT(director.payout_multiplier() < 1, "a failing clinic should be paid less")
	director.reputation = 0
	director.update_level()
	TEST_ASSERT_EQUAL(director.level_name(), "Local clinic", "reputation 0 should be a local clinic")
	director.reputation = 250
	director.update_level()
	TEST_ASSERT_EQUAL(director.level_name(), "Centre of excellence", "reputation 250 should be a centre of excellence")
	TEST_ASSERT(director.max_patients(1) > 4, "a better hospital should hold more patients")

	// level gating: a local clinic never gets the rare critical cases, a top hospital can
	director.reputation = 0
	director.update_level()
	for(var/i in 1 to 40)
		var/picked = director.pick_case(6)
		var/datum/patient_case/case = new picked()
		TEST_ASSERT(case.get_min_level() <= director.level, "[picked] picked below its hospital level")
	director.reputation = 250
	director.update_level()
	var/saw_rare = FALSE
	for(var/i in 1 to 400)
		if(director.pick_case(6) == /datum/patient_case/heart_attack)
			saw_rare = TRUE
	TEST_ASSERT(saw_rare, "a top hospital should eventually see heart attacks")

	// stats and the report
	director.record_stat(new /datum/patient_case/flu(), "treated")
	director.record_stat(new /datum/patient_case/flu(), "died")
	TEST_ASSERT_EQUAL(director.case_stats["Fever and cough"]["treated"], 1, "stat not recorded")
	var/report = director.shift_report()
	TEST_ASSERT(findtext(report, "Hospital shift report") && findtext(report, "Fever and cough"), "shift report is missing content")

	director.case_stats = old_stats
	director.reputation = old_reputation
	director.level = old_level

/// The timed flows really work in the real map: the ambulance arrives, unloads on a timer and leaves, a walk-in walks to a
/// chair and sits down, and a discharged patient takes their stretcher with them.
/datum/unit_test/medstation_flows

/datum/unit_test/medstation_flows/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()

	// ---- ambulance: drives in, unloads after a few seconds, leaves
	TEST_ASSERT(director.launch_ambulance(2, 3, 2), "launch_ambulance failed")
	sleep(7 SECONDS)
	var/ambulance_patients = 0
	for(var/datum/patient_record/record as anything in director.active)
		if(record.arrival_mode != PATIENT_ARRIVE_AMBULANCE)
			continue
		ambulance_patients++
		var/mob/living/carbon/human/patient = record.patient_ref.resolve()
		TEST_ASSERT_NOTNULL(patient, "an ambulance patient has no body")
		TEST_ASSERT(istype(patient.buckled, /obj/structure/bed/medical/emergency), "an ambulance patient should be on a stretcher")
	TEST_ASSERT_EQUAL(ambulance_patients, 2, "the ambulance should have unloaded 2 patients after its timer")
	var/obj/structure/medstation_ambulance/ambulance
	for(var/obj/effect/landmark/ambulance_park/park as anything in GLOB.ambulance_park_points)
		ambulance = locate() in get_turf(park)
	TEST_ASSERT_NOTNULL(ambulance, "the ambulance should still be in the bay")
	ambulance.drive_off()
	sleep(5 SECONDS)
	TEST_ASSERT(QDELETED(ambulance), "the ambulance should be gone after driving off")
	TEST_ASSERT(!director.ambulance_present(), "the bay should be empty again")

	// ---- a discharged ambulance patient takes the stretcher away
	var/datum/patient_record/leaving = director.active[1]
	var/mob/living/carbon/human/leaving_patient = leaving.patient_ref.resolve()
	var/obj/structure/bed/medical/emergency/leaving_stretcher = leaving_patient.buckled
	TEST_ASSERT_NOTNULL(leaving_stretcher, "no stretcher to remove")
	leaving.discharge(leaving_patient, director)
	sleep(4 SECONDS)
	TEST_ASSERT(QDELETED(leaving_stretcher), "the stretcher should leave with a discharged patient")
	TEST_ASSERT(QDELETED(leaving_patient), "a discharged patient should be gone")
	director.active.Cut()

	// ---- walk-in: appears at the door, walks to a chair in the waiting room and sits down
	var/datum/patient_record/walkin = director.spawn_patient(/datum/patient_case/flu, null, 1, PATIENT_ARRIVE_WALKIN)
	TEST_ASSERT_NOTNULL(walkin, "walk-in spawn failed")
	var/mob/living/carbon/human/walker = walkin.patient_ref.resolve()
	TEST_ASSERT_NOTNULL(walkin.chair_ref?.resolve(), "there was no free chair in the waiting room")
	for(var/i in 1 to 40)
		sleep(1 SECONDS)
		walkin.process_record(director)
		if(walker.buckled)
			break
	TEST_ASSERT(walker.buckled, "the walk-in never sat down")
	TEST_ASSERT(world.time - walkin.arrived_at < 55 SECONDS, "the walk-in should walk to the chair, not get placed on it after the timeout")
	qdel(walker)
	director.active.Cut()

/// The field response plumbing: the ambulance shuttle exists, every scene variant loads, and the shuttle can dock at the
/// scene and come home again.
/datum/unit_test/medstation_field

/datum/unit_test/medstation_field/Run()
	var/obj/docking_port/mobile/ambulance = SSshuttle.getShuttle("ambulance")
	TEST_ASSERT_NOTNULL(ambulance, "the ambulance shuttle was not loaded")
	var/obj/docking_port/stationary/home = SSshuttle.getDock("ambulance_home")
	TEST_ASSERT_NOTNULL(home, "the map has no ambulance_home dock")
	TEST_ASSERT_EQUAL(ambulance.get_docked(), home, "the ambulance should start docked at the hospital")
	TEST_ASSERT(length(subtypesof(/datum/medstation_scene)), "no field scenes are defined")
	for(var/scene_type in subtypesof(/datum/medstation_scene))
		var/datum/medstation_scene/definition = new scene_type()
		for(var/variant in 1 to definition.variants)
			var/where = "[definition.name] variant [variant]"
			var/datum/field_scene/scene = new(definition)
			TEST_ASSERT(scene.load(variant), "[where] failed to load")
			TEST_ASSERT_NOTNULL(scene.dock, "[where] has no dock")
			TEST_ASSERT_EQUAL(scene.dock.shuttle_id, "ambulance_scene", "[where]: the scene dock should keep its id")
			TEST_ASSERT(length(scene.patient_spots) >= 3, "[where] has fewer than 3 patient spots")
			TEST_ASSERT_EQUAL(ambulance.canDock(scene.dock), SHUTTLE_CAN_DOCK, "the ambulance can't dock at [where]")
			TEST_ASSERT_EQUAL(SSshuttle.moveShuttle("ambulance", "ambulance_scene", FALSE), DOCKING_SUCCESS, "the ambulance couldn't get to [where]")
			TEST_ASSERT_EQUAL(ambulance.get_docked(), scene.dock, "the ambulance should be docked at [where]")
			TEST_ASSERT_EQUAL(SSshuttle.moveShuttle("ambulance", "ambulance_home", FALSE), DOCKING_SUCCESS, "the ambulance couldn't come home from [where]")
			TEST_ASSERT_EQUAL(ambulance.get_docked(), home, "the ambulance should be home again after [where]")
			var/obj/docking_port/stationary/old_dock = scene.dock
			qdel(scene)
			TEST_ASSERT(!(old_dock in SSshuttle.stationary_docking_ports), "the dock of [where] was left registered after unloading")
			sleep(1 SECONDS)

/// Answering a call with a scene: the scene loads with patients lying in it, the real ambulance drives out and back, anybody
/// left behind is lost, and a scene nobody drives to is abandoned as a missed call.
/datum/unit_test/medstation_scene_calls

/datum/unit_test/medstation_scene_calls/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	director.pending_calls.Cut()
	director.active_scene = null
	director.ambulance_away_until = 0
	var/mob/living/carbon/human/dispatcher = allocate(/mob/living/carbon/human/consistent)
	var/deceased_before = director.deceased
	var/old_training = director.training_done
	director.training_done = TRUE // clocks are compared against the normal length below

	// ---- answering a scene call loads the scene with its patients lying in it
	var/datum/ambulance_call/answered = director.post_call(2, 3, list(/datum/patient_case/burns, /datum/patient_case/respiratory), /datum/medstation_scene/cargo)
	TEST_ASSERT_NOTNULL(answered.scene_type, "the call should be for a scene")
	answered.posted_at = world.time - 2 MINUTES
	TEST_ASSERT(director.dispatch_call(answered, dispatcher), "answering the call should load its scene")
	var/datum/field_scene/scene = director.active_scene
	TEST_ASSERT_NOTNULL(scene, "no scene after answering")
	TEST_ASSERT_NOTNULL(director.get_scene_dock(), "the scene has no dock")
	TEST_ASSERT(director.ambulance_busy(), "the ambulance counts as busy while a scene is active")
	var/list/field_records = list()
	for(var/datum/patient_record/record as anything in director.active)
		if(record.arrival_mode == PATIENT_ARRIVE_FIELD)
			field_records += record
	TEST_ASSERT_EQUAL(length(field_records), 2, "the scene should have both patients")
	for(var/datum/patient_record/record as anything in field_records)
		var/mob/living/carbon/human/patient = record.patient_ref.resolve()
		TEST_ASSERT_NOTNULL(patient, "a scene patient has no body")
		TEST_ASSERT(scene.contains(patient), "a scene patient should be inside the scene")
		TEST_ASSERT(patient.body_position == LYING_DOWN, "a scene patient should be lying down")
		TEST_ASSERT(record.deadline - world.time < record.case.get_deadline() - 90 SECONDS, "the scene patients' clocks should have been running since the call")

	// ---- the crew drive out, bring one patient back and drive home
	TEST_ASSERT_EQUAL(SSshuttle.moveShuttle("ambulance", "ambulance_scene", FALSE), DOCKING_SUCCESS, "couldn't drive to the scene")
	director.process_scene()
	TEST_ASSERT(scene.departed, "the scene should know the ambulance left")
	var/datum/patient_record/rescued = field_records[1]
	var/mob/living/carbon/human/rescued_patient = rescued.patient_ref.resolve()
	rescued_patient.forceMove(get_step(SSshuttle.getDock("ambulance_home"), NORTH))
	TEST_ASSERT(!scene.contains(rescued_patient), "the rescued patient should be out of the scene")
	TEST_ASSERT_EQUAL(SSshuttle.moveShuttle("ambulance", "ambulance_home", FALSE), DOCKING_SUCCESS, "couldn't drive home")
	director.process_scene()
	TEST_ASSERT_NOTNULL(scene.returned_at, "the scene should notice the ambulance is home")
	scene.returned_at = world.time - 5 MINUTES
	var/obj/docking_port/stationary/scene_dock = scene.dock
	director.process_scene()
	TEST_ASSERT_NULL(director.active_scene, "the scene should be cleared once the ambulance has been home a while")
	TEST_ASSERT_EQUAL(director.deceased, deceased_before + 1, "the patient left behind should count as lost")
	TEST_ASSERT(rescued in director.active, "the rescued patient is still a patient")
	TEST_ASSERT(!QDELETED(rescued_patient), "the rescued patient must survive the scene being cleared")
	TEST_ASSERT(!(scene_dock in SSshuttle.stationary_docking_ports), "the scene dock should be gone")
	director.active.Cut()
	qdel(rescued_patient)

	// ---- a scene nobody drives out to is abandoned as a missed call
	var/datum/ambulance_call/ignored = director.post_call(2, 3, list(/datum/patient_case/burns), /datum/medstation_scene/maintenance)
	TEST_ASSERT(director.dispatch_call(ignored, dispatcher), "answering the second call should work")
	var/missed_before = director.missed_calls
	director.active_scene.created_at = world.time - 20 MINUTES
	director.process_scene()
	TEST_ASSERT_NULL(director.active_scene, "an abandoned scene should be cleared")
	TEST_ASSERT_EQUAL(director.missed_calls, missed_before + 1, "an abandoned scene should count as a missed call")
	TEST_ASSERT(!length(director.active), "an abandoned scene's patients should be dropped")
	director.training_done = old_training

/// Ambulance calls: they go on the board, expire into lost reputation, and answering one brings the patients back already
/// closer to their deadline.
/datum/unit_test/medstation_calls

/datum/unit_test/medstation_calls/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_training = director.training_done
	director.training_done = TRUE // clocks are compared against the normal length below
	director.active.Cut()
	director.pending_calls.Cut()
	director.ambulance_away_until = 0

	// a call that nobody answers is lost
	var/datum/ambulance_call/stale = director.post_call(2, 3, list(/datum/patient_case/burns))
	TEST_ASSERT_NOTNULL(stale, "post_call returned no call")
	TEST_ASSERT(stale in director.pending_calls, "the call should be on the board")
	var/missed_before = director.missed_calls
	var/reputation_before = director.reputation
	stale.expires_at = world.time
	director.expire_calls()
	TEST_ASSERT(!(stale in director.pending_calls), "an expired call should leave the board")
	TEST_ASSERT_EQUAL(director.missed_calls, missed_before + 1, "an expired call should count as missed")
	TEST_ASSERT(director.reputation < reputation_before, "a missed call should cost reputation")

	// answering a call: the ambulance goes away, then comes back with the patients, whose clocks have been running
	var/mob/living/carbon/human/dispatcher = allocate(/mob/living/carbon/human/consistent)
	var/datum/ambulance_call/answered = director.post_call(2, 3, list(/datum/patient_case/burns, /datum/patient_case/respiratory))
	answered.travel_time = 3 SECONDS
	answered.posted_at = world.time - 2 MINUTES // it has been waiting two minutes already
	TEST_ASSERT(director.dispatch_call(answered, dispatcher), "dispatch_call should send the ambulance")
	TEST_ASSERT(!(answered in director.pending_calls), "an answered call should leave the board")
	TEST_ASSERT(director.ambulance_busy(), "the ambulance should be busy while out")
	TEST_ASSERT(!director.dispatch_call(answered, dispatcher), "a call can't be answered twice")
	sleep(9 SECONDS) // 3s away + 4s to unload + slack
	var/found = 0
	for(var/datum/patient_record/record as anything in director.active)
		if(record.arrival_mode != PATIENT_ARRIVE_AMBULANCE)
			continue
		found++
		// burns normally allow 8 minutes (respiratory 5): after two minutes of waiting they must be less than that
		TEST_ASSERT(record.deadline - world.time < record.case.get_deadline() - 90 SECONDS, "the patients' clocks should have been running since the call came in")
	TEST_ASSERT_EQUAL(found, 2, "the ambulance should have brought both patients")
	for(var/obj/structure/medstation_ambulance/ambulance in world)
		qdel(ambulance)
	director.active.Cut()
	director.ambulance_away_until = 0
	director.training_done = old_training

/// Everything a case needs to be treated (/datum/patient_case/needs) must be obtainable from the start: in the medical areas
/// (nested contents included), in a vending machine, or (for medicines) makeable by chemistry from what the dispensers hold.
/// Only spare organs may rely on the terminal's order list. Keeps the core loop playable: no case may need something the
/// hospital doesn't have.
/datum/unit_test/medstation_treatability
	/// Item and machine types in the medical areas (nested contents included), by type
	var/list/stocked = list()
	/// Reagents sitting in containers in the medical areas
	var/list/stocked_reagents = list()
	var/list/dispensable = list()
	var/list/craftable_memo = list()
	/// Item types the terminal sells. Only organs may be bought: everything else has to be there from the start.
	var/list/orderable = list()

/datum/unit_test/medstation_treatability/proc/collect_stock()
	for(var/atom/movable/thing in world)
		var/turf/where = get_turf(thing)
		if(!where || !istype(get_area(where), /area/station/medical))
			continue
		if(!isitem(thing) && !ismachinery(thing) && !isstructure(thing))
			continue
		stocked[thing.type] = TRUE
		if(thing.reagents)
			for(var/datum/reagent/reagent as anything in thing.reagents.reagent_list)
				stocked_reagents[reagent.type] = TRUE
		if(istype(thing, /obj/machinery/vending))
			var/obj/machinery/vending/vendor = thing
			for(var/datum/data/vending_product/record as anything in vendor.product_records)
				stocked[record.product_path] = TRUE
	for(var/obj/machinery/chem_dispenser/dispenser in world)
		for(var/reagent_type in dispenser.dispensable_reagents)
			dispensable[reagent_type] = TRUE
	for(var/supply_name in GLOB.hospital_supplies)
		var/datum/hospital_supply/supply = GLOB.hospital_supplies[supply_name]
		for(var/item_type in supply.contents_list)
			orderable[item_type] = TRUE

/// Can chemistry make this reagent from dispensable reagents (recursively)?
/datum/unit_test/medstation_treatability/proc/can_make(reagent_type, depth = 0)
	if(dispensable[reagent_type])
		return TRUE
	if(depth > 6)
		return FALSE
	var/key = "[reagent_type]"
	if(!isnull(craftable_memo[key]))
		return craftable_memo[key]
	craftable_memo[key] = FALSE // guards against cycles
	for(var/datum/chemical_reaction/reaction as anything in GLOB.chemical_reactions_list_product_index[reagent_type])
		var/ok = TRUE
		for(var/needed in reaction.required_reagents)
			if(!can_make(needed, depth + 1))
				ok = FALSE
				break
		if(ok)
			for(var/catalyst in reaction.required_catalysts)
				if(!can_make(catalyst, depth + 1))
					ok = FALSE
					break
		if(ok)
			craftable_memo[key] = TRUE
			return TRUE
	return FALSE

/datum/unit_test/medstation_treatability/proc/obtainable(wanted)
	if(ispath(wanted, /datum/reagent))
		if(stocked_reagents[wanted])
			return TRUE
		for(var/stocked_reagent in stocked_reagents)
			if(ispath(stocked_reagent, wanted))
				return TRUE
		return can_make(wanted)
	for(var/stocked_type in stocked)
		if(ispath(stocked_type, wanted))
			return TRUE
	if(ispath(wanted, /obj/item/organ)) // spare organs are a purchase, not a starting supply
		for(var/orderable_type in orderable)
			if(ispath(orderable_type, wanted))
				return TRUE
	return FALSE

/datum/unit_test/medstation_treatability/Run()
	collect_stock()
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		TEST_ASSERT(length(case.needs), "[case_type] doesn't say what it needs to be treated")
		for(var/list/group as anything in case.needs)
			var/found = FALSE
			for(var/wanted in group)
				// obtainable from the start, and usable at the rank this case is sent to
				if(obtainable(wanted) && career_rank_for_type(wanted) <= case.required_rank)
					found = TRUE
					break
			TEST_ASSERT(found, "[case_type] (rank [case.required_rank]) needs one of [json_encode(group)] but the hospital can't provide any of them at that rank")

/// Chemical cases arrive contaminated, can't be discharged until they have been washed, and a wash clears it.
/datum/unit_test/medstation_decon

/datum/unit_test/medstation_decon/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	var/datum/patient_record/record = director.spawn_patient(/datum/patient_case/poisoning, run_loc_floor_bottom_left, 1)
	TEST_ASSERT_NOTNULL(record, "couldn't spawn a poisoning patient")
	var/mob/living/carbon/human/patient = record.patient_ref.resolve()
	TEST_ASSERT(is_contaminated(patient), "a chemical case should arrive contaminated")
	var/chart_text = ""
	for(var/datum/paper_input/input as anything in record.make_chart().raw_text_inputs)
		chart_text += input.raw_text
	TEST_ASSERT(findtext(chart_text, "Decontaminate"), "the chart should say to decontaminate the patient")
	// otherwise cured, but still covered in residue: not discharged, and the residue keeps hurting them
	patient.reagents.clear_reagents()
	patient.adjustToxLoss(-patient.getToxLoss(), forced = TRUE)
	patient.updatehealth()
	record.process_record(director)
	TEST_ASSERT(isnull(record.discharge_at), "a contaminated patient must not be queued for discharge")
	TEST_ASSERT(patient.getToxLoss() > 0, "contamination should keep hurting the patient")
	// a wash (what a shower does) clears it
	patient.wash(CLEAN_RAD | CLEAN_WASH)
	TEST_ASSERT(!is_contaminated(patient), "washing should clear the contamination")
	patient.adjustToxLoss(-patient.getToxLoss(), forced = TRUE)
	patient.updatehealth()
	record.process_record(director)
	TEST_ASSERT_NOTNULL(record.discharge_at, "once washed and cured the patient should be queued for discharge (tox [patient.getToxLoss()], resolved [record.case.is_resolved(patient)])")
	// cases that aren't chemical are not contaminated
	var/datum/patient_record/clean = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	TEST_ASSERT(!is_contaminated(clean.patient_ref.resolve()), "a burns patient is not contaminated")
	// the chemical cases all need a shower, and the hospital has them
	for(var/case_type in list(/datum/patient_case/poisoning, /datum/patient_case/respiratory, /datum/patient_case/eye_injury, /datum/patient_case/radiation))
		var/datum/patient_case/case = new case_type()
		TEST_ASSERT(case.contaminated, "[case_type] should be a contaminated case")
		TEST_ASSERT(findtext(case.treatment, "shower"), "[case_type]'s treatment hint should mention the shower")
	director.active.Cut()

/// Contagious patients: the chart warns about them and keeping them in the isolation lab earns a bonus.
/datum/unit_test/medstation_quarantine

/datum/unit_test/medstation_quarantine/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	var/datum/patient_record/sick = director.spawn_patient(/datum/patient_case/flu, run_loc_floor_bottom_left, 1)
	TEST_ASSERT_NOTNULL(sick, "couldn't spawn a flu patient")
	var/obj/item/paper/chart = sick.make_chart()
	var/chart_text = ""
	for(var/datum/paper_input/input as anything in chart.raw_text_inputs)
		chart_text += input.raw_text
	TEST_ASSERT(findtext(chart_text, "contagious"), "a contagious patient's chart should say so")
	var/datum/patient_record/healthy = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/healthy_chart_text = ""
	for(var/datum/paper_input/input as anything in healthy.make_chart().raw_text_inputs)
		healthy_chart_text += input.raw_text
	TEST_ASSERT(!findtext(healthy_chart_text, "contagious"), "a burns patient isn't contagious")
	// cured without isolation vs cured in isolation
	var/reputation_before = director.reputation
	sick.discharge(sick.patient_ref.resolve(), director)
	var/plain_gain = director.reputation - reputation_before
	var/datum/patient_record/isolated = director.spawn_patient(/datum/patient_case/flu, run_loc_floor_bottom_left, 1)
	isolated.isolated = TRUE
	reputation_before = director.reputation
	isolated.discharge(isolated.patient_ref.resolve(), director)
	TEST_ASSERT_EQUAL(director.reputation - reputation_before, plain_gain + 1, "isolating a contagious patient should earn a reputation bonus")
	director.active.Cut()

/// Money sinks: deaths and allergic reactions cost compensation, and the marketing campaign buys a rush hour.
/datum/unit_test/medstation_economy

/datum/unit_test/medstation_economy/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/datum/bank_account/department/medical = SSeconomy.get_dep_account(ACCOUNT_MED)
	TEST_ASSERT_NOTNULL(medical, "no medical budget account")
	medical.adjust_money(2000)
	director.active.Cut()
	// a death costs compensation
	var/datum/patient_record/doomed = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/balance_before = medical.account_balance
	var/mob/living/carbon/human/body = doomed.patient_ref.resolve()
	body.death()
	doomed.process_record(director)
	TEST_ASSERT(medical.account_balance < balance_before, "a death should cost the hospital compensation")
	// an allergic reaction costs a fee
	var/datum/patient_record/allergic = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	allergic.allergy = /datum/reagent/medicine/c2/libital
	balance_before = medical.account_balance
	allergic.patient_ref.resolve().reagents.add_reagent(/datum/reagent/medicine/c2/libital, 5)
	allergic.process_record(director)
	TEST_ASSERT(medical.account_balance < balance_before, "an allergic reaction should cost a fee")
	// the marketing campaign is a service that starts a rush hour
	var/datum/hospital_supply/marketing = GLOB.hospital_supplies["Marketing campaign (rush hour for 10 minutes)"]
	TEST_ASSERT_NOTNULL(marketing, "the marketing campaign isn't on the terminal")
	director.rush_until = 0
	marketing.fulfil(director)
	TEST_ASSERT(director.rush_until > world.time, "the marketing campaign should start a rush hour")
	director.rush_until = 0
	// vending machine refills can be bought
	TEST_ASSERT_NOTNULL(GLOB.hospital_supplies["NanoMed Plus refill (tools and dressings)"], "no NanoMed Plus refill on the terminal")
	director.active.Cut()

/// The first few patients are easier (longer clocks, longer gaps); a lone medic gets longer gaps; the rare critical cases wait.
/datum/unit_test/medstation_solo

/datum/unit_test/medstation_solo/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_training = director.training_done
	director.training_done = FALSE
	TEST_ASSERT(director.deadline_multiplier() > 1, "the training period should give patients more time")
	var/datum/patient_case/burns = new /datum/patient_case/burns()
	var/datum/mob_for_record = allocate(/mob/living/carbon/human/consistent)
	var/datum/patient_record/training_record = new(mob_for_record, burns, PATIENT_ARRIVE_AMBULANCE)
	TEST_ASSERT(training_record.deadline - world.time > burns.get_deadline(), "a training patient's clock should be longer than normal")
	director.training_done = TRUE
	TEST_ASSERT_EQUAL(director.deadline_multiplier(), 1, "after training the clocks are normal length")
	var/datum/patient_record/normal_record = new(mob_for_record, burns, PATIENT_ARRIVE_AMBULANCE)
	TEST_ASSERT(normal_record.deadline - world.time <= burns.get_deadline() + 1, "after training a patient's clock is normal length")
	// a lone medic waits longer between patients than a pair does
	var/solo_total = 0
	var/pair_total = 0
	for(var/i in 1 to 200)
		solo_total += director.patient_interval(1)
		pair_total += director.patient_interval(2)
	TEST_ASSERT(solo_total > pair_total * 1.3, "a lone medic should get noticeably longer gaps than two medics")
	// the rare critical cases need a better hospital than the starting one
	for(var/case_type in list(/datum/patient_case/heart_attack, /datum/patient_case/liver_failure, /datum/patient_case/parasite))
		var/datum/patient_case/rare = new case_type()
		TEST_ASSERT(rare.get_min_level() > 3, "[case_type] shouldn't turn up before a regional hospital")
	director.training_done = old_training

/// The welcome guide exists and covers the main points.
/datum/unit_test/medstation_guide

/datum/unit_test/medstation_guide/Run()
	var/text = hospital_guide_text()
	for(var/keyword in list("ambulance", "walk-ins", "intake chart", "Triage", "hospital terminal", "Rating", "shuttle", "Careers"))
		TEST_ASSERT(findtext(text, keyword), "the hospital guide doesn't mention [keyword]")

/// The case library only shows cases the staff have seen.
/datum/unit_test/medstation_library

/datum/unit_test/medstation_library/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_discovered = director.discovered
	director.discovered = list()
	var/text = director.get_library_text()
	TEST_ASSERT(!findtext(text, "Appendicitis"), "an unseen case shouldn't be in the library")
	TEST_ASSERT(findtext(text, "not seen yet"), "the library should say how many cases are still unseen")
	director.record_stat(new /datum/patient_case/appendicitis(), "treated")
	text = director.get_library_text()
	TEST_ASSERT(findtext(text, "organ manipulation"), "a seen case should show its treatment")
	director.case_stats = list()
	director.discovered = old_discovered

/// Every hospital event runs and brings patients (or an ambulance, or a rush).
/datum/unit_test/medstation_events

/datum/unit_test/medstation_events/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	TEST_ASSERT(length(director.event_weights), "no hospital events registered")
	for(var/event_type in director.event_weights)
		director.active.Cut()
		var/datum/hospital_event/event = director.run_event(event_type, 3)
		TEST_ASSERT_NOTNULL(event, "[event_type] did not run")
	// rush hour shortens the gap between patients
	director.rush_until = 0
	var/normal_interval_max = 180 SECONDS
	director.rush_until = world.time + 5 MINUTES
	TEST_ASSERT(director.patient_interval(3) < normal_interval_max, "rush hour should shorten the patient interval")
	director.rush_until = 0
	// an ambulance may be left over from the mass casualty event: remove it
	for(var/obj/structure/medstation_ambulance/ambulance in world)
		qdel(ambulance)
	director.active.Cut()

/// Everything on the hospital terminal's order list must exist and be affordable-looking.
/datum/unit_test/medstation_supplies

/datum/unit_test/medstation_supplies/Run()
	TEST_ASSERT(length(GLOB.hospital_supplies), "no hospital supplies defined")
	for(var/supply_name in GLOB.hospital_supplies)
		var/datum/hospital_supply/supply = GLOB.hospital_supplies[supply_name]
		TEST_ASSERT(supply.cost > 0, "[supply_name] has no cost")
		TEST_ASSERT(supply.immediate || length(supply.contents_list), "[supply_name] has no contents")
		var/obj/structure/closet/crate/crate = allocate(/obj/structure/closet/crate)
		for(var/item_type in supply.contents_list)
			TEST_ASSERT(ispath(item_type, /obj), "[supply_name] contains [item_type] which is not an object type")
			TEST_ASSERT(supply.contents_list[item_type] >= 1, "[supply_name] has a zero count for [item_type]")
			var/obj/made = new item_type(crate)
			TEST_ASSERT(!QDELETED(made), "[item_type] from [supply_name] deleted itself on creation")

/// The map must have what the hospital needs to run.
/datum/unit_test/medstation_map

/datum/unit_test/medstation_map/Run()
	TEST_ASSERT(length(GLOB.patient_spawn_points), "map has no /obj/effect/landmark/patient_spawn")
	TEST_ASSERT(length(GLOB.ambulance_park_points), "map has no /obj/effect/landmark/ambulance_park")
	TEST_ASSERT(length(GLOB.supply_drop_points), "map has no /obj/effect/landmark/supply_drop")
	TEST_ASSERT(length(GLOB.patient_walkin_points), "map has no /obj/effect/landmark/patient_walkin")
	TEST_ASSERT(length(SSjob.latejoin_trackers), "map has no latejoin landmarks")
	// the emergency shuttle needs somewhere to dock, or the shift can never end
	TEST_ASSERT_NOTNULL(SSshuttle.getDock("emergency_home"), "map has no emergency_home docking port")
	TEST_ASSERT_NOTNULL(SSshuttle.emergency, "no emergency shuttle was loaded")
	TEST_ASSERT_EQUAL(SSshuttle.emergency.canDock(SSshuttle.getDock("emergency_home")), SHUTTLE_CAN_DOCK, "the emergency shuttle can't dock at emergency_home")
	// Start landmarks delete themselves once the round has started (before the tests run), so read the map file.
	var/map_text = file2text("_maps/map_files/debug/medstation.dmm")
	TEST_ASSERT(length(map_text), "could not read medstation.dmm")
	// showers to decontaminate patients, and toilets and sinks for everyone
	var/shower_count = length(splittext(map_text, "/obj/machinery/shower")) - 1
	var/toilet_count = length(splittext(map_text, "/obj/structure/toilet")) - 1
	var/sink_count = length(splittext(map_text, "/obj/structure/sink")) - 1
	TEST_ASSERT(shower_count >= 3, "the hospital should have at least 3 showers (has [shower_count])")
	TEST_ASSERT(toilet_count >= 3, "the hospital should have at least 3 toilets (has [toilet_count])")
	TEST_ASSERT(sink_count >= 6, "the hospital should have at least 6 sinks (has [sink_count])")
	for(var/job_landmark in list("nurse", "basic_emt", "medical_doctor", "paramedic", "chemist", "virologist", "psychologist", "geneticist", "chief_medical_officer"))
		TEST_ASSERT(findtext(map_text, "/obj/effect/landmark/start/[job_landmark]"), "map has no [job_landmark] start landmark")

/// A long randomised run of the whole director: patients, events, ambulance calls and scenes, with random cures, deaths and
/// trips of the ambulance, then a check that nothing threw a runtime and that nothing leaked. Kept last so it can't upset the
/// other tests.
/datum/unit_test/medstation_soak

/datum/unit_test/medstation_soak/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/runtimes_before = GLOB.total_runtimes
	var/old_reputation = director.reputation
	var/old_level = director.level
	var/old_training = director.training_done
	var/mob/living/carbon/human/dispatcher = allocate(/mob/living/carbon/human/consistent)
	var/obj/docking_port/mobile/ambulance = SSshuttle.getShuttle("ambulance")
	director.staff_override = 3
	director.paramedic_override = TRUE
	director.active.Cut()
	director.pending_calls.Cut()
	director.ambulance_away_until = 0
	if(director.active_scene)
		director.end_scene(TRUE)
	var/scenes_started = 0
	var/most_active = 0
	for(var/i in 1 to 250)
		director.next_patient_time = 0
		if(i % 8 == 0)
			director.next_event_time = 0
		director.fire()
		most_active = max(most_active, length(director.active))
		for(var/datum/patient_record/record as anything in director.active.Copy())
			var/mob/living/carbon/human/patient = record.patient_ref?.resolve()
			if(QDELETED(patient))
				continue
			switch(rand(1, 24))
				if(1, 2)
					record.discharge_at = world.time // treated
				if(3)
					patient.death()
				if(4)
					record.patience_until = world.time // a walk-in loses patience
		for(var/datum/ambulance_call/emergency as anything in director.pending_calls.Copy())
			if(prob(40) && director.dispatch_call(emergency, dispatcher))
				scenes_started++
		if(director.active_scene && ambulance)
			if(!director.ambulance_away_from_home() && prob(50))
				SSshuttle.moveShuttle("ambulance", "ambulance_scene", FALSE)
			else if(director.ambulance_away_from_home() && prob(50))
				SSshuttle.moveShuttle("ambulance", "ambulance_home", FALSE)
		director.process_scene()
		if(director.active_scene && prob(15)) // fast-forward the scene's clocks
			director.active_scene.created_at -= 10 MINUTES
			if(director.active_scene.returned_at)
				director.active_scene.returned_at -= 5 MINUTES
		if(i % 25 == 0)
			sleep(2 SECONDS) // let the unloading timers and animations run

	// wrap up: get the ambulance home, clear the scene, remove everything we spawned
	if(director.active_scene)
		if(ambulance && director.ambulance_away_from_home())
			SSshuttle.moveShuttle("ambulance", "ambulance_home", FALSE)
		director.end_scene(TRUE)
	for(var/datum/patient_record/record as anything in director.active.Copy())
		var/mob/living/carbon/human/patient = record.patient_ref?.resolve()
		if(patient)
			qdel(patient)
	director.active.Cut()
	director.pending_calls.Cut()
	for(var/obj/structure/medstation_ambulance/npc_ambulance in world)
		qdel(npc_ambulance)
	director.staff_override = null
	director.paramedic_override = FALSE
	director.ambulance_away_until = 0
	director.reputation = old_reputation
	director.level = old_level
	director.training_done = old_training
	TEST_ASSERT_EQUAL(GLOB.total_runtimes, runtimes_before, "runtime errors happened during the soak run")
	TEST_ASSERT(scenes_started > 0, "the soak run never answered a scene call")
	TEST_ASSERT(most_active < 60, "patients piled up without limit ([most_active])")
	TEST_ASSERT(!director.ambulance_away_from_home(), "the ambulance should be home after the soak run")

/// Careers: XP maths, ranks, job gating and saving to disk.
/datum/unit_test/medstation_careers

/datum/unit_test/medstation_careers/Run()
	var/old_dir = SScareers.career_dir
	var/old_cache = SScareers.cache
	SScareers.career_dir = "data/medstation_test_careers"
	SScareers.cache = list()
	var/test_ckey = "zzcareertest"
	TEST_ASSERT_EQUAL(SScareers.get_xp(test_ckey), 0, "a new player has no XP")
	TEST_ASSERT_EQUAL(SScareers.rank_of_ckey(test_ckey), 0, "a new player is a Trainee")
	for(var/list/pair in list(list(0, 0), list(299, 0), list(300, 1), list(999, 1), list(1000, 2), list(2499, 2), list(2500, 3), list(99999, 3)))
		TEST_ASSERT_EQUAL(SScareers.rank_for_xp(pair[1]), pair[2], "[pair[1]] XP should be rank [pair[2]]")
	SScareers.add_xp(test_ckey, 350, "test")
	TEST_ASSERT_EQUAL(SScareers.rank_of_ckey(test_ckey), 1, "350 XP should be Qualified")
	SScareers.add_xp(test_ckey, -1000, "penalty")
	TEST_ASSERT_EQUAL(SScareers.get_xp(test_ckey), 0, "XP can't go below zero")
	SScareers.add_xp(test_ckey, 1200, "more")
	SScareers.cache = list() // forget the memory: it has to come back from the file
	TEST_ASSERT_EQUAL(SScareers.get_xp(test_ckey), 1200, "XP should be saved to disk and come back")
	TEST_ASSERT_EQUAL(SScareers.rank_of_ckey(test_ckey), 2, "1200 XP should be Senior")
	// jobs: a Senior can be a virologist but not the CMO; anyone can be a nurse or a basic EMT; a newcomer can't be a doctor
	TEST_ASSERT(SScareers.can_ckey_take_job(test_ckey, JOB_VIROLOGIST), "a Senior should be able to take Virologist")
	TEST_ASSERT(SScareers.can_ckey_take_job(test_ckey, JOB_MEDICAL_DOCTOR), "a Senior should be able to take Medical Doctor")
	TEST_ASSERT(!SScareers.can_ckey_take_job(test_ckey, JOB_CHIEF_MEDICAL_OFFICER), "a Senior shouldn't be able to take Chief Medical Officer")
	var/fresh = "zzfreshplayer"
	for(var/title in list(JOB_NURSE, JOB_BASIC_EMT))
		TEST_ASSERT(SScareers.can_ckey_take_job(fresh, title), "a newcomer should be able to take [title]")
	for(var/title in list(JOB_MEDICAL_DOCTOR, JOB_PARAMEDIC, JOB_CHEMIST, JOB_CHIEF_MEDICAL_OFFICER))
		TEST_ASSERT(!SScareers.can_ckey_take_job(fresh, title), "a newcomer shouldn't be able to take [title]")
	TEST_ASSERT(GLOB.career_job_ranks[JOB_PARAMEDIC] > GLOB.career_job_ranks[JOB_BASIC_EMT], "Paramedic should be a step above Basic EMT")
	TEST_ASSERT(GLOB.career_job_ranks[JOB_MEDICAL_DOCTOR] > GLOB.career_job_ranks[JOB_NURSE], "Medical Doctor should be a step above Nurse")
	TEST_ASSERT(GLOB.career_job_ranks[JOB_CHIEF_MEDICAL_OFFICER] == length(GLOB.career_ranks) - 1, "the CMO should need the top rank")
	var/summary = SScareers.career_summary(test_ckey)
	TEST_ASSERT(findtext(summary, "Senior") && findtext(summary, "XP"), "the career summary should show the rank and XP")
	fdel("data/medstation_test_careers/")
	SScareers.career_dir = old_dir
	SScareers.cache = old_cache

/// Locks: a Trainee can't use surgical tools, advanced medicines or the chemistry machines on patients, a Qualified rank can,
/// the CMO's hypospray needs a Chief, and unplayed mobs (patients, dummies) are unrestricted.
/datum/unit_test/medstation_locks

/datum/unit_test/medstation_locks/Run()
	var/mob/living/carbon/human/trainee = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/qualified = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/chief = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/unplayed = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent)
	SScareers.rank_override[trainee] = 0
	SScareers.rank_override[qualified] = 1
	SScareers.rank_override[chief] = 3
	var/obj/item/scalpel/scalpel = allocate(/obj/item/scalpel)
	var/obj/item/circular_saw/saw = allocate(/obj/item/circular_saw)
	var/obj/item/stack/medical/gauze/gauze = allocate(/obj/item/stack/medical/gauze)
	var/obj/item/healthanalyzer/analyzer = allocate(/obj/item/healthanalyzer)
	TEST_ASSERT(!SScareers.may_use_item(trainee, scalpel, patient), "a Trainee shouldn't be able to operate")
	TEST_ASSERT(SScareers.may_use_item(qualified, scalpel, patient), "a Qualified rank should be able to use a scalpel")
	TEST_ASSERT(!SScareers.may_use_item(qualified, saw, patient), "a Qualified rank shouldn't use the bone saw yet")
	TEST_ASSERT(SScareers.may_use_item(chief, saw, patient), "a Chief should be able to use the saw")
	TEST_ASSERT(SScareers.may_use_item(trainee, gauze, patient), "a Trainee should be able to bandage")
	TEST_ASSERT(SScareers.may_use_item(trainee, analyzer, patient), "a Trainee should be able to scan")
	TEST_ASSERT(SScareers.may_use_item(unplayed, scalpel, patient), "unplayed mobs are unrestricted")
	// only treatments on patients are locked: a scalpel on a table is nobody's business
	var/obj/structure/table/table = allocate(/obj/structure/table)
	TEST_ASSERT(SScareers.may_use_item(trainee, scalpel, table), "tools are only locked when used on patients")
	// medicines are locked by what is in them
	var/obj/item/reagent_containers/syringe/syringe = allocate(/obj/item/reagent_containers/syringe)
	syringe.reagents.add_reagent(/datum/reagent/medicine/c2/multiver, 5)
	TEST_ASSERT(!SScareers.may_use_item(trainee, syringe, patient), "a Trainee shouldn't give multiver")
	TEST_ASSERT(SScareers.may_use_item(qualified, syringe, patient), "a Qualified rank should be able to give multiver")
	var/obj/item/reagent_containers/syringe/basic_syringe = allocate(/obj/item/reagent_containers/syringe)
	basic_syringe.reagents.add_reagent(/datum/reagent/medicine/c2/libital, 5)
	TEST_ASSERT(SScareers.may_use_item(trainee, basic_syringe, patient), "a Trainee should be able to give a basic brute medicine")
	var/obj/item/reagent_containers/syringe/toxin_syringe = allocate(/obj/item/reagent_containers/syringe)
	toxin_syringe.reagents.add_reagent(/datum/reagent/toxin/formaldehyde, 5)
	TEST_ASSERT(!SScareers.may_use_item(qualified, toxin_syringe, patient), "poisons need the top ranks")
	TEST_ASSERT_EQUAL(career_rank_for_reagent(/datum/reagent/toxin/formaldehyde), 3, "poisons should need the top rank")
	TEST_ASSERT_EQUAL(career_rank_for_reagent(/datum/reagent/water), 0, "water is free for everybody")
	TEST_ASSERT_EQUAL(career_rank_for_reagent(/datum/reagent/medicine/epinephrine), 1, "epinephrine should need Qualified")
	TEST_ASSERT_EQUAL(career_rank_for_reagent(/datum/reagent/medicine/c2/libital), 0, "basic brute medicine is open to Trainees")
	// the CMO's hypospray is above the ordinary one
	TEST_ASSERT(career_lock_for_type(/obj/item/hypospray, GLOB.career_item_locks) < career_lock_for_type(/obj/item/hypospray/cmo, GLOB.career_item_locks), "the CMO hypospray should need a higher rank")
	// machines
	TEST_ASSERT_EQUAL(career_rank_for_type(/obj/machinery/chem_dispenser), 1, "the chem dispenser should need Qualified")
	TEST_ASSERT_EQUAL(career_rank_for_type(/obj/machinery/stasis), 0, "stasis beds are open to everybody")
	var/obj/machinery/chem_dispenser/dispenser = allocate(/obj/machinery/chem_dispenser)
	TEST_ASSERT(!SScareers.may_operate(trainee, dispenser), "a Trainee shouldn't run the chemistry dispenser")
	TEST_ASSERT(SScareers.may_operate(qualified, dispenser), "a Qualified rank should run the dispenser")
	SScareers.rank_override.Cut()

/// The director only sends cases that somebody on duty is qualified for, scenes included.
/datum/unit_test/medstation_rank_cases

/datum/unit_test/medstation_rank_cases/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_level = director.level
	director.level = length(GLOB.hospital_levels) // the best hospital, so levels don't hide anything
	director.staff_rank_override = 0
	for(var/i in 1 to 200)
		var/picked = director.pick_case(6)
		var/datum/patient_case/case = new picked()
		TEST_ASSERT(case.required_rank <= 0, "[picked] was picked for a staff of Trainees")
	var/saw_rank_one = FALSE
	director.staff_rank_override = 1
	for(var/i in 1 to 400)
		var/picked = director.pick_case(6)
		var/datum/patient_case/case = new picked()
		TEST_ASSERT(case.required_rank <= 1, "[picked] was picked for a staff of Qualified rank")
		if(case.required_rank == 1)
			saw_rank_one = TRUE
	TEST_ASSERT(saw_rank_one, "a Qualified staff should see rank 1 cases")
	var/saw_rank_two = FALSE
	director.staff_rank_override = 3
	for(var/i in 1 to 600)
		var/picked = director.pick_case(6)
		var/datum/patient_case/case = new picked()
		if(case.required_rank >= 2)
			saw_rank_two = TRUE
	TEST_ASSERT(saw_rank_two, "a Chief-led staff should see the hard cases")
	// scenes: even a chemical spill only hands Trainees what they can treat
	director.staff_rank_override = 0
	for(var/i in 1 to 30)
		var/datum/ambulance_call/emergency = director.post_call(3, 3, null, /datum/medstation_scene/hydroponics)
		for(var/case_type in emergency.case_types)
			var/datum/patient_case/case = new case_type()
			TEST_ASSERT(case.required_rank <= 0, "a scene call for Trainees contained [case_type]")
	director.pending_calls.Cut()
	director.staff_rank_override = null
	director.level = old_level

/// Career XP is paid out to the people who worked on a patient, and only them.
/datum/unit_test/medstation_xp_awards

/datum/unit_test/medstation_xp_awards/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	var/old_dir = SScareers.career_dir
	var/old_cache = SScareers.cache
	SScareers.career_dir = "data/medstation_test_careers"
	SScareers.cache = list()
	director.active.Cut()
	// a cured ambulance patient (difficulty 1): 40 x 1.25 for the people who worked on them twice or more
	var/datum/patient_record/cured = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	cured.note_contributor("zzxpa")
	cured.note_contributor("zzxpa")
	cured.note_contributor("zzxpb")
	cured.discharge(cured.patient_ref.resolve(), director)
	TEST_ASSERT_EQUAL(SScareers.get_xp("zzxpa"), 50, "a difficulty 1 ambulance cure is worth 50 XP")
	TEST_ASSERT_EQUAL(SScareers.get_xp("zzxpb"), 0, "touching a patient once doesn't earn XP")
	// a walk-in has no emergency bonus
	var/datum/patient_record/walkin = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1, PATIENT_ARRIVE_WALKIN)
	walkin.note_contributor("zzxpa")
	walkin.note_contributor("zzxpa")
	walkin.discharge(walkin.patient_ref.resolve(), director)
	TEST_ASSERT_EQUAL(SScareers.get_xp("zzxpa"), 90, "a walk-in cure is worth 40 XP")
	// a correct triage tag adds a bonus
	var/datum/patient_record/tagged = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	tagged.tag_level = TRIAGE_GREEN
	tagged.note_contributor("zzxpa")
	tagged.note_contributor("zzxpa")
	tagged.discharge(tagged.patient_ref.resolve(), director)
	TEST_ASSERT_EQUAL(SScareers.get_xp("zzxpa"), 150, "a correct triage tag is worth 10 more XP")
	// a patient who is lost still teaches a little
	var/datum/patient_record/lost = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	lost.note_contributor("zzxpa")
	lost.note_contributor("zzxpa")
	var/mob/living/carbon/human/body = lost.patient_ref.resolve()
	body.death()
	lost.process_record(director)
	TEST_ASSERT_EQUAL(SScareers.get_xp("zzxpa"), 160, "a lost patient is worth a little XP to those who tried")
	// the attack signal is wired up and ignores people who aren't players
	var/datum/patient_record/watched = director.spawn_patient(/datum/patient_case/burns, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/watched_patient = watched.patient_ref.resolve()
	var/obj/item/stack/medical/gauze/gauze = allocate(/obj/item/stack/medical/gauze)
	var/mob/living/carbon/human/unplayed = allocate(/mob/living/carbon/human/consistent)
	SEND_SIGNAL(watched_patient, COMSIG_ATOM_ATTACKBY, gauze, unplayed)
	TEST_ASSERT(!length(watched.contributors), "an unplayed mob shouldn't count as a contributor")
	director.active.Cut()
	fdel("data/medstation_test_careers/")
	SScareers.career_dir = old_dir
	SScareers.cache = old_cache

/// The Nurse and Basic EMT jobs exist, are unlimited, are the overflow role, and the map and config know them.
/datum/unit_test/medstation_career_jobs

/datum/unit_test/medstation_career_jobs/Run()
	for(var/title in list(JOB_NURSE, JOB_BASIC_EMT))
		var/datum/job/job = SSjob.GetJob(title)
		TEST_ASSERT_NOTNULL(job, "[title] isn't a job")
		TEST_ASSERT_EQUAL(job.total_positions, -1, "[title] should have unlimited slots")
		TEST_ASSERT(job.departments_bitflags & DEPARTMENT_BITFLAG_MEDICAL, "[title] should be a medical job")
		TEST_ASSERT(ispath(job.outfit, /datum/outfit/job), "[title] has no outfit")
	TEST_ASSERT_EQUAL(SSjob.overflow_role, /datum/job/nurse, "players without a job should start as a Nurse")
	var/job_config = file2text("config/jobconfig.toml")
	TEST_ASSERT(findtext(job_config, "\[NURSE]") && findtext(job_config, "\[BASIC_EMT]"), "jobconfig.toml doesn't list the new jobs")
	// every job in the ladder exists
	for(var/title in GLOB.career_job_ranks)
		TEST_ASSERT_NOTNULL(SSjob.GetJob(title), "the career ladder lists [title] which isn't a job")

/// Pain and shock: serious injuries and blood loss push a patient into shock; the right care pulls them back.
/datum/unit_test/medstation_shock

/datum/unit_test/medstation_shock/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	var/datum/patient_record/record = director.spawn_patient(/datum/patient_case/flu, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/patient = record.patient_ref.resolve()
	patient.reagents.clear_reagents()
	// a mild patient never goes into shock
	for(var/i in 1 to 20)
		record.process_record(director)
	TEST_ASSERT(get_shock_level(patient) < SHOCK_PALE, "a flu patient should not be in shock (level [get_shock_level(patient)])")
	// badly hurt and standing: shock builds, then they collapse
	patient.adjustBruteLoss(80, forced = TRUE)
	patient.updatehealth()
	var/datum/component/shock/shock = patient.GetComponent(/datum/component/shock)
	TEST_ASSERT_NOTNULL(shock, "the director should have given the patient a shock component")
	for(var/i in 1 to 30)
		shock.tick_shock(patient)
	TEST_ASSERT(shock.level >= SHOCK_COLLAPSE, "a badly hurt patient should be in deep shock (level [shock.level])")
	TEST_ASSERT(patient.IsUnconscious(), "deep shock should knock the patient out")
	TEST_ASSERT(patient.getOxyLoss() > 0, "deep shock should start to suffocate the patient")
	// the scanner shows vitals that reflect it
	var/list/scan = list()
	SEND_SIGNAL(patient, COMSIG_LIVING_HEALTHSCAN, scan, TRUE, null, 1, FALSE) // 1 is the verbose scan mode
	var/scan_text = scan.Join()
	TEST_ASSERT(findtext(scan_text, "DEEP SHOCK") && findtext(scan_text, "bpm"), "the advanced scan should show pulse and shock stage (got [scan_text])")
	TEST_ASSERT(shock.get_pulse(patient) > 100, "a patient in shock should have a racing pulse ([shock.get_pulse(patient)])")
	TEST_ASSERT(patient.blood_volume / BLOOD_VOLUME_NORMAL * 120 - 0.4 * shock.level < 90, "blood pressure should have dropped")
	scan.Cut()
	SEND_SIGNAL(patient, COMSIG_LIVING_HEALTHSCAN, scan, FALSE, null, 1, FALSE) // 1 is the verbose scan mode
	TEST_ASSERT(!findtext(scan.Join(), "Circulation"), "the basic scanner shouldn't name the shock stage")
	// they are not discharged while in shock
	TEST_ASSERT(isnull(record.discharge_at), "a patient in shock must not be discharged")
	// stasis freezes the level
	var/frozen = shock.level
	ADD_TRAIT(patient, TRAIT_STASIS, TRAIT_GENERIC)
	shock.tick_shock(patient)
	TEST_ASSERT_EQUAL(shock.level, frozen, "stasis should freeze shock")
	REMOVE_TRAIT(patient, TRAIT_STASIS, TRAIT_GENERIC)
	// a painkiller slows the climb compared with no treatment
	shock.level = 0
	shock.tick_shock(patient)
	var/untreated_rise = shock.level
	shock.level = 0
	patient.reagents.add_reagent(/datum/reagent/medicine/painkiller/morphine, 5)
	shock.tick_shock(patient)
	TEST_ASSERT(shock.level < untreated_rise, "a painkiller should slow shock ([shock.level] vs [untreated_rise])")
	patient.reagents.clear_reagents()
	// healed and given saline, shock drains away
	patient.adjustBruteLoss(-patient.getBruteLoss(), forced = TRUE)
	patient.adjustOxyLoss(-patient.getOxyLoss(), forced = TRUE)
	patient.updatehealth()
	shock.level = 90
	patient.reagents.add_reagent(/datum/reagent/medicine/salglu_solution, 5)
	for(var/i in 1 to 15)
		shock.tick_shock(patient)
	TEST_ASSERT(shock.level < SHOCK_STABLE, "a healed patient on saline should recover from shock (level [shock.level])")
	director.active.Cut()

/// Wound infection: open wounds can fester, which blocks discharge until antibiotics clear it.
/datum/unit_test/medstation_infection

/datum/unit_test/medstation_infection/Run()
	var/datum/controller/subsystem/patient_director/director = SSpatient_director
	director.active.Cut()
	for(var/case_type in list(/datum/patient_case/laceration, /datum/patient_case/shrapnel, /datum/patient_case/chest_wound))
		var/datum/patient_case/case = new case_type()
		TEST_ASSERT(case.open_wound, "[case_type] should be an open wound case")
	var/datum/patient_case/flu = new /datum/patient_case/flu()
	TEST_ASSERT(!flu.open_wound, "flu is not an open wound")
	var/datum/patient_record/record = director.spawn_patient(/datum/patient_case/laceration, run_loc_floor_bottom_left, 1)
	var/mob/living/carbon/human/patient = record.patient_ref.resolve()
	TEST_ASSERT(!is_infected(patient), "a fresh patient is not infected")
	// infected and otherwise fixed up: still no discharge, and the toxins build
	patient.AddComponent(/datum/component/wound_infection)
	TEST_ASSERT(is_infected(patient), "the infection should attach")
	patient.setBruteLoss(0)
	patient.blood_volume = BLOOD_VOLUME_NORMAL
	patient.updatehealth()
	var/tox_before = patient.getToxLoss()
	record.process_record(director)
	TEST_ASSERT(patient.getToxLoss() > tox_before, "an infection should poison the patient")
	TEST_ASSERT(isnull(record.discharge_at), "an infected patient must not be discharged")
	var/list/scan = list()
	SEND_SIGNAL(patient, COMSIG_LIVING_HEALTHSCAN, scan, TRUE, null, 1, FALSE) // 1 is the verbose scan mode
	TEST_ASSERT(findtext(scan.Join(), "spaceacillin"), "the advanced scan should recommend antibiotics")
	// antibiotics clear it
	patient.reagents.add_reagent(/datum/reagent/medicine/antipathogenic/spaceacillin, 5)
	record.process_record(director)
	TEST_ASSERT(!is_infected(patient), "spaceacillin should clear the infection")
	director.active.Cut()

/// The vitals monitor reads patients lying nearby.
/datum/unit_test/medstation_vitals_monitor

/datum/unit_test/medstation_vitals_monitor/Run()
	var/obj/machinery/computer/vitals_monitor/monitor = allocate(/obj/machinery/computer/vitals_monitor, run_loc_floor_bottom_left)
	TEST_ASSERT(findtext(monitor.get_readout(), "No patients"), "an empty room should read no patients")
	var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent, get_step(run_loc_floor_bottom_left, EAST))
	patient.Paralyze(10 SECONDS)
	patient.set_body_position(LYING_DOWN)
	var/text = monitor.get_readout()
	TEST_ASSERT(findtext(text, patient.real_name) && findtext(text, "bpm") && findtext(text, "BP"), "the monitor should list the lying patient's vitals (got [text])")
	patient.set_body_position(STANDING_UP)
	TEST_ASSERT(findtext(monitor.get_readout(), "No patients"), "standing people are not monitored")

/// Scene hazards hurt unprotected people at the scene, and the ambulance's gear protects against them.
/datum/unit_test/medstation_hazards

/datum/unit_test/medstation_hazards/Run()
	var/list/expected = list(/datum/medstation_scene/hydroponics = /datum/scene_hazard/fumes, /datum/medstation_scene/fire = /datum/scene_hazard/smoke,
		/datum/medstation_scene/cargo = /datum/scene_hazard/collapse)
	for(var/scene_type in expected)
		var/datum/medstation_scene/definition = new scene_type()
		TEST_ASSERT_EQUAL(definition.hazard_type, expected[scene_type], "[scene_type] has the wrong hazard")
	// the ambulance carries the gear
	var/gear_text = file2text("_maps/shuttles/ambulance_medstation.dmm")
	TEST_ASSERT(findtext(gear_text, "/obj/item/clothing/mask/gas") && findtext(gear_text, "/obj/item/clothing/head/utility/hardhat"), "the ambulance map should hold gas masks and hard hats")

	var/datum/field_scene/scene = new(new /datum/medstation_scene/hydroponics())
	TEST_ASSERT(scene.load(1), "couldn't load the hydroponics scene")
	TEST_ASSERT_NOTNULL(scene.hazard, "the scene should have a hazard")
	var/turf/spot = scene.patient_spots[1]
	var/mob/living/carbon/human/bare = allocate(/mob/living/carbon/human/consistent, spot)
	var/mob/living/carbon/human/masked = allocate(/mob/living/carbon/human/consistent, scene.patient_spots[2])
	var/obj/item/clothing/mask/gas/mask = allocate(/obj/item/clothing/mask/gas)
	masked.equip_to_slot_if_possible(mask, ITEM_SLOT_MASK)
	TEST_ASSERT(has_filtered_air(masked) && !has_filtered_air(bare), "only the masked person has filtered air")
	scene.hazard.pulse(scene)
	TEST_ASSERT(bare.getToxLoss() > 0, "fumes should poison an unmasked person")
	TEST_ASSERT_EQUAL(masked.getToxLoss(), 0, "a gas mask should protect from fumes")

	// debris: a hard hat takes most of it
	var/datum/scene_hazard/collapse/collapse = new()
	var/mob/living/carbon/human/hatted = allocate(/mob/living/carbon/human/consistent, scene.patient_spots[3])
	var/obj/item/clothing/head/utility/hardhat/hat = allocate(/obj/item/clothing/head/utility/hardhat)
	hatted.equip_to_slot_if_possible(hat, ITEM_SLOT_HEAD)
	collapse.drop(get_turf(bare))
	collapse.drop(get_turf(hatted))
	TEST_ASSERT(bare.getBruteLoss() >= collapse.bare_damage - 1, "debris should hurt a bare-headed person ([bare.getBruteLoss()])")
	TEST_ASSERT(hatted.getBruteLoss() < bare.getBruteLoss(), "a hard hat should reduce debris damage ([hatted.getBruteLoss()] vs [bare.getBruteLoss()])")
	qdel(scene)

/// Every MedStation test has to be registered with TEST_FOCUS, or it silently never runs.
/datum/unit_test/medstation_tests_are_focused

/datum/unit_test/medstation_tests_are_focused/Run()
	for(var/test_type in subtypesof(/datum/unit_test))
		if(!findtext("[test_type]", "/datum/unit_test/medstation_") && !(test_type in list(/datum/unit_test/patient_cases, /datum/unit_test/patient_director)))
			continue
		var/datum/unit_test/test = test_type
		TEST_ASSERT(initial(test.test_flags) & UNIT_TEST_FOCUS, "[test_type] has no TEST_FOCUS line, so it never runs")

TEST_FOCUS(/datum/unit_test/patient_cases)
TEST_FOCUS(/datum/unit_test/patient_director)
TEST_FOCUS(/datum/unit_test/medstation_ambulance)
TEST_FOCUS(/datum/unit_test/medstation_flows)
TEST_FOCUS(/datum/unit_test/medstation_field)
TEST_FOCUS(/datum/unit_test/medstation_decon)
TEST_FOCUS(/datum/unit_test/medstation_shock)
TEST_FOCUS(/datum/unit_test/medstation_hazards)
TEST_FOCUS(/datum/unit_test/medstation_vitals_monitor)
TEST_FOCUS(/datum/unit_test/medstation_infection)
TEST_FOCUS(/datum/unit_test/medstation_economy)
TEST_FOCUS(/datum/unit_test/medstation_quarantine)
TEST_FOCUS(/datum/unit_test/medstation_solo)
TEST_FOCUS(/datum/unit_test/medstation_treatability)
TEST_FOCUS(/datum/unit_test/medstation_scene_calls)
TEST_FOCUS(/datum/unit_test/medstation_calls)
TEST_FOCUS(/datum/unit_test/medstation_library)
TEST_FOCUS(/datum/unit_test/medstation_guide)
TEST_FOCUS(/datum/unit_test/medstation_levels)
TEST_FOCUS(/datum/unit_test/medstation_events)
TEST_FOCUS(/datum/unit_test/medstation_supplies)
TEST_FOCUS(/datum/unit_test/medstation_map)
TEST_FOCUS(/datum/unit_test/medstation_soak)
TEST_FOCUS(/datum/unit_test/medstation_careers)
TEST_FOCUS(/datum/unit_test/medstation_locks)
TEST_FOCUS(/datum/unit_test/medstation_rank_cases)
TEST_FOCUS(/datum/unit_test/medstation_xp_awards)
TEST_FOCUS(/datum/unit_test/medstation_career_jobs)
TEST_FOCUS(/datum/unit_test/medstation_tests_are_focused)
#endif
