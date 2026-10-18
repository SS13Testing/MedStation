/**
 * Field scenes: small randomised maps the ambulance drives to. A scene is a themed template (maintenance collapse, cargo
 * bay accident, ...) in several generated variants (tools/medstation_mapgen/scenes.py). It is loaded into reserved
 * space when a call is answered, gets a docking port for the ambulance and patients where the landmarks are, and is
 * removed again once the ambulance is back.
 */
/area/medstation_scene
	name = "Accident scene"
	icon_state = "yellow"
	requires_power = FALSE
	has_gravity = STANDARD_GRAVITY

/area/medstation_scene/maintenance
	name = "Collapsed maintenance corridor"

/area/medstation_scene/cargo
	name = "Cargo bay accident"

/area/medstation_scene/hydroponics
	name = "Hydroponics deck"

/area/medstation_scene/observation
	name = "Wrecked observation lounge"

/area/medstation_scene/fire
	name = "Burnt-out compartment"

/// Where the ambulance docks in a scene: the tile its airlock ends up on (top centre of the 7x5 parking block).
/obj/effect/landmark/ambulance_scene_dock
	name = "ambulance scene dock"

/// A spot where a patient may be lying. Only some of them get a patient.
/obj/effect/landmark/scene_patient
	name = "scene patient"

/// The dock the ambulance uses at a scene. Same size as the hospital one.
/obj/docking_port/stationary/ambulance_scene
	name = "scene dock"
	shuttle_id = "ambulance_scene"
	dir = SOUTH
	width = 7
	dwidth = 3
	height = 5

/// One kind of scene. Subtype it to add a theme (and generate its maps in scenes.py).
/datum/medstation_scene
	var/name
	/// Maps are _maps/templates/medstation_scenes/[map_file]_[1..variants].dmm
	var/map_file
	var/variants = 3
	/// Hospital level needed before this scene turns up
	var/min_level = 1
	var/weight = 10
	/// How the call describes the place
	var/location_text
	/// Weighted case types the patients here can have
	var/list/cases = list()
	var/min_patients = 1
	var/max_patients = 3

/datum/medstation_scene/maintenance
	name = "Maintenance collapse"
	map_file = "maintenance"
	location_text = "a collapsed maintenance corridor"
	cases = list(/datum/patient_case/blunt_trauma = 10, /datum/patient_case/laceration = 8, /datum/patient_case/head_injury = 4, /datum/patient_case/shrapnel = 5)

/datum/medstation_scene/cargo
	name = "Cargo bay accident"
	map_file = "cargo"
	location_text = "the cargo bay, where a stack of crates came down"
	cases = list(/datum/patient_case/blunt_trauma = 12, /datum/patient_case/laceration = 6, /datum/patient_case/head_injury = 6, /datum/patient_case/shrapnel = 3)

/datum/medstation_scene/hydroponics
	name = "Hydroponics deck"
	map_file = "hydroponics"
	location_text = "the hydroponics deck, where a chemical spill sent people to the floor"
	cases = list(/datum/patient_case/poisoning = 12, /datum/patient_case/respiratory = 8, /datum/patient_case/eye_injury = 6, /datum/patient_case/appendicitis = 4)

/datum/medstation_scene/observation
	name = "Observation lounge"
	map_file = "observation"
	location_text = "the observation lounge, where a window failed"
	cases = list(/datum/patient_case/shrapnel = 10, /datum/patient_case/laceration = 8, /datum/patient_case/respiratory = 6, /datum/patient_case/blunt_trauma = 6)

/datum/medstation_scene/fire
	name = "Compartment fire"
	map_file = "fire"
	location_text = "a compartment that has just been through a fire"
	min_level = 2
	cases = list(/datum/patient_case/burns = 14, /datum/patient_case/respiratory = 10, /datum/patient_case/heart_attack = 2)

/// A scene that is actually loaded: its reserved map block, the ambulance's dock in it and where the patients can lie.
/datum/field_scene
	var/datum/medstation_scene/template
	var/datum/turf_reservation/reservation
	var/obj/docking_port/stationary/ambulance_scene/dock
	/// Turfs with a patient landmark on them
	var/list/turf/patient_spots = list()
	var/created_at

/datum/field_scene/New(datum/medstation_scene/template)
	src.template = template
	created_at = world.time

/datum/field_scene/Destroy(force)
	unload()
	template = null
	return ..()

/// Loads a random variant of the template into reserved space, makes the dock and records the patient spots.
/datum/field_scene/proc/load(variant)
	variant ||= rand(1, template.variants)
	var/load_path = "_maps/templates/medstation_scenes/[template.map_file]_[variant].dmm"
	if(!fexists(load_path))
		CRASH("field scene [template.type] has no map at [load_path]")
	var/datum/parsed_map/measured = load_map(file(load_path), measure_only = TRUE)
	if(isnull(measured?.parsed_bounds))
		CRASH("could not measure the field scene map [load_path]")
	var/width = measured.parsed_bounds[MAP_MAXX] - measured.parsed_bounds[MAP_MINX] + 1
	var/height = measured.parsed_bounds[MAP_MAXY] - measured.parsed_bounds[MAP_MINY] + 1
	reservation = SSmapping.request_turf_block_reservation(width, height, 1)
	if(!reservation)
		return FALSE
	var/turf/bottom_left = reservation.bottom_left_turfs[1]
	var/turf/top_right = reservation.top_right_turfs[1]
	load_map(file(load_path), bottom_left.x, bottom_left.y, bottom_left.z, z_upper = 1, z_lower = 1)

	var/list/loaded_atoms = list()
	var/list/loaded_turfs = list()
	var/list/loaded_areas = list()
	for(var/turf/loaded_turf as anything in block(bottom_left, top_right))
		loaded_turfs += loaded_turf
		loaded_areas |= get_area(loaded_turf)
		for(var/atom/thing as anything in (loaded_turf.get_all_contents() - loaded_turf))
			loaded_atoms |= thing
	SSatoms.InitializeAtoms(loaded_areas + loaded_atoms + loaded_turfs)

	var/turf/dock_turf
	for(var/obj/effect/landmark/landmark in loaded_atoms)
		if(istype(landmark, /obj/effect/landmark/ambulance_scene_dock))
			dock_turf = get_turf(landmark)
		else if(istype(landmark, /obj/effect/landmark/scene_patient))
			patient_spots += get_turf(landmark)
		else
			continue
		qdel(landmark)
	if(!dock_turf)
		CRASH("field scene map [load_path] has no ambulance_scene_dock landmark")
	SSshuttle.assoc_stationary -= "ambulance_scene" // so the new dock keeps its id instead of getting a numbered one
	dock = new(dock_turf)
	dock.name = "Scene: [template.name]"
	return TRUE

/// Picks a case type for a patient at this scene.
/datum/field_scene/proc/pick_case()
	return pick_weight(template.cases)

/// Removes the dock and the map. Anything still in the scene goes with it.
/datum/field_scene/proc/unload()
	if(dock)
		qdel(dock, force = TRUE)
		dock = null
	if(reservation)
		qdel(reservation)
		reservation = null
	patient_spots.Cut()

/// Is this atom somewhere inside the loaded scene?
/datum/field_scene/proc/contains(atom/thing)
	var/turf/where = get_turf(thing)
	return !!where && !!reservation && (where in reservation.reserved_turfs)
