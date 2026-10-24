/// Nobody drove the ambulance out to a scene that long after the call was answered: the call is lost
#define SCENE_DEPART_TIMEOUT (5 MINUTES)
/// The ambulance has been home this long: the scene is cleared away
#define SCENE_CLEANUP_DELAY (45 SECONDS)

/**
 * The glue between ambulance calls and field scenes. With a paramedic on duty a call is for a scene: answering it loads the
 * scene with its patients (lying where they were hurt) and the crew drive the real ambulance out to it, treat them and bring
 * them back. Anybody left behind is lost. See ambulance_calls.dm for the calls and field_scenes.dm for the scenes.
 */

/// The ambulance shuttle, or null if the map has none.
/datum/controller/subsystem/patient_director/proc/ambulance_shuttle()
	for(var/obj/docking_port/mobile/port as anything in SSshuttle.mobile_docking_ports)
		if(port.shuttle_id == "ambulance")
			return port

/// The ambulance's dock in the hospital, or null.
/datum/controller/subsystem/patient_director/proc/ambulance_home_dock()
	for(var/obj/docking_port/stationary/dock as anything in SSshuttle.stationary_docking_ports)
		if(dock.shuttle_id == "ambulance_home")
			return dock

/// Is the ambulance shuttle away from its dock in the hospital (or on the road)?
/datum/controller/subsystem/patient_director/proc/ambulance_away_from_home()
	var/obj/docking_port/mobile/ambulance = ambulance_shuttle()
	if(!ambulance)
		return FALSE
	return ambulance.mode != SHUTTLE_IDLE || ambulance.get_docked() != ambulance_home_dock()

/// A scene type this hospital can send the ambulance to (by level and weight), or null if there is no ambulance to send.
/datum/controller/subsystem/patient_director/proc/pick_scene_type()
	if(!ambulance_shuttle())
		return null
	var/list/candidates = list()
	for(var/scene_type in subtypesof(/datum/medstation_scene))
		var/datum/medstation_scene/scene = scene_type
		if(initial(scene.name) && initial(scene.min_level) <= level)
			candidates[scene_type] = initial(scene.weight)
	if(length(candidates))
		return pick_weight(candidates)

/// Loads the scene for a call and puts its patients in it. Returns FALSE if that can't be done right now.
/datum/controller/subsystem/patient_director/proc/start_scene(datum/ambulance_call/emergency)
	if(active_scene || ambulance_away_from_home())
		return FALSE
	var/datum/field_scene/scene = new(new emergency.scene_type())
	if(!scene.load())
		qdel(scene)
		return FALSE
	scene.urgency = emergency.urgency()
	active_scene = scene
	if(scene.hazard)
		dispatch("Hazard at [scene.template.location_text]: [scene.hazard.warning]")
	var/staff = max(1, count_staff())
	var/list/spots = scene.patient_spots.Copy()
	for(var/case_type in emergency.case_types)
		if(!length(spots))
			break
		var/turf/spot = pick_n_take(spots)
		var/datum/patient_record/record = spawn_patient(case_type, spot, staff, PATIENT_ARRIVE_FIELD)
		if(record) // their clocks have been running since the call came in
			record.deadline = max(world.time + 45 SECONDS, record.deadline - (world.time - emergency.posted_at))
	return TRUE

/// Called every director tick: sends nobody-came scenes away, and clears the scene once the ambulance is home again.
/datum/controller/subsystem/patient_director/proc/process_scene()
	var/datum/field_scene/scene = active_scene
	if(!scene)
		return
	if(ambulance_away_from_home())
		scene.departed = TRUE
		scene.returned_at = null
		scene.hazard?.tick_hazard(scene)
		return
	if(scene.departed)
		scene.returned_at ||= world.time
		if(world.time >= scene.returned_at + SCENE_CLEANUP_DELAY)
			end_scene(FALSE)
		return
	if(world.time >= scene.created_at + SCENE_DEPART_TIMEOUT)
		end_scene(TRUE)

/// Clears the scene. Patients still in it are lost (or, if nobody ever went, the call just counts as missed).
/datum/controller/subsystem/patient_director/proc/end_scene(abandoned)
	var/datum/field_scene/scene = active_scene
	if(!scene)
		return
	active_scene = null
	// anyone still out there is brought home
	var/obj/docking_port/stationary/home = ambulance_home_dock()
	var/turf/safe = home ? get_step(home, NORTH) : null
	for(var/mob/living/player as anything in GLOB.alive_player_list)
		if(safe && scene.contains(player))
			player.forceMove(safe)
			to_chat(player, span_notice("The scene is cleared and you are brought back to the hospital."))
	for(var/datum/patient_record/record as anything in active.Copy())
		if(record.arrival_mode != PATIENT_ARRIVE_FIELD)
			continue
		var/mob/living/carbon/human/patient = record.patient_ref?.resolve()
		if(QDELETED(patient) || !scene.contains(patient))
			continue // brought back to the hospital: a normal patient from here on
		if(abandoned)
			active -= record
		else if(patient.stat == DEAD)
			finish(record, PATIENT_OUTCOME_DIED)
		else
			finish(record, PATIENT_OUTCOME_ABANDONED)
	if(abandoned)
		missed_calls++
		reputation -= scene.urgency
		dispatch("Nobody went out to [scene.template.location_text]. The patients were taken elsewhere. Reputation falls.")
		update_level()
	qdel(scene)

#undef SCENE_DEPART_TIMEOUT
#undef SCENE_CLEANUP_DELAY
