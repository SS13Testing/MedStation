/**
 * Hospital events: things that happen to the hospital as a whole, on top of the steady trickle of patients.
 * They replace the storyteller's random events. The patient director rolls one every so often.
 * To add one, make a subtype, set name/weight/min_staff and write start_event().
 */
/datum/hospital_event
	var/name
	/// Relative chance to be picked
	var/weight = 10
	/// Needs at least this many medical staff on the station
	var/min_staff = 1
	/// Shown to the staff when it starts
	var/announcement

/// Does the event. `staff` is the number of medical staff on duty.
/datum/hospital_event/proc/start_event(datum/controller/subsystem/patient_director/director, staff)
	return

/// Everyone from a bad crash arrives at once: a full ambulance of serious cases and some walking wounded.
/datum/hospital_event/mass_casualty
	name = "Mass casualty incident"
	weight = 8
	min_staff = 2
	announcement = "MASS CASUALTY INCIDENT: a transit ring collision. Expect an ambulance full of serious patients and walking wounded."

/datum/hospital_event/mass_casualty/start_event(datum/controller/subsystem/patient_director/director, staff)
	director.launch_ambulance(staff, room = 3, count = 3)
	for(var/i in 1 to clamp(staff + 1, 2, 5))
		addtimer(CALLBACK(director, TYPE_PROC_REF(/datum/controller/subsystem/patient_director, spawn_patient), null, null, staff, PATIENT_ARRIVE_WALKIN), rand(5, 40) SECONDS)

/// A wave of flu cases walks in and fills the waiting room.
/datum/hospital_event/outbreak
	name = "Flu outbreak"
	weight = 10
	min_staff = 1
	announcement = "FLU OUTBREAK: several people with a fever are heading for the waiting room. Keep the sick away from the wards."

/datum/hospital_event/outbreak/start_event(datum/controller/subsystem/patient_director/director, staff)
	for(var/i in 1 to clamp(staff + 2, 3, 6))
		addtimer(CALLBACK(director, TYPE_PROC_REF(/datum/controller/subsystem/patient_director, spawn_patient), /datum/patient_case/flu, null, staff, PATIENT_ARRIVE_WALKIN), (i * rand(8, 20)) SECONDS)

/// Patients keep coming faster for a few minutes.
/datum/hospital_event/rush_hour
	name = "Rush hour"
	weight = 12
	min_staff = 1
	announcement = "RUSH HOUR: it is going to be busy for the next few minutes."

/datum/hospital_event/rush_hour/start_event(datum/controller/subsystem/patient_director/director, staff)
	director.rush_until = world.time + 5 MINUTES
