/**
 * The hospital remembers: its reputation (so its level), whether the opening training period is over, lifetime totals and the
 * cases the staff have already seen survive from one round to the next. Saved to a JSON file each time a patient is finished.
 * Delete the file to start the hospital from scratch. Config: MEDSTATION_PERSIST_HOSPITAL 0 turns this off.
 */
/datum/controller/subsystem/patient_director
	/// Where the hospital's progress is kept
	var/hospital_save_path = "data/medstation/hospital.json"
	/// Set by load_hospital(): tells the unit tests (and the status text) what came from a previous round
	var/loaded_from_save = FALSE
	/// Patients cured and lost over every round (this one included once it has been saved)
	var/lifetime_treated = 0
	var/lifetime_deceased = 0
	/// Switch for the tests: they must not touch the real save
#ifdef UNIT_TESTS
	var/persist_hospital = FALSE
#else
	var/persist_hospital = TRUE
#endif

/datum/controller/subsystem/patient_director/proc/persistence_enabled()
	return persist_hospital && CONFIG_GET(number/medstation_persist_hospital)

/// What gets saved.
/datum/controller/subsystem/patient_director/proc/hospital_save_data()
	var/list/seen = list()
	for(var/case_type in discovered)
		seen += "[case_type]"
	return list(
		"reputation" = reputation,
		"training_done" = training_done,
		"lifetime_treated" = lifetime_treated + treated,
		"lifetime_deceased" = lifetime_deceased + deceased,
		"discovered" = seen,
	)

/datum/controller/subsystem/patient_director/proc/save_hospital()
	if(!persistence_enabled())
		return FALSE
	rustg_file_write(json_encode(hospital_save_data()), hospital_save_path)
	return TRUE

/// Loads the saved hospital, if there is one. Called when the first patient is scheduled.
/datum/controller/subsystem/patient_director/proc/load_hospital()
	if(!persistence_enabled() || !fexists(hospital_save_path))
		return FALSE
	var/list/data = safe_json_decode(rustg_file_read(hospital_save_path))
	if(!islist(data))
		return FALSE
	reputation = isnum(data["reputation"]) ? data["reputation"] : reputation
	if(data["training_done"])
		training_done = TRUE
	lifetime_treated = isnum(data["lifetime_treated"]) ? data["lifetime_treated"] : 0
	lifetime_deceased = isnum(data["lifetime_deceased"]) ? data["lifetime_deceased"] : 0
	if(islist(data["discovered"]))
		for(var/path_text in data["discovered"])
			var/case_path = text2path(path_text)
			if(ispath(case_path, /datum/patient_case))
				discovered[case_path] = TRUE
	loaded_from_save = TRUE
	update_level()
	return TRUE
