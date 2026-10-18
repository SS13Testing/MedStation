#ifdef UNIT_TESTS
/// Every patient case must inflict something, not be cured straight away, and carry intake chart text.
/datum/unit_test/patient_cases

/datum/unit_test/patient_cases/Run()
	for(var/case_type in subtypesof(/datum/patient_case))
		var/datum/patient_case/case = new case_type()
		var/mob/living/carbon/human/patient = allocate(/mob/living/carbon/human/consistent)
		case.apply(patient)
		patient.updatehealth()
		TEST_ASSERT(!case.is_resolved(patient), "[case_type] is already resolved straight after apply()")
		TEST_ASSERT(length(case.symptoms) && length(case.history), "[case_type] has no symptoms/history for the chart")
		TEST_ASSERT(case.diagnosis != "Unknown", "[case_type] has no diagnosis")
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

/// The welcome guide exists and covers the main points.
/datum/unit_test/medstation_guide

/datum/unit_test/medstation_guide/Run()
	var/text = hospital_guide_text()
	for(var/keyword in list("ambulance", "walk-ins", "intake chart", "Triage", "hospital terminal", "Rating", "shuttle"))
		TEST_ASSERT(findtext(text, keyword), "the hospital guide doesn't mention [keyword]")

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
		TEST_ASSERT(length(supply.contents_list), "[supply_name] has no contents")
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
	for(var/job_landmark in list("medical_doctor", "paramedic", "chemist", "virologist", "psychologist", "geneticist", "chief_medical_officer"))
		TEST_ASSERT(findtext(map_text, "/obj/effect/landmark/start/[job_landmark]"), "map has no [job_landmark] start landmark")

TEST_FOCUS(/datum/unit_test/patient_cases)
TEST_FOCUS(/datum/unit_test/patient_director)
TEST_FOCUS(/datum/unit_test/medstation_ambulance)
TEST_FOCUS(/datum/unit_test/medstation_guide)
TEST_FOCUS(/datum/unit_test/medstation_levels)
TEST_FOCUS(/datum/unit_test/medstation_events)
TEST_FOCUS(/datum/unit_test/medstation_supplies)
TEST_FOCUS(/datum/unit_test/medstation_map)
#endif
