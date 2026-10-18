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

/// The map must have what the hospital needs to run.
/datum/unit_test/medstation_map

/datum/unit_test/medstation_map/Run()
	TEST_ASSERT(length(GLOB.patient_spawn_points), "map has no /obj/effect/landmark/patient_spawn")
	TEST_ASSERT(length(GLOB.ambulance_park_points), "map has no /obj/effect/landmark/ambulance_park")
	TEST_ASSERT(length(GLOB.patient_walkin_points), "map has no /obj/effect/landmark/patient_walkin")
	TEST_ASSERT(length(SSjob.latejoin_trackers), "map has no latejoin landmarks")
	var/found_doctor_spawn = FALSE
	for(var/obj/effect/landmark/start/start as anything in GLOB.start_landmarks_list)
		if(start.name == JOB_MEDICAL_DOCTOR)
			found_doctor_spawn = TRUE
	TEST_ASSERT(found_doctor_spawn, "map has no medical doctor start landmark")

TEST_FOCUS(/datum/unit_test/patient_cases)
TEST_FOCUS(/datum/unit_test/patient_director)
TEST_FOCUS(/datum/unit_test/medstation_ambulance)
TEST_FOCUS(/datum/unit_test/medstation_map)
#endif
