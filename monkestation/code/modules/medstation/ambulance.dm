GLOBAL_LIST_EMPTY(ambulance_park_points)
GLOBAL_LIST_EMPTY(patient_walkin_points)

/// Centre of the 3x3 space the ambulance parks in. Face the ambulance east: its rear (and the patients) end up on the west side.
/obj/effect/landmark/ambulance_park
	name = "ambulance park"

/obj/effect/landmark/ambulance_park/Initialize(mapload)
	. = ..()
	GLOB.ambulance_park_points += src

/obj/effect/landmark/ambulance_park/Destroy()
	GLOB.ambulance_park_points -= src
	return ..()

/// Just inside the waiting room door: walk-in patients appear here and head for a chair.
/obj/effect/landmark/patient_walkin
	name = "patient walk-in"

/obj/effect/landmark/patient_walkin/Initialize(mapload)
	. = ..()
	GLOB.patient_walkin_points += src

/obj/effect/landmark/patient_walkin/Destroy()
	GLOB.patient_walkin_points -= src
	return ..()

/// Invisible solid tile so the 3x3 ambulance can't be walked through.
/obj/effect/ambulance_blocker
	name = "ambulance"
	anchored = TRUE
	density = TRUE
	invisibility = INVISIBILITY_ABSTRACT

/obj/effect/ambulance_blocker/singularity_act()
	return

/obj/effect/ambulance_blocker/ex_act(severity, target)
	return FALSE

/**
 * The ambulance that brings patients in. It is not drivable (yet): the patient director has it pull into the
 * bay, the patients get wheeled off the back, and it leaves again after a while.
 *
 * Sprite: 'ambulance' state from the crimson-grid cars sheet, see icons/README.md.
 */
/obj/structure/medstation_ambulance
	name = "ambulance"
	desc = "A hospital ambulance. Its rear doors are open for unloading."
	icon = 'monkestation/code/modules/medstation/icons/ambulance.dmi'
	icon_state = "ambulance"
	dir = EAST
	pixel_x = -32
	pixel_y = -32
	layer = ABOVE_MOB_LAYER
	anchored = TRUE
	density = TRUE
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	/// How far, in pixels, it slides when arriving and leaving
	var/slide_distance = 128
	var/list/obj/effect/ambulance_blocker/blockers = list()

/obj/structure/medstation_ambulance/Initialize(mapload)
	. = ..()
	for(var/turf/around as anything in RANGE_TURFS(1, src))
		if(around == loc)
			continue
		blockers += new /obj/effect/ambulance_blocker(around)

/obj/structure/medstation_ambulance/Destroy()
	QDEL_LIST(blockers)
	return ..()

/// Slides in from the west with the siren chime.
/obj/structure/medstation_ambulance/proc/drive_in()
	alpha = 0
	pixel_x = initial(pixel_x) - slide_distance
	playsound(loc, 'sound/machines/chime.ogg', 60, FALSE, 10)
	animate(src, pixel_x = initial(pixel_x), alpha = 255, time = 3 SECONDS, easing = SINE_EASING | EASE_OUT)

/// Slides out the way it came, then goes away for good.
/obj/structure/medstation_ambulance/proc/drive_off()
	if(QDELETED(src))
		return
	visible_message(span_notice("[src] pulls out of the bay."))
	QDEL_LIST(blockers)
	animate(src, pixel_x = initial(pixel_x) + slide_distance, alpha = 0, time = 3 SECONDS, easing = SINE_EASING | EASE_IN)
	QDEL_IN(src, 3 SECONDS)
