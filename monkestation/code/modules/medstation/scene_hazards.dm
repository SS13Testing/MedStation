/**
 * Scene hazards: things at a field scene that hurt the crew as well as the patients. A hazard is picked by the scene type and
 * pulses every director tick while the ambulance is out. The ambulance carries the gear that counters them (gas masks for
 * fumes and smoke, hard hats for falling debris). See scenes in field_scenes.dm.
 */
/datum/scene_hazard
	var/name = "Hazard"
	/// Said to the crew in the call notes
	var/warning = "Take care."
	/// Ticks (director fires) between pulses
	var/period = 1
	var/ticks = 0

/// Called every director tick while the ambulance is at the scene.
/datum/scene_hazard/proc/tick_hazard(datum/field_scene/scene)
	ticks++
	if(ticks % period)
		return
	pulse(scene)

/// The living humans (crew and patients) inside the scene.
/datum/scene_hazard/proc/people_in(datum/field_scene/scene)
	. = list()
	for(var/mob/living/carbon/human/person as anything in GLOB.human_list)
		if(person.stat != DEAD && scene.contains(person))
			. += person

/datum/scene_hazard/proc/pulse(datum/field_scene/scene)
	return

/// Is this person wearing something that filters the air?
/proc/has_filtered_air(mob/living/carbon/human/person)
	return istype(person.wear_mask, /obj/item/clothing/mask/gas) || istype(person.wear_mask, /obj/item/clothing/mask/breath)

/// Toxic fumes: everyone without a mask is poisoned a little every pulse.
/datum/scene_hazard/fumes
	name = "Toxic fumes"
	warning = "There are chemical fumes in the air. Wear a gas mask from the ambulance locker, and mask the patients too."

/datum/scene_hazard/fumes/pulse(datum/field_scene/scene)
	for(var/mob/living/carbon/human/person as anything in people_in(scene))
		if(has_filtered_air(person))
			continue
		person.adjustToxLoss(2, forced = TRUE)
		to_chat(person, span_warning("You cough and choke on the fumes."))

/// Smoke: unmasked people lose breath.
/datum/scene_hazard/smoke
	name = "Smoke"
	warning = "The compartment is full of smoke. Wear a gas mask from the ambulance locker, and mask the patients too."

/datum/scene_hazard/smoke/pulse(datum/field_scene/scene)
	for(var/mob/living/carbon/human/person as anything in people_in(scene))
		if(has_filtered_air(person))
			continue
		person.adjustOxyLoss(4, forced = TRUE)
		to_chat(person, span_warning("The smoke burns your lungs."))

/// Unstable structure: debris drops on somebody every so often, after a warning creak. Hard hats take the edge off.
/datum/scene_hazard/collapse
	name = "Unstable structure"
	warning = "The structure is unstable and debris may fall. Wear a hard hat from the ambulance locker and get the patients out quickly."
	period = 4
	/// Damage to somebody without a hard hat, and with one
	var/bare_damage = 14
	var/hat_damage = 3

/datum/scene_hazard/collapse/pulse(datum/field_scene/scene)
	var/list/people = people_in(scene)
	if(!length(people))
		return
	var/mob/living/carbon/human/target = pick(people)
	var/turf/spot = get_turf(target)
	for(var/mob/living/carbon/human/person as anything in people)
		to_chat(person, span_userdanger("The ceiling groans and creaks overhead!"))
	addtimer(CALLBACK(src, PROC_REF(drop), spot), 5 SECONDS)

/// Debris comes down on a tile.
/datum/scene_hazard/collapse/proc/drop(turf/spot)
	if(QDELETED(spot))
		return
	playsound(spot, 'sound/effects/meteorimpact.ogg', 40, TRUE)
	for(var/mob/living/carbon/human/person in spot)
		var/hat = istype(person.head, /obj/item/clothing/head/utility/hardhat) || istype(person.head, /obj/item/clothing/head/helmet)
		person.apply_damage(hat ? hat_damage : bare_damage, BRUTE, pick(GLOB.all_body_zones))
		person.visible_message(span_danger("Debris crashes down on [person]!"), span_userdanger("Debris crashes down on you!"))
