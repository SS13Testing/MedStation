/**
 * Chemical contamination. Patients from chemical exposures (poisoning, fumes, eye splashes) arrive covered in residue: it
 * keeps hurting them and they can't be discharged until they have been through a shower.
 */
/datum/component/contaminated

/datum/component/contaminated/Initialize()
	if(!ishuman(parent))
		return COMPONENT_INCOMPATIBLE

/datum/component/contaminated/RegisterWithParent()
	RegisterSignal(parent, COMSIG_ATOM_EXAMINE, PROC_REF(on_examine))
	RegisterSignal(parent, COMSIG_COMPONENT_CLEAN_ACT, PROC_REF(on_wash))

/datum/component/contaminated/UnregisterFromParent()
	UnregisterSignal(parent, list(COMSIG_ATOM_EXAMINE, COMSIG_COMPONENT_CLEAN_ACT))

/datum/component/contaminated/proc/on_examine(atom/source, mob/user, list/examine_list)
	SIGNAL_HANDLER
	examine_list += span_warning("[source.p_Theyre()] covered in a chemical residue. A shower would wash it off.")

/datum/component/contaminated/proc/on_wash(atom/source, clean_types)
	SIGNAL_HANDLER
	if(!(clean_types & CLEAN_TYPE_BLOOD)) // any proper wash (a shower passes CLEAN_WASH)
		return NONE
	var/mob/living/carbon/human/patient = parent
	to_chat(patient, span_notice("The chemical residue washes away."))
	patient.visible_message(span_notice("The chemical residue washes off [patient]."))
	qdel(src)
	return COMPONENT_CLEANED

/// Is this patient still covered in chemicals?
/proc/is_contaminated(mob/living/carbon/human/patient)
	return !!patient.GetComponent(/datum/component/contaminated)
