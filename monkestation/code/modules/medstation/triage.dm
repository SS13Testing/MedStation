/// A coloured triage tag tied to a patient. Re-tagging replaces the colour.
/datum/component/triage_tag
	dupe_mode = COMPONENT_DUPE_UNIQUE_PASSARGS
	var/level = TRIAGE_GREEN

/datum/component/triage_tag/Initialize(level = TRIAGE_GREEN)
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE
	src.level = level

/datum/component/triage_tag/InheritComponent(datum/component/new_comp, i_am_original, level = TRIAGE_GREEN)
	src.level = level

/datum/component/triage_tag/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))

/datum/component/triage_tag/UnregisterFromParent()
	UnregisterSignal(parent, COMSIG_ATOM_EXAMINE)

/datum/component/triage_tag/proc/on_examine(atom/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	examine_list += span_notice("A [triage_level_name(level)] triage tag is tied to [source.p_their()] wrist.")

/proc/triage_level_name(level)
	switch(level)
		if(TRIAGE_GREEN)
			return "green (minor)"
		if(TRIAGE_YELLOW)
			return "yellow (serious)"
		if(TRIAGE_RED)
			return "red (critical)"
	return "black (beyond help)"

/// Ties triage tags to patients. Use it in hand to change the colour, then click a patient.
/obj/item/triage_tagger
	name = "triage tagger"
	desc = "Ties a coloured triage tag to a patient so everyone knows who to see first: green is minor, yellow is serious, red is critical, black is beyond help. Use it in your hand to change the colour."
	icon = 'icons/obj/service/bureaucracy.dmi'
	icon_state = "stamp-ok"
	w_class = WEIGHT_CLASS_TINY
	var/level = TRIAGE_GREEN

/obj/item/triage_tagger/examine(mob/user)
	. = ..()
	. += span_notice("It is set to [triage_level_name(level)].")

/obj/item/triage_tagger/attack_self(mob/user)
	level = (level + 1) % 4
	to_chat(user, span_notice("You set [src] to [triage_level_name(level)]."))
	return TRUE

/obj/item/triage_tagger/interact_with_atom(atom/interacting_with, mob/living/user, list/modifiers)
	if(!ishuman(interacting_with))
		return NONE
	var/mob/living/carbon/human/patient = interacting_with
	patient.AddComponent(/datum/component/triage_tag, level)
	SSpatient_director.note_tag(patient, level)
	user.visible_message(span_notice("[user] ties a [triage_level_name(level)] triage tag to [patient]."), span_notice("You tie a [triage_level_name(level)] triage tag to [patient]."))
	return ITEM_INTERACT_SUCCESS
